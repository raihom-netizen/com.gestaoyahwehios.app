import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
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

/// Carga canónica do Cadastro — **uma** leitura Firestore via [ChurchRepository].
///
/// Web = Android = iOS: sessão → cache Hive → `loadByChurchId` (sem leituras triplicadas).
abstract final class ChurchCadastroLoadService {
  ChurchCadastroLoadService._();

  /// Perfil mínimo útil (nome + pelo menos endereço ou gestor).
  static const int kMinProfileScore = 5;

  static Duration get _networkTimeout =>
      kIsWeb ? const Duration(seconds: 15) : const Duration(seconds: 20);

  static String _logoPathFor(String churchId, Map<String, dynamic>? data) {
    return ChurchBrandService.logoPathFromData(data, churchId: churchId) ??
        ChurchStorageLayout.churchIdentityLogoPath(churchId);
  }

  static int _profileScore(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return 0;
    return TenantResolverService.churchProfileRichnessScore(data);
  }

  static bool _isUsableProfile(Map<String, dynamic>? data) =>
      _profileScore(data) >= kMinProfileScore;

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

  static String _resolveChurchId(String seedTenantId) {
    return ChurchPanelTenant.resolve(
      seedTenantId.trim().isNotEmpty
          ? seedTenantId.trim()
          : (ChurchContextService.currentChurchId ?? ''),
    );
  }

  /// Fontes locais instantâneas (sessão + Hive) — sem rede.
  static Future<ChurchCadastroLoadResult?> tryLocalSources({
    required String seedTenantId,
  }) async {
    final seed = seedTenantId.trim();
    final churchId = _resolveChurchId(seed);
    if (churchId.isEmpty) return null;

    final ctxId = ChurchContextService.currentChurchId?.trim() ?? '';
    final ctxData = ChurchContextService.currentChurchData;
    if (ctxData != null &&
        ctxId.isNotEmpty &&
        ChurchPanelTenant.resolve(ctxId) == churchId &&
        ctxData.isNotEmpty) {
      return _resultFromData(
        seed: seed,
        churchId: churchId,
        data: ctxData,
        readSource: 'session_context',
      );
    }

    final cached = await ChurchPanelLocalCache.readMap(
      churchId: churchId,
      module: ChurchPanelLocalCache.moduleCadastro,
    );
    if (cached != null && cached.isNotEmpty) {
      return _resultFromData(
        seed: seed,
        churchId: churchId,
        data: cached,
        readSource: 'local_cache',
      );
    }

    return null;
  }

  /// Ordem: sessão/Hive → **uma** leitura `ChurchRepository.loadByChurchId`.
  static Future<ChurchCadastroLoadResult> load({
    required String seedTenantId,
    bool forceRefresh = false,
  }) async {
    final seed = seedTenantId.trim();
    final churchId = _resolveChurchId(seed);

    if (churchId.isEmpty) {
      throw ChurchRepositoryException(
        'ID da igreja não informado.',
        seedTenantId: seed,
      );
    }

    final defaultLogoPath = ChurchStorageLayout.churchIdentityLogoPath(churchId);

    ChurchCadastroLoadResult? paintedLocal;
    if (!forceRefresh) {
      final local = await tryLocalSources(seedTenantId: seed);
      if (local != null && _isUsableProfile(local.data)) {
        if (!kIsWeb) {
          return local;
        }
        paintedLocal = local;
      }
    }

    Object? loadError;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady()
            .timeout(const Duration(seconds: 2), onTimeout: () {})
            .catchError((_) {});
      }

      final loaded = await ChurchRepository.loadByChurchId(
        churchId,
        seedTenantId: seed.isNotEmpty ? seed : churchId,
      ).timeout(_networkTimeout);

      if (loaded.data.isNotEmpty) {
        return _resultFromData(
          seed: seed,
          churchId: loaded.churchId,
          data: loaded.data,
          readSource: loaded.readSource,
        );
      }
    } on TimeoutException catch (e) {
      loadError = e;
    } on ChurchRepositoryException catch (e) {
      loadError = e;
    } catch (e) {
      loadError = e;
    }

    if (!forceRefresh) {
      if (paintedLocal != null && paintedLocal.data.isNotEmpty) {
        final errMsg = _formatSoftError(loadError);
        return _resultFromData(
          seed: seed,
          churchId: churchId,
          data: paintedLocal.data,
          readSource: paintedLocal.readSource,
          softError: errMsg ??
              'Sincronização parcial. Toque em «Atualizar» para tentar de novo.',
        );
      }
      final local = await tryLocalSources(seedTenantId: seed);
      if (local != null && local.data.isNotEmpty) {
        final errMsg = _formatSoftError(loadError);
        return _resultFromData(
          seed: seed,
          churchId: churchId,
          data: local.data,
          readSource: local.readSource,
          softError: errMsg ??
              'Sincronização parcial. Toque em «Atualizar» para tentar de novo.',
        );
      }
    }

    final errMsg = _formatSoftError(loadError);

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

  static String? _formatSoftError(Object? error) {
    if (error == null) return null;
    if (error is ChurchRepositoryException) return error.message;
    final raw = error.toString();
    if (FirestoreWebGuard.isInternalAssertionError(error)) {
      return 'Firestore instável na web. Toque em «Atualizar» em alguns segundos.';
    }
    if (raw.length > 280) return '${raw.substring(0, 277)}…';
    return raw;
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
