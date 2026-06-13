import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Falha de alinhamento Firestore ↔ Storage — operação deve ser abortada.
class ChurchTenantMediaException implements Exception {
  ChurchTenantMediaException(
    this.message, {
    this.seedTenantId,
    this.churchId,
    this.storagePath,
    this.firestorePath,
  });

  final String message;
  final String? seedTenantId;
  final String? churchId;
  final String? storagePath;
  final String? firestorePath;

  @override
  String toString() => message;
}

/// Contexto canónico — `churchId` resolvido uma vez para Firestore **e** Storage.
class ChurchTenantContext {
  const ChurchTenantContext({
    required this.seedTenantId,
    required this.churchId,
    required this.firestorePath,
    required this.storageRoot,
    required this.storageBucket,
    this.tenantMismatch = false,
    this.firestoreActive = false,
    this.storageActive = false,
  });

  final String seedTenantId;
  final String churchId;
  final String firestorePath;
  final String storageRoot;
  final String storageBucket;
  final bool tenantMismatch;
  final bool firestoreActive;
  final bool storageActive;
}

/// Atividade recente de mídia — exibida no diagnóstico (Configurações).
class ChurchTenantMediaActivity {
  ChurchTenantMediaActivity._();

  static DateTime? lastUploadAt;
  static String? lastUploadPath;
  static DateTime? lastDownloadAt;
  static String? lastDownloadPath;
  static String? lastError;
  static DateTime? lastErrorAt;

  static void recordUpload(String storagePath) {
    lastUploadAt = DateTime.now();
    lastUploadPath = storagePath.trim();
  }

  static void recordDownload(String storagePath) {
    lastDownloadAt = DateTime.now();
    lastDownloadPath = storagePath.trim();
  }

  static void recordError(String message) {
    lastErrorAt = DateTime.now();
    lastError = message.trim();
  }
}

/// **Único gate** Firestore + Storage — Web, Android e iOS.
abstract final class ChurchTenantMediaService {
  ChurchTenantMediaService._();

  static final Set<String> _loggedMismatchKeys = {};

  /// Resolve `churchId` operacional (mesmo em todas as plataformas).
  static Future<ChurchTenantContext> resolveContext({
    required String seedTenantId,
    String? userUid,
    bool forceRefresh = false,
    bool probeServices = false,
  }) async {
    final seed = seedTenantId.trim();
    if (seed.isEmpty) {
      throw ChurchTenantMediaException('Igreja não identificada.');
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final resolved = ChurchRepository.churchId(seed).trim();
    if (resolved.isEmpty) {
      throw ChurchTenantMediaException(
        'Não foi possível resolver o tenant operacional.',
        seedTenantId: seed,
      );
    }

    final firestorePath = 'igrejas/$resolved';
    final storageRoot = ChurchStorageLayout.churchRoot(resolved);
    final bucket = firebaseDefaultStorage.bucket;
    final mismatch = seed != resolved;

    var firestoreActive = false;
    var storageActive = false;

    if (probeServices) {
      firestoreActive = await _probeFirestore(resolved);
      storageActive = await _probeStorage(resolved);
    }

    return ChurchTenantContext(
      seedTenantId: seed,
      churchId: resolved,
      firestorePath: firestorePath,
      storageRoot: storageRoot,
      storageBucket: bucket,
      tenantMismatch: mismatch,
      firestoreActive: firestoreActive,
      storageActive: storageActive,
    );
  }

  static Future<bool> _probeFirestore(String churchId) async {
    try {
      final snap = await FirestoreReadResilience.getDocument(
        ChurchOperationalPaths.churchDoc(churchId),
        cacheKey: 'church_media_probe_$churchId',
        maxAttempts: kIsWeb ? 3 : 2,
        attemptTimeout: const Duration(seconds: 12),
      );
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _probeStorage(String churchId) async {
    try {
      final probe = '${ChurchStorageLayout.churchRoot(churchId)}/configuracoes/.probe';
      await firebaseDefaultStorage.ref(probe).getMetadata().timeout(
            const Duration(seconds: 8),
          );
      return true;
    } catch (e) {
      if (_isNotFound(e)) {
        try {
          await ChurchStorageMetadataVerify.assertExists(
            ChurchStorageLayout.churchIdentityLogoPath(churchId),
            timeout: const Duration(seconds: 8),
          );
          return true;
        } catch (_) {}
      }
      return firebaseDefaultStorage.bucket.trim().isNotEmpty;
    }
  }

  static bool _isNotFound(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('object-not-found') || s.contains('404');
  }

  /// Extrai o segmento `igrejas/{id}` de um path Storage.
  static String? churchIdFromStoragePath(String storagePath) {
    final norm = _normalizePath(storagePath);
    final m = RegExp(r'^igrejas/([^/]+)').firstMatch(norm);
    return m?.group(1)?.trim();
  }

  static String _normalizePath(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '').trim();

  /// Garante que [storagePath] pertence ao tenant [operationalChurchId].
  /// Aborta paths soltos na raiz (`chat_media/`, `eventos/`, etc.).
  static void assertStoragePathAligned({
    required String storagePath,
    required String operationalChurchId,
  }) {
    final norm = _normalizePath(storagePath);
    if (norm.isEmpty) {
      throw ChurchTenantMediaException('storagePath vazio.');
    }

    final churchId = operationalChurchId.trim();
    if (churchId.isEmpty) {
      throw ChurchTenantMediaException('churchId operacional vazio.');
    }

    const forbiddenRoots = <String>[
      'chat_media/',
      'eventos/',
      'avisos/',
      'membros/',
      'patrimonio/',
      'certificados/',
      'configuracoes/',
    ];
    for (final root in forbiddenRoots) {
      if (norm.startsWith(root)) {
        throw ChurchTenantMediaException(
          'STORAGE_FORA_DO_TENANT: "$norm" — use igrejas/{churchId}/$root',
          churchId: churchId,
          storagePath: norm,
        );
      }
    }

    final expectedPrefix = 'igrejas/$churchId/';
    final expectedRoot = 'igrejas/$churchId';
    if (norm == expectedRoot || norm.startsWith(expectedPrefix)) return;

    final pathChurchId = churchIdFromStoragePath(norm);
    if (pathChurchId == null || pathChurchId.isEmpty) {
      throw ChurchTenantMediaException(
        'STORAGE_FORA_DO_TENANT: "$norm" não está sob igrejas/{churchId}/',
        churchId: churchId,
        storagePath: norm,
      );
    }

    final canonicalFromPath =
        TenantResolverService.syncStorageTenantId(pathChurchId);
    if (canonicalFromPath != churchId && pathChurchId != churchId) {
      throw ChurchTenantMediaException(
        'STORAGE_TENANT_MISMATCH: path usa "$pathChurchId", '
        'esperado "$churchId" (Firestore).',
        churchId: churchId,
        storagePath: norm,
        firestorePath: 'igrejas/$churchId',
      );
    }
  }

  /// Gate completo antes de upload — resolve tenant, valida path e serviços.
  static Future<ChurchTenantContext> prepareUploadGate({
    required String seedTenantId,
    required String storagePath,
    String? userUid,
  }) async {
    final ctx = await resolveContext(
      seedTenantId: seedTenantId,
      userUid: userUid,
      probeServices: true,
    );

    assertStoragePathAligned(
      storagePath: storagePath,
      operationalChurchId: ctx.churchId,
    );

    if (!ctx.firestoreActive) {
      throw ChurchTenantMediaException(
        'Firestore inativo ou doc ${ctx.firestorePath} inacessível.',
        seedTenantId: ctx.seedTenantId,
        churchId: ctx.churchId,
        storagePath: storagePath,
        firestorePath: ctx.firestorePath,
      );
    }

    await ensureFirebaseReadyForMediaUpload();

    if (ctx.tenantMismatch) {
      await _logMismatchOnce(
        seed: ctx.seedTenantId,
        resolved: ctx.churchId,
        storagePath: storagePath,
        reason: 'upload_gate',
      );
    }

    return ctx;
  }

  /// Gate quando só o path Storage é conhecido (uploads internos).
  static Future<void> assertUploadPathFromResolvedTenant({
    required String storagePath,
    String? seedTenantId,
    String? userUid,
  }) async {
    final norm = _normalizePath(storagePath);
    final pathChurchId = churchIdFromStoragePath(norm);
    if (pathChurchId == null || pathChurchId.isEmpty) {
      throw ChurchTenantMediaException(
        'STORAGE_FORA_DO_TENANT: "$norm"',
        storagePath: norm,
      );
    }

    final seed = (seedTenantId ?? pathChurchId).trim();
    final ctx = await resolveContext(seedTenantId: seed, userUid: userUid);
    assertStoragePathAligned(
      storagePath: storagePath,
      operationalChurchId: ctx.churchId,
    );
  }

  /// [Reference] após validação de tenant.
  static Reference ref(String storagePath) {
    final norm = _normalizePath(storagePath);
    return firebaseDefaultStorage.ref(norm);
  }

  static Future<Reference> refForUpload({
    required String seedTenantId,
    required String storagePath,
    String? userUid,
  }) async {
    await prepareUploadGate(
      seedTenantId: seedTenantId,
      storagePath: storagePath,
      userUid: userUid,
    );
    return ref(storagePath);
  }

  static Future<void> _logMismatchOnce({
    required String seed,
    required String resolved,
    required String storagePath,
    required String reason,
  }) async {
    final key = '$seed->$resolved::$storagePath::$reason';
    if (_loggedMismatchKeys.contains(key)) return;
    _loggedMismatchKeys.add(key);
    debugPrint(
      'STORAGE_TENANT_MISMATCH seed=$seed resolved=$resolved path=$storagePath',
    );
    await SystemLogService.record(
      module: 'church_sync',
      message: 'STORAGE_TENANT_MISMATCH',
      tenantId: seed,
      canonicalId: resolved,
      severity: 'warn',
      extra: {
        'reason': reason,
        'storagePath': storagePath,
        'firestorePath': 'igrejas/$resolved',
        'platform': kIsWeb ? 'web' : 'mobile',
      },
    );
  }

  /// Diagnóstico unificado Firestore + Storage.
  static Future<ChurchSyncDiagnosticReport> runFullDiagnostic({
    required String seedTenantId,
    String? userUid,
  }) async {
    final firestoreReport = await ChurchRepository.runDiagnostic(
      seedTenantId: seedTenantId,
      userUid: userUid,
    );

    ChurchTenantContext? ctx;
    try {
      if (kIsWeb) {
        final resolved = firestoreReport.resolvedChurchId.trim();
        ctx = ChurchTenantContext(
          seedTenantId: firestoreReport.seedTenantId,
          churchId: resolved,
          firestorePath: firestoreReport.firestorePath,
          storageRoot: ChurchStorageLayout.churchRoot(resolved),
          storageBucket: firebaseDefaultStorage.bucket,
          tenantMismatch: firestoreReport.tenantMismatch,
          firestoreActive: firestoreReport.lastError == null &&
              firestoreReport.fieldCount > 0,
          storageActive: await _probeStorage(resolved),
        );
      } else {
        ctx = await resolveContext(
          seedTenantId: seedTenantId,
          userUid: userUid,
          forceRefresh: true,
          probeServices: true,
        );
      }
    } catch (e) {
      ChurchTenantMediaActivity.recordError(e.toString());
    }

    final storageRoot = ctx?.storageRoot ??
        ChurchStorageLayout.churchRoot(firestoreReport.resolvedChurchId);
    final aligned = ctx != null &&
        firestoreReport.resolvedChurchId == ctx.churchId;

    return ChurchSyncDiagnosticReport(
      seedTenantId: firestoreReport.seedTenantId,
      resolvedChurchId: firestoreReport.resolvedChurchId,
      firestorePath: firestoreReport.firestorePath,
      storageRootPath: storageRoot,
      storageBucket: firestoreReport.storageBucket,
      fieldCount: firestoreReport.fieldCount,
      lastReadAt: firestoreReport.lastReadAt,
      nome: firestoreReport.nome,
      cep: firestoreReport.cep,
      rua: firestoreReport.rua,
      bairro: firestoreReport.bairro,
      cidade: firestoreReport.cidade,
      instagram: firestoreReport.instagram,
      facebook: firestoreReport.facebook,
      whatsapp: firestoreReport.whatsapp,
      logoStoragePath: firestoreReport.logoStoragePath,
      logoExists: firestoreReport.logoExists,
      tenantMismatch: firestoreReport.tenantMismatch || !aligned,
      lastError: firestoreReport.lastError ?? ChurchTenantMediaActivity.lastError,
      firestoreActive: ctx?.firestoreActive,
      storageActive: ctx?.storageActive,
      storageAligned: aligned,
      lastUploadAt: ChurchTenantMediaActivity.lastUploadAt,
      lastUploadPath: ChurchTenantMediaActivity.lastUploadPath,
      lastDownloadAt: ChurchTenantMediaActivity.lastDownloadAt,
      lastDownloadPath: ChurchTenantMediaActivity.lastDownloadPath,
      lastMediaErrorAt: ChurchTenantMediaActivity.lastErrorAt,
    );
  }
}
