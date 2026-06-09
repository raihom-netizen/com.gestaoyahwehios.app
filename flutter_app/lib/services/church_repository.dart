import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Falha de leitura do perfil da igreja — **nunca** mascarar com `{}`.
class ChurchRepositoryException implements Exception {
  ChurchRepositoryException(
    this.message, {
    this.seedTenantId,
    this.resolvedChurchId,
    this.firestorePath,
  });

  final String message;
  final String? seedTenantId;
  final String? resolvedChurchId;
  final String? firestorePath;

  @override
  String toString() => message;
}

/// Resultado canónico de [ChurchRepository.loadChurchData].
class ChurchDataLoadResult {
  const ChurchDataLoadResult({
    required this.seedTenantId,
    required this.churchId,
    required this.firestorePath,
    required this.data,
    required this.fieldCount,
    required this.loadedAt,
    required this.readSource,
    required this.logoStoragePath,
    this.logoExistsInStorage = false,
    this.tenantMismatch = false,
  });

  final String seedTenantId;
  final String churchId;
  final String firestorePath;
  final Map<String, dynamic> data;
  final int fieldCount;
  final DateTime loadedAt;
  final String readSource;
  final String logoStoragePath;
  final bool logoExistsInStorage;
  final bool tenantMismatch;
}

class ChurchSyncDiagnosticReport {
  const ChurchSyncDiagnosticReport({
    required this.seedTenantId,
    required this.resolvedChurchId,
    required this.firestorePath,
    required this.storageBucket,
    required this.fieldCount,
    required this.lastReadAt,
    this.storageRootPath,
    this.nome,
    this.cep,
    this.rua,
    this.bairro,
    this.cidade,
    this.instagram,
    this.facebook,
    this.whatsapp,
    this.logoStoragePath,
    this.logoExists,
    this.tenantMismatch = false,
    this.storageAligned = true,
    this.firestoreActive,
    this.storageActive,
    this.lastError,
    this.lastUploadAt,
    this.lastUploadPath,
    this.lastDownloadAt,
    this.lastDownloadPath,
    this.lastMediaErrorAt,
  });

  final String seedTenantId;
  final String resolvedChurchId;
  final String firestorePath;
  final String storageBucket;
  final int fieldCount;
  final DateTime? lastReadAt;
  final String? storageRootPath;
  final String? nome;
  final String? cep;
  final String? rua;
  final String? bairro;
  final String? cidade;
  final String? instagram;
  final String? facebook;
  final String? whatsapp;
  final String? logoStoragePath;
  final bool? logoExists;
  final bool tenantMismatch;
  final bool storageAligned;
  final bool? firestoreActive;
  final bool? storageActive;
  final String? lastError;
  final DateTime? lastUploadAt;
  final String? lastUploadPath;
  final DateTime? lastDownloadAt;
  final String? lastDownloadPath;
  final DateTime? lastMediaErrorAt;
}

/// **Único** ponto de leitura do doc `igrejas/{churchId}` — Web, Android e iOS.
abstract final class ChurchRepository {
  ChurchRepository._();

  static ChurchDataLoadResult? _lastGoodResult;
  static String? _lastMismatchKey;

  static ChurchDataLoadResult? peekLastResult() => _lastGoodResult;

  /// RAM — só devolve se o perfil tiver campos reais (nunca `{}` vazio).
  static ChurchDataLoadResult? peekCached({
    required String seedTenantId,
    String? userUid,
  }) {
    final peek = TenantResolverService.peekRegistrationContext(
      seedTenantId,
      userUid: userUid,
    );
    if (peek == null || peek.profile.isEmpty) return _lastGoodResult;
    if (TenantResolverService.churchProfileRichnessScore(peek.profile) < 4) {
      return _lastGoodResult;
    }
    final churchId = peek.operationalId.trim();
    return ChurchDataLoadResult(
      seedTenantId: seedTenantId.trim(),
      churchId: churchId,
      firestorePath: 'igrejas/$churchId',
      data: Map<String, dynamic>.from(peek.profile),
      fieldCount: peek.profile.length,
      loadedAt: DateTime.now(),
      readSource: 'ram_cache',
      logoStoragePath: ChurchStorageLayout.churchIdentityLogoPath(churchId),
      tenantMismatch: seedTenantId.trim() != churchId &&
          TenantResolverService.kBpcLegacyTenantIds
              .contains(seedTenantId.trim()),
    );
  }

  /// Carrega `igrejas/{churchId}` após resolver tenant operacional.
  ///
  /// [directDocOnly]: quando `true`, lê **somente** o doc canónico — sem cluster
  /// «richest» (evita dados cruzados e loading infinito no Cadastro).
  static Future<ChurchDataLoadResult> loadChurchData({
    required String seedTenantId,
    String? userUid,
    bool forceRefresh = false,
    bool directDocOnly = false,
  }) async {
    const totalTimeout = Duration(seconds: 15);

    return loadChurchDataInner(
      seedTenantId: seedTenantId,
      userUid: userUid,
      forceRefresh: forceRefresh,
      directDocOnly: directDocOnly,
    ).timeout(
      totalTimeout,
      onTimeout: () {
        throw ChurchRepositoryException(
          'Tempo esgotado (${totalTimeout.inSeconds}s) ao carregar igrejas/{churchId}.',
          seedTenantId: seedTenantId.trim(),
        );
      },
    );
  }

  static Future<ChurchDataLoadResult> loadChurchDataInner({
    required String seedTenantId,
    String? userUid,
    bool forceRefresh = false,
    bool directDocOnly = false,
  }) async {
    final seed = seedTenantId.trim();
    if (seed.isEmpty) {
      throw ChurchRepositoryException(
        'Igreja não identificada.',
        seedTenantId: seed,
      );
    }

    if (forceRefresh) {
      TenantResolverService.invalidateRegistrationContextCache(
        seedId: seed,
        userUid: userUid,
      );
      ChurchOperationalPaths.invalidateResolved(seed, userUid: userUid);
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final churchId = await TenantResolverService.operationalChurchId(
      seed: seed,
      userUid: userUid,
      forceRefresh: forceRefresh,
    );
    final resolved = churchId.trim();
    if (resolved.isEmpty) {
      throw ChurchRepositoryException(
        'Não foi possível resolver o tenant operacional da igreja.',
        seedTenantId: seed,
      );
    }

    final firestorePath = 'igrejas/$resolved';
    debugPrint('WEB CHURCH ID:');
    debugPrint(resolved);
    debugPrint('WEB DOC PATH:');
    debugPrint(firestorePath);

    final tenantMismatch = seed != resolved;
    if (tenantMismatch) {
      await _logTenantMismatch(seed: seed, resolved: resolved);
    }

    ChurchOperationalPaths.rememberResolved(seed, resolved, userUid: userUid);

    Map<String, dynamic> data = await TenantResolverService
        .loadIgrejaCadastroDocDirect(resolved, preferServer: false);
    var readSource = 'serverAndCache';

    // Operacional: só igrejas/{churchId} — sem merge de cluster/irmãos.

    if (data.isEmpty) {
      try {
        final snap = await FirestoreReadResilience.getDocument(
          ChurchOperationalPaths.churchDoc(resolved),
          cacheKey: 'church_repo_$resolved',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: kIsWeb
              ? const Duration(seconds: 18)
              : const Duration(seconds: 12),
        );
        if (snap.exists && snap.data() != null) {
          data = Map<String, dynamic>.from(snap.data()!);
          readSource = snap.metadata.isFromCache ? 'cache_fallback' : 'server';
        }
      } catch (_) {}
    }

    if (data.isEmpty) {
      throw ChurchRepositoryException(
        'Não foi possível carregar os dados da igreja em $firestorePath. '
        'Verifique a conexão e tente novamente.',
        seedTenantId: seed,
        resolvedChurchId: resolved,
        firestorePath: firestorePath,
      );
    }

    final logoPath = ChurchStorageLayout.churchIdentityLogoPath(resolved);
    // Verificação de logo no Storage é feita pelo ChurchBrandService (não bloqueia cadastro).
    const logoExists = false;

    final result = ChurchDataLoadResult(
      seedTenantId: seed,
      churchId: resolved,
      firestorePath: firestorePath,
      data: data,
      fieldCount: data.length,
      loadedAt: DateTime.now(),
      readSource: readSource,
      logoStoragePath: logoPath,
      logoExistsInStorage: logoExists,
      tenantMismatch: tenantMismatch,
    );

    _lastGoodResult = result;
    await _logEmptyWebProfileIfNeeded(
      seed: seed,
      resolved: resolved,
      data: data,
    );
    TenantResolverService.invalidateRegistrationContextCache(
      seedId: seed,
      userUid: userUid,
    );
    return result;
  }

  static Future<void> _logEmptyWebProfileIfNeeded({
    required String seed,
    required String resolved,
    required Map<String, dynamic> data,
  }) async {
    if (!kIsWeb) return;
    final score = TenantResolverService.churchProfileRichnessScore(data);
    final keyFields = <String>[
      (data['cep'] ?? '').toString(),
      (data['rua'] ?? data['address'] ?? '').toString(),
      (data['instagramUrl'] ?? data['instagram'] ?? '').toString(),
      (data['whatsappChatUrl'] ?? data['whatsapp'] ?? '').toString(),
      (data['telefone'] ?? data['phone'] ?? '').toString(),
    ];
    final emptyKeys = keyFields.where((v) => v.trim().isEmpty).length;
    if (score >= 6 && emptyKeys < 3) return;
    debugPrint(
      'WEB_FIRESTORE_MISMATCH empty_profile seed=$seed resolved=$resolved '
      'score=$score emptyKeys=$emptyKeys',
    );
    await SystemLogService.record(
      module: 'church_sync',
      message: 'WEB_FIRESTORE_MISMATCH',
      tenantId: seed,
      canonicalId: resolved,
      severity: 'warn',
      extra: {
        'reason': 'empty_profile_on_web',
        'seedTenantId': seed,
        'resolvedChurchId': resolved,
        'richnessScore': score,
        'emptyKeyFields': emptyKeys,
        'fieldCount': data.length,
      },
    );
  }

  static Future<void> _logTenantMismatch({
    required String seed,
    required String resolved,
  }) async {
    final key = '$seed->$resolved';
    if (_lastMismatchKey == key) return;
    _lastMismatchKey = key;
    debugPrint('WEB_FIRESTORE_MISMATCH seed=$seed resolved=$resolved');
    await SystemLogService.record(
      module: 'church_sync',
      message: 'WEB_FIRESTORE_MISMATCH',
      tenantId: seed,
      canonicalId: resolved,
      severity: 'warn',
      extra: {
        'seedTenantId': seed,
        'resolvedChurchId': resolved,
        'platform': kIsWeb ? 'web' : 'mobile',
      },
    );
  }

  /// Regista `WEB_FIRESTORE_MISMATCH` quando a Web carrega perfil sem campos-chave.
  static Future<void> reportClientEmptyProfile(
    ChurchSyncDiagnosticReport report,
  ) async {
    if (!kIsWeb) return;
    final fields = <String?>[
      report.cep,
      report.rua,
      report.instagram,
      report.whatsapp,
      report.nome,
    ];
    final empty = fields.where((v) => (v ?? '').trim().isEmpty).length;
    if (empty < 3) return;
    await _logTenantMismatch(
      seed: report.seedTenantId,
      resolved: report.resolvedChurchId,
    );
    await SystemLogService.record(
      module: 'church_sync',
      message: 'WEB_FIRESTORE_MISMATCH',
      tenantId: report.seedTenantId,
      canonicalId: report.resolvedChurchId,
      severity: 'warn',
      extra: {
        'reason': 'test_page_empty_fields',
        'emptyFields': empty,
        'fieldCount': report.fieldCount,
        'firestorePath': report.firestorePath,
      },
    );
  }

  static Future<ChurchSyncDiagnosticReport> runDiagnostic({
    required String seedTenantId,
    String? userUid,
  }) async {
    String resolved = seedTenantId.trim();
    String? lastError;
    ChurchDataLoadResult? load;

    try {
      load = await loadChurchData(
        seedTenantId: seedTenantId,
        userUid: userUid,
        forceRefresh: true,
      );
      resolved = load.churchId;
    } catch (e) {
      lastError = e.toString();
      try {
        resolved = await TenantResolverService.resolveOperationalChurchDocId(
          seedTenantId,
          userUid: userUid,
        );
      } catch (e2) {
        lastError = e2.toString();
      }
    }

    final data = load?.data ?? const <String, dynamic>{};
    return ChurchSyncDiagnosticReport(
      seedTenantId: seedTenantId.trim(),
      resolvedChurchId: resolved,
      firestorePath: 'igrejas/$resolved',
      storageRootPath: ChurchStorageLayout.churchRoot(resolved),
      storageBucket: firebaseDefaultStorage.bucket,
      fieldCount: data.length,
      lastReadAt: load?.loadedAt,
      nome: (data['nome'] ?? data['name'] ?? '').toString(),
      cep: (data['cep'] ?? '').toString(),
      rua: (data['rua'] ?? data['address'] ?? '').toString(),
      bairro: (data['bairro'] ?? '').toString(),
      cidade: (data['cidade'] ?? data['localidade'] ?? '').toString(),
      instagram: (data['instagramUrl'] ?? data['instagram'] ?? '').toString(),
      facebook: (data['facebookUrl'] ?? data['facebook'] ?? '').toString(),
      whatsapp: (data['whatsappChatUrl'] ?? data['whatsapp'] ?? '').toString(),
      logoStoragePath: load?.logoStoragePath ??
          ChurchStorageLayout.churchIdentityLogoPath(resolved),
      logoExists: load?.logoExistsInStorage,
      tenantMismatch: load?.tenantMismatch ?? (seedTenantId.trim() != resolved),
      lastError: lastError,
    );
  }
}
