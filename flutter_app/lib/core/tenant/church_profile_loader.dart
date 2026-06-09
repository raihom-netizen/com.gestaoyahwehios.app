import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';
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

/// Resultado canónico de [ChurchProfileLoader.loadChurchData].
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

/// Carregamento do doc raiz `igrejas/{churchId}` — camada core.
abstract final class ChurchProfileLoader {
  ChurchProfileLoader._();

  static ChurchDataLoadResult? _lastGoodResult;

  static Future<ChurchDataLoadResult> loadByChurchId(
    String churchId, {
    String? seedTenantId,
    String? userUid,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty) {
      throw ChurchRepositoryException(
        'churchId vazio.',
        seedTenantId: seedTenantId,
        resolvedChurchId: id,
      );
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final firestorePath = 'igrejas/$id';
    ChurchModuleFirestoreAudit.logBeforeQuery(
      module: 'Cadastro Igreja',
      churchId: id,
      path: firestorePath,
    );

    final snap = await FirestoreReadResilience.getDocument(
      ChurchFirestoreAccess.churchDoc(id),
      cacheKey: 'church_direct_$id',
      maxAttempts: kIsWeb ? 4 : 3,
      attemptTimeout: kIsWeb
          ? const Duration(seconds: 18)
          : const Duration(seconds: 12),
    );

    final data = snap.exists && snap.data() != null
        ? Map<String, dynamic>.from(snap.data()!)
        : <String, dynamic>{};

    if (data.isEmpty) {
      throw ChurchRepositoryException(
        'Não foi possível carregar os dados da igreja em $firestorePath.',
        seedTenantId: seedTenantId ?? id,
        resolvedChurchId: id,
        firestorePath: firestorePath,
      );
    }

    final seed = (seedTenantId ?? id).trim();
    final result = ChurchDataLoadResult(
      seedTenantId: seed,
      churchId: id,
      firestorePath: firestorePath,
      data: data,
      fieldCount: data.length,
      loadedAt: DateTime.now(),
      readSource: snap.metadata.isFromCache ? 'cache' : 'server',
      logoStoragePath: ChurchStorageLayout.churchIdentityLogoPath(id),
      tenantMismatch: seed != id,
    );
    _lastGoodResult = result;
    ChurchOperationalPaths.rememberResolved(seed, id, userUid: userUid);
    return result;
  }

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
      ChurchOperationalPaths.invalidateResolved(seed, userUid: userUid);
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final directId = ChurchContext.resolveChurchId(seed);
    final candidates = <String>{
      if (directId.isNotEmpty) directId,
      seed,
    };

    ChurchRepositoryException? lastError;
    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      try {
        return await loadByChurchId(
          candidate,
          seedTenantId: seed,
          userUid: userUid,
        );
      } on ChurchRepositoryException catch (e) {
        lastError = e;
      }
    }

    throw lastError ??
        ChurchRepositoryException(
          'Não foi possível carregar os dados da igreja em igrejas/{churchId}.',
          seedTenantId: seed,
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
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
        final id = ChurchContext.resolveChurchId(seedTenantId);
        load = await FirestoreWebGuard.runWithWebRecovery(
          () => loadByChurchId(
            id.isNotEmpty ? id : seedTenantId.trim(),
            seedTenantId: seedTenantId,
            userUid: userUid,
          ),
          maxAttempts: 4,
        );
      } else {
        load = await loadChurchData(
          seedTenantId: seedTenantId,
          userUid: userUid,
          forceRefresh: true,
        );
      }
      resolved = load!.churchId;
    } catch (e) {
      lastError = e.toString();
      resolved = ChurchContext.resolveChurchId(seedTenantId);
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
