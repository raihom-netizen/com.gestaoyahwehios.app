import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/church_tenant_fields.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
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

/// Carga canónica do Cadastro — **uma** leitura Firestore via [ChurchRepository].
///
/// Web = Android = iOS: sessão → cache Hive → `loadByChurchId` (sem leituras triplicadas).
abstract final class ChurchCadastroLoadService {
  ChurchCadastroLoadService._();

  /// Perfil mínimo útil (nome + pelo menos endereço ou gestor).
  static const int kMinProfileScore = 5;

  static Duration get _networkTimeout => ChurchPanelReadTimeouts.churchDocCap;

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

  /// Agregados KPI/financeiro não alimentam inputs — ficam fora do estado do formulário.
  static const Set<String> _heavyRootKeys = {
    'dashboardAggregates',
    'financeAggregates',
    'membersDirectorySnapshot',
    'membersDirectory',
    'panelFeedCache',
    'lastFinanceSnapshot',
  };

  static const List<String> _identityFieldKeys = [
    'name',
    'nome',
    'NOME',
    'NOME_IGREJA',
    'cnpj',
    'CNPJ',
    'cep',
    'rua',
    'endereco',
    'gestorNome',
    'gestor_nome',
    'slug',
    'slugId',
    'telefone',
    'phone',
  ];

  /// Só campos do cadastro — evita re-render pesado com mapas agregados do doc raiz.
  static Map<String, dynamic> sliceCadastroFormFields(Map<String, dynamic> raw) {
    if (raw.isEmpty) return const {};
    final out = Map<String, dynamic>.from(raw);
    for (final k in _heavyRootKeys) {
      out.remove(k);
    }
    return out;
  }

  static bool _hasIdentityField(Map<String, dynamic> data) {
    final slice = sliceCadastroFormFields(data);
    for (final k in _identityFieldKeys) {
      final v = slice[k];
      if (v != null && v.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  static bool _hasMinimalCadastroFields(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    if (_isUsableProfile(data)) return true;
    return _hasIdentityField(data);
  }

  static Map<String, dynamic> _bestCadastroPayload({
    Map<String, dynamic>? primary,
    Map<String, dynamic>? secondary,
  }) {
    final p = sliceCadastroFormFields(primary ?? const {});
    final s = sliceCadastroFormFields(secondary ?? const {});
    if (p.isEmpty) return s;
    if (s.isEmpty) return p;
    final pScore = _profileScore(p);
    final sScore = _profileScore(s);
    if (sScore > pScore) return s;
    if (pScore > sScore) return p;
    if (_hasIdentityField(s) && !_hasIdentityField(p)) return s;
    return p;
  }

  static Future<({String docId, Map<String, dynamic> data})?> _readCadastroDocOnce(
    String churchId,
  ) async {
    final id = churchId.trim();
    if (id.isEmpty) return null;

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady()
          .timeout(const Duration(seconds: 2), onTimeout: () {})
          .catchError((_) {});
    }

    try {
      final snap = await FirestoreReadResilience.getDocument(
        ChurchFirestoreAccess.churchDoc(id),
        cacheKey: 'cadastro_form_$id',
        maxAttempts: kIsWeb ? 2 : 2,
        attemptTimeout: Duration(seconds: kIsWeb ? 8 : 6),
      ).timeout(Duration(seconds: kIsWeb ? 14 : 10));

      if (!snap.exists) return null;
      final raw = snap.data();
      if (raw == null || raw.isEmpty) return null;
      return (
        docId: snap.id,
        data: sliceCadastroFormFields(Map<String, dynamic>.from(raw)),
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
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

  static String _resolveChurchId(String seedTenantId) {
    final seed = seedTenantId.trim();
    if (seed.isNotEmpty) return ChurchRepository.churchId(seed);
    return ChurchRepository.churchId(
      ChurchContextService.currentChurchId ?? '',
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
        ChurchRepository.churchId(ctxId) == churchId &&
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
      if (local != null && _hasMinimalCadastroFields(local.data)) {
        return _resultFromData(
          seed: seed,
          churchId: churchId,
          data: sliceCadastroFormFields(local.data),
          readSource: local.readSource,
        );
      }
      if (local != null && local.data.isNotEmpty) {
        paintedLocal = local;
      }
    }

    Object? loadError;

    // Doc único — getDoc cache-first (sem snapshots); timeout curto para não travar a UI.
    Map<String, dynamic> directData = const {};
    try {
      String? directDocId;
      final direct = await _readCadastroDocOnce(churchId);
      if (direct != null && direct.data.isNotEmpty) {
        directDocId = direct.docId;
        directData = Map<String, dynamic>.from(direct.data);
      }
      if (directData.isNotEmpty && _hasMinimalCadastroFields(directData)) {
        return _resultFromData(
          seed: seed,
          churchId: directDocId ?? churchId,
          data: ChurchTenantFields.stamp(directDocId ?? churchId, directData),
          readSource: 'direct_read',
        );
      }
    } catch (e) {
      loadError = e;
    }

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
        final merged = _bestCadastroPayload(
          primary: loaded.data,
          secondary: directData,
        );
        return _resultFromData(
          seed: seed,
          churchId: loaded.churchId,
          data: ChurchTenantFields.stamp(loaded.churchId, merged),
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

    try {
      final richest =
          await TenantResolverService.richestChurchProfileForCadastro(
        churchId,
        preferServer: kIsWeb,
      );
      final best = _bestCadastroPayload(
        primary: richest,
        secondary: directData,
      );
      if (best.isNotEmpty) {
        return _resultFromData(
          seed: seed,
          churchId: churchId,
          data: ChurchTenantFields.stamp(churchId, best),
          readSource: 'richest_cluster',
        );
      }
    } catch (e) {
      loadError ??= e;
    }

    try {
      final direct = await _readCadastroDocOnce(churchId);
      if (direct != null && direct.data.isNotEmpty) {
        final best = _bestCadastroPayload(
          primary: direct.data,
          secondary: directData,
        );
        return _resultFromData(
          seed: seed,
          churchId: direct.docId,
          data: ChurchTenantFields.stamp(direct.docId, best),
          readSource: 'direct_read',
        );
      }
    } catch (e) {
      loadError ??= e;
    }

    if (!forceRefresh) {
      if (paintedLocal != null && paintedLocal.data.isNotEmpty) {
        final errMsg = _formatSoftError(loadError);
        return _resultFromData(
          seed: seed,
          churchId: churchId,
          data: sliceCadastroFormFields(paintedLocal.data),
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
          data: sliceCadastroFormFields(local.data),
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
    final slim = sliceCadastroFormFields(result.data);
    ChurchContextService.bindChurchData(
      churchId: result.churchId,
      data: slim,
    );
    await ChurchPanelLocalCache.saveMap(
      churchId: result.churchId,
      module: ChurchPanelLocalCache.moduleCadastro,
      data: slim,
    );
  }
}
