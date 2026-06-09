import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
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

  // ─── API única painel — Android / iOS / Web (só igrejas/{churchId}) ───────

  /// ID canónico da sessão — **sem** tenant/alias resolver.
  static String churchId([String? shellHint]) =>
      ChurchContextService.panelChurchId(shellHint);

  static Duration get panelQueryTimeout =>
      kIsWeb ? const Duration(seconds: 10) : const Duration(seconds: 22);

  static String firestorePath([String? shellHint]) {
    final id = churchId(shellHint);
    return id.isEmpty ? '' : 'igrejas/$id';
  }

  /// Doc raiz `igrejas/{churchId}`.
  static DocumentReference<Map<String, dynamic>> churchDoc([String? shellHint]) {
    final id = churchId(shellHint);
    return firebaseDefaultFirestore.collection('igrejas').doc(id);
  }

  /// Subcoleção `igrejas/{churchId}/{name}`.
  static CollectionReference<Map<String, dynamic>> collection(
    String subcollection, {
    String? churchIdHint,
  }) =>
      churchDoc(churchIdHint).collection(subcollection.trim());

  static Future<QuerySnapshot<Map<String, dynamic>>> _querySubcollection({
    required String module,
    required String subcollection,
    String? churchIdHint,
    int limit = 120,
    String? cacheKeySuffix,
  }) async {
    final id = churchId(churchIdHint);
    if (id.isEmpty) return const MergedFirestoreQuerySnapshot([]);
    final path = 'igrejas/$id/$subcollection';
    Future<QuerySnapshot<Map<String, dynamic>>> run() =>
        ChurchModuleFirestoreAudit.traceQuery(
          module: module,
          churchId: id,
          path: path,
          run: () => FirestoreWebGuard.runWithWebRecovery(
            () => FirestoreReadResilience.getQuery(
              collection(subcollection, churchIdHint: id).limit(limit),
              cacheKey: 'repo_${id}_${cacheKeySuffix ?? subcollection}_$limit',
            ),
          ),
        );
    if (kIsWeb) {
      return run().timeout(
        panelQueryTimeout,
        onTimeout: () => const MergedFirestoreQuerySnapshot([]),
      );
    }
    return run();
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> departamentos({
    String? churchIdHint,
    int limit = 120,
  }) =>
      _querySubcollection(
        module: 'Departamentos',
        subcollection: 'departamentos',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> cargos({
    String? churchIdHint,
    int limit = 120,
  }) =>
      _querySubcollection(
        module: 'Cargos',
        subcollection: 'cargos',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> membros({
    String? churchIdHint,
    int limit = 250,
  }) =>
      _querySubcollection(
        module: 'Membros',
        subcollection: 'membros',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> financeiro({
    String? churchIdHint,
    int limit = 250,
  }) =>
      _querySubcollection(
        module: 'Financeiro',
        subcollection: 'finance',
        churchIdHint: churchIdHint,
        limit: limit,
        cacheKeySuffix: 'finance',
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> fornecedores({
    String? churchIdHint,
    int limit = 80,
  }) =>
      _querySubcollection(
        module: 'Fornecedores',
        subcollection: 'fornecedores',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> patrimonio({
    String? churchIdHint,
    int limit = 120,
  }) =>
      _querySubcollection(
        module: 'Patrimônio',
        subcollection: 'patrimonio',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> avisos({
    String? churchIdHint,
    int limit = 80,
  }) =>
      _querySubcollection(
        module: 'Avisos',
        subcollection: 'avisos',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> eventos({
    String? churchIdHint,
    int limit = 80,
  }) =>
      _querySubcollection(
        module: 'Eventos',
        subcollection: 'noticias',
        churchIdHint: churchIdHint,
        limit: limit,
        cacheKeySuffix: 'eventos_noticias',
      );

  static CollectionReference<Map<String, dynamic>> chats({
    String? churchIdHint,
  }) =>
      collection('chats', churchIdHint: churchIdHint);

  static CollectionReference<Map<String, dynamic>> certificadosCol({
    String? churchIdHint,
  }) =>
      collection('certificados_emitidos', churchIdHint: churchIdHint);

  static Future<QuerySnapshot<Map<String, dynamic>>> certificadosEmitidos({
    String? churchIdHint,
    int limit = 80,
  }) =>
      _querySubcollection(
        module: 'Certificados',
        subcollection: 'certificados_emitidos',
        churchIdHint: churchIdHint,
        limit: limit,
        cacheKeySuffix: 'certificados',
      );

  /// Alias público — certificados emitidos (`certificados_emitidos`).
  static Future<QuerySnapshot<Map<String, dynamic>>> certificados({
    String? churchIdHint,
    int limit = 80,
  }) =>
      certificadosEmitidos(churchIdHint: churchIdHint, limit: limit);

  static Future<QuerySnapshot<Map<String, dynamic>>> visitantes({
    String? churchIdHint,
    int limit = 200,
  }) =>
      _querySubcollection(
        module: 'Visitantes',
        subcollection: 'visitantes',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> escalas({
    String? churchIdHint,
    int limit = 120,
  }) =>
      _querySubcollection(
        module: 'Escalas',
        subcollection: 'escalas',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  static Future<QuerySnapshot<Map<String, dynamic>>> notificacoes({
    String? churchIdHint,
    int limit = 80,
  }) =>
      _querySubcollection(
        module: 'Notificações',
        subcollection: 'notificacoes',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  /// Configurações — subcoleção real `config` (não renomear no Firestore).
  static CollectionReference<Map<String, dynamic>> configuracoes({
    String? churchIdHint,
  }) =>
      collection('config', churchIdHint: churchIdHint);

  static DocumentReference<Map<String, dynamic>> configuracoesDoc(
    String docId, {
    String? churchIdHint,
  }) =>
      configuracoes(churchIdHint: churchIdHint).doc(docId.trim());

  /// Carteirinhas — dados em `membros` + mídia em Storage `cartao_membro/`.
  static CollectionReference<Map<String, dynamic>> carteirinhas({
    String? churchIdHint,
  }) =>
      collection('membros', churchIdHint: churchIdHint);

  /// Alias — coleção `chats`.
  static Future<QuerySnapshot<Map<String, dynamic>>> chat({
    String? churchIdHint,
    int limit = 40,
  }) =>
      _querySubcollection(
        module: 'Chat',
        subcollection: 'chats',
        churchIdHint: churchIdHint,
        limit: limit,
      );

  /// Cache instantâneo — `igrejas/{churchId}/_dashboard_cache/main`.
  static DocumentReference<Map<String, dynamic>> dashboardCacheMain({
    String? churchIdHint,
  }) =>
      churchDoc(churchIdHint).collection('_dashboard_cache').doc('main');

  /// Doc raiz `igrejas/{churchId}` com timeout Web.
  static Future<DocumentSnapshot<Map<String, dynamic>>> church({
    String? churchIdHint,
  }) async {
    final id = churchId(churchIdHint);
    if (id.isEmpty) {
      throw ChurchRepositoryException('churchId vazio.');
    }
    final path = 'igrejas/$id';
    ChurchModuleFirestoreAudit.logBeforeQuery(
      module: 'Igreja',
      churchId: id,
      path: path,
    );
    Future<DocumentSnapshot<Map<String, dynamic>>> run() =>
        FirestoreReadResilience.getDocument(
          churchDoc(id),
          cacheKey: 'church_snap_$id',
          maxAttempts: kIsWeb ? 4 : 3,
          attemptTimeout: panelQueryTimeout,
        );
    if (kIsWeb) {
      return run().timeout(
        panelQueryTimeout,
        onTimeout: () => throw ChurchRepositoryException(
          'Tempo esgotado ao carregar $path.',
          resolvedChurchId: id,
          firestorePath: path,
        ),
      );
    }
    return run();
  }

  static ChurchDataLoadResult? peekLastResult() => _lastGoodResult;

  /// RAM — só devolve se o perfil tiver campos reais (nunca `{}` vazio).
  static ChurchDataLoadResult? peekCached({
    required String seedTenantId,
    String? userUid,
  }) {
    final ctx = ChurchContextService.currentChurchData;
    final id = ChurchContextService.panelChurchId(seedTenantId);
    if (ctx != null && ctx.isNotEmpty && id.isNotEmpty) {
      return ChurchDataLoadResult(
        seedTenantId: seedTenantId.trim(),
        churchId: id,
        firestorePath: 'igrejas/$id',
        data: Map<String, dynamic>.from(ctx),
        fieldCount: ctx.length,
        loadedAt: DateTime.now(),
        readSource: 'context_cache',
        logoStoragePath: ChurchStorageLayout.churchIdentityLogoPath(id),
      );
    }
    return _lastGoodResult;
  }

  /// Leitura directa `igrejas/{churchId}` — **mesmo fluxo que Membros no Android**.
  /// Sem tenant resolver, alias ou slug lookup.
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
      churchDoc(id),
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
      ChurchOperationalPaths.invalidateResolved(seed, userUid: userUid);
    }

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }

    final directId = ChurchContextService.panelChurchId(seed);
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
      resolved = churchId(seedTenantId);
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
