import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/tenant/church_profile_loader.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Resultado da carga do Cadastro da Igreja — leitura directa `igrejas/{churchId}`.
class ChurchCadastroLoadResult {
  const ChurchCadastroLoadResult({
    required this.seedTenantId,
    required this.churchId,
    required this.data,
    required this.logoStoragePath,
    required this.readSource,
    this.softError,
  });

  final String seedTenantId;
  final String churchId;
  final Map<String, dynamic> data;
  final String logoStoragePath;
  final String readSource;

  /// Falha não fatal — formulário abre mesmo assim (retry em background).
  final String? softError;

  ChurchDataLoadResult toChurchDataLoadResult() => ChurchDataLoadResult(
        seedTenantId: seedTenantId,
        churchId: churchId,
        firestorePath: 'igrejas/$churchId',
        data: data,
        fieldCount: data.length,
        loadedAt: DateTime.now(),
        readSource: readSource,
        logoStoragePath: logoStoragePath,
      );
}

/// Carga canónica do Cadastro — **sempre** `igrejas/{churchId}` (sem cluster/resolver).
abstract final class ChurchCadastroLoadService {
  ChurchCadastroLoadService._();

  /// Perfil mínimo útil (nome + pelo menos endereço ou gestor).
  static const int kMinProfileScore = 5;

  static String _logoPathFor(String churchId, Map<String, dynamic>? data) {
    return ChurchBrandService.logoPathFromData(data, churchId: churchId) ??
        ChurchStorageLayout.churchIdentityLogoPath(churchId);
  }

  static bool _isUsableProfile(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    return TenantResolverService.churchProfileRichnessScore(data) >=
        kMinProfileScore;
  }

  static ChurchCadastroLoadResult _resultFromData({
    required String seed,
    required String churchId,
    required Map<String, dynamic> data,
    required String readSource,
    String? softError,
  }) =>
      ChurchCadastroLoadResult(
        seedTenantId: seed.isNotEmpty ? seed : churchId,
        churchId: churchId,
        data: Map<String, dynamic>.from(data),
        logoStoragePath: _logoPathFor(churchId, data),
        readSource: readSource,
        softError: softError,
      );

  /// Leitura completa do doc raiz — cache Firestore → servidor (timeout longo na web).
  static Future<({String docId, Map<String, dynamic> data})?> _readFirestoreDocFull(
    String churchId,
  ) async {
    final id = ChurchPanelTenant.resolve(churchId);
    if (id.isEmpty) return null;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final ref = ChurchFirestoreAccess.churchDoc(id);

    try {
      final cacheSnap = await ref
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 5));
      if (cacheSnap.exists && cacheSnap.data() != null) {
        final data = Map<String, dynamic>.from(cacheSnap.data()!);
        if (_isUsableProfile(data)) {
          return (docId: cacheSnap.id, data: data);
        }
      }
    } catch (_) {}

    try {
      Future<DocumentSnapshot<Map<String, dynamic>>> readServer() =>
          FirestoreReadResilience.getDocument(
            ref,
            cacheKey: 'cadastro_igreja_full_$id',
            maxAttempts: kIsWeb ? 5 : 3,
            attemptTimeout: kIsWeb
                ? const Duration(seconds: 24)
                : const Duration(seconds: 16),
          );

      final snap = kIsWeb
          ? await FirestoreWebGuard.runWithWebRecovery(
              readServer,
              maxAttempts: 4,
            ).timeout(const Duration(seconds: 100))
          : await readServer().timeout(const Duration(seconds: 50));

      if (!snap.exists || snap.data() == null) return null;
      return (docId: snap.id, data: Map<String, dynamic>.from(snap.data()!));
    } on TimeoutException {
      rethrow;
    } on ChurchRepositoryException {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  /// Ordem: sessão (perfil rico) → cache Hive → Firestore cache+servidor → direct read → loadByChurchId.
  static Future<ChurchCadastroLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final seed = seedTenantId.trim();
    final churchId = ChurchPanelTenant.resolve(
      seed.isNotEmpty ? seed : (ChurchContextService.currentChurchId ?? ''),
    );

    if (churchId.isEmpty) {
      throw ChurchRepositoryException(
        'ID da igreja não informado.',
        seedTenantId: seed,
      );
    }

    final defaultLogoPath = ChurchStorageLayout.churchIdentityLogoPath(churchId);

    if (!forceRefresh) {
      final ctxId = ChurchContextService.currentChurchId?.trim() ?? '';
      final ctxData = ChurchContextService.currentChurchData;
      if (ctxData != null &&
          ctxId.isNotEmpty &&
          ChurchPanelTenant.resolve(ctxId) == churchId &&
          _isUsableProfile(ctxData)) {
        return _resultFromData(
          seed: seed,
          churchId: churchId,
          data: ctxData,
          readSource: 'session_context',
        );
      }
    }

    if (!forceRefresh) {
      final cached = await ChurchPanelLocalCache.readMap(
        churchId: churchId,
        module: ChurchPanelLocalCache.moduleCadastro,
      );
      if (cached != null && _isUsableProfile(cached)) {
        return _resultFromData(
          seed: seed,
          churchId: churchId,
          data: cached,
          readSource: 'local_cache',
        );
      }
    }

    Object? directError;
    try {
      final full = await _readFirestoreDocFull(churchId);
      if (full != null && full.data.isNotEmpty) {
        return _resultFromData(
          seed: seed,
          churchId: full.docId,
          data: full.data,
          readSource: 'firestore_full_doc',
        );
      }
    } on TimeoutException catch (e) {
      directError = e;
    } on ChurchRepositoryException catch (e) {
      directError = e;
    } catch (e) {
      directError = e;
    }

    try {
      final hit = await IgrejaDirectFirestoreReads.readIgrejaDoc(churchId);
      if (hit != null && hit.data.isNotEmpty) {
        return _resultFromData(
          seed: seed,
          churchId: hit.docId,
          data: hit.data,
          readSource: 'direct_igrejas_doc',
        );
      }
    } on TimeoutException catch (e) {
      directError ??= e;
    } on ChurchRepositoryException catch (e) {
      directError ??= e;
    } catch (e) {
      directError ??= e;
    }

    try {
      final loaded = await ChurchRepository.loadByChurchId(
        churchId,
        seedTenantId: seed.isNotEmpty ? seed : churchId,
        userUid: null,
      );
      if (loaded.data.isNotEmpty) {
        return _resultFromData(
          seed: seed,
          churchId: loaded.churchId,
          data: loaded.data,
          readSource: loaded.readSource,
        );
      }
    } catch (e) {
      directError ??= e;
    }

    final errMsg = directError is ChurchRepositoryException
        ? directError.message
        : directError?.toString();

    return ChurchCadastroLoadResult(
      seedTenantId: seed.isNotEmpty ? seed : churchId,
      churchId: churchId,
      data: const {},
      logoStoragePath: defaultLogoPath,
      readSource: 'shell_fallback',
      softError: errMsg ??
          'Não foi possível sincronizar agora. Toque em Atualizar.',
    );
  }

  /// Persiste perfil completo após leitura bem-sucedida.
  static Future<void> persistAfterLoad(ChurchCadastroLoadResult result) async {
    if (result.data.isEmpty) return;
    ChurchContextService.bindChurchData(
      churchId: result.churchId,
      data: result.data,
    );
    await ChurchPanelLocalCache.saveMap(
      churchId: result.churchId,
      module: ChurchPanelLocalCache.moduleCadastro,
      data: result.data,
    );
  }
}
