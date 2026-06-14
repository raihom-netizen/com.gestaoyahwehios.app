/// **ÚNICA porta de entrada** de dados do Gestão YAHWEH.
///
/// ```dart
/// import 'package:gestao_yahweh/core/repositories/church_repository.dart';
///
/// final churchId = ChurchContext.currentChurchId;
/// final deps = await ChurchRepository.departamentos.list();
/// ```
library;

export 'package:gestao_yahweh/core/church_panel_paths.dart';
export 'package:gestao_yahweh/core/yahweh_unified_image_pipeline.dart';
export 'package:gestao_yahweh/core/gestao_yahweh_write_first_publish_service.dart';
export 'package:gestao_yahweh/core/yahweh_data_engine_fetcher.dart';
export 'package:gestao_yahweh/core/data/church_data_paths.dart';
export 'package:gestao_yahweh/core/data/church_ui_collections.dart';
export 'package:gestao_yahweh/core/data/church_data_result.dart';
export 'package:gestao_yahweh/core/data/church_data_audit.dart';
export 'package:gestao_yahweh/core/tenant/church_context.dart';
export 'package:gestao_yahweh/core/tenant/diagnostic_access_policy.dart';
export 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
export 'package:gestao_yahweh/core/tenant/church_profile_loader.dart';
export 'package:gestao_yahweh/core/tenant/tenant_migration_service.dart';
export 'package:gestao_yahweh/core/chat_engine/chat_hub_operations.dart';
export 'package:gestao_yahweh/core/chat_engine/chat_hub_threads.dart';
export 'package:gestao_yahweh/core/chat_engine/chat_messaging_engine.dart';
export 'package:gestao_yahweh/core/chat_engine/chat_presence_engine.dart';
export 'package:gestao_yahweh/core/chat_engine/chat_thread_operations.dart';
export 'package:gestao_yahweh/core/chat_engine/chat_models.dart';
export 'package:gestao_yahweh/core/chat_engine/chat_engine_paths.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_panel_read_timeouts.dart';
import 'package:gestao_yahweh/core/data/church_data_audit.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_data_result.dart';
import 'package:gestao_yahweh/core/data/church_repository.dart' as data;
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/core/tenant/church_profile_loader.dart';
import 'package:gestao_yahweh/core/tenant/tenant_migration_service.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';

/// Repositório central — Web = Android = iOS.
///
/// Proibido nas telas: `FirebaseFirestore.instance`, `.collection()`, paths manuais.
abstract final class ChurchRepository {
  ChurchRepository._();

  /// Timeout padrão de leituras do painel (Firestore) — 90s web / 28s mobile.
  static Duration get panelQueryTimeout => ChurchPanelReadTimeouts.queryCap;

  // ─── Contexto ───────────────────────────────────────────────────────────────
  static String? get currentChurchId => ChurchContext.currentChurchId;

  static String churchId([String? hint]) => resolveChurchId(hint);

  static String resolveChurchId([String? hint]) =>
      ChurchContext.resolveChurchId(hint);

  static String requireChurchId([String? hint]) =>
      ChurchContext.requireChurchId(hint);

  static String firestorePath([String? hint]) {
    final id = resolveChurchId(hint);
    return id.isEmpty ? '' : ChurchDataPaths.churchRoot(id);
  }

  static String storagePath([String? hint]) =>
      ChurchContext.churchStorageRoot(hint);

  /// Doc raiz `igrejas/{churchId}`.
  static DocumentReference<Map<String, dynamic>> churchDoc([String? hint]) =>
      ChurchFirestoreAccess.churchDoc(resolveChurchId(hint));

  /// Subcoleção canónica em `igrejas/{churchId}/{sub}`.
  static CollectionReference<Map<String, dynamic>> collection(
    String subcollection, {
    String? churchIdHint,
  }) =>
      ChurchFirestoreAccess.collectionRef(
        resolveChurchId(churchIdHint),
        subcollection.trim(),
      );

  static Future<TenantMigrationReport> runTenantMigration({
    String? churchIdHint,
    String? seedHint,
  }) =>
      TenantMigrationService.runAfterBind(
        churchIdHint: churchIdHint,
        seedHint: seedHint,
      );

  static Future<ChurchDataAuditReport> runFullAudit({String? churchIdHint}) =>
      ChurchDataAudit.runFull(churchIdHint: resolveChurchId(churchIdHint));

  // ─── Módulos ──────────────────────────────────────────────────────────────
  static final departamentos = data.ChurchDataRepository.departamentos;
  static final cargos = data.ChurchDataRepository.cargos;
  static final membros = data.ChurchDataRepository.membros;
  static final eventos = data.ChurchDataRepository.eventos;
  static final avisos = data.ChurchDataRepository.avisos;
  static final chat = data.ChurchDataRepository.chat;
  static final patrimonio = data.ChurchDataRepository.patrimonio;
  static final financeiro = data.ChurchDataRepository.financeiro;
  static final fornecedores = data.ChurchDataRepository.fornecedores;
  static final escalas = data.ChurchDataRepository.escalas;
  static final agenda = data.ChurchDataRepository.agenda;
  static final lideres = data.ChurchDataRepository.lideres;
  static final administrativo = data.ChurchDataRepository.administrativo;
  static final doacoes = data.ChurchDataRepository.doacoes;
  static final mercadopago = data.ChurchDataRepository.mercadopago;
  static final pedidosOracao = data.ChurchDataRepository.pedidosOracao;
  static final transferencias = data.ChurchDataRepository.transferencias;
  static final certificados = data.ChurchDataRepository.certificados;
  static final cartoes = data.ChurchDataRepository.cartoes;

  static Future<ChurchDataDocResult> loadChurchRoot({String? churchIdHint}) =>
      data.ChurchDataRepository.loadChurchRoot(churchIdHint: churchIdHint);

  static Future<ChurchDataLoadResult> loadByChurchId(
    String churchId, {
    String? seedTenantId,
    String? userUid,
  }) =>
      ChurchProfileLoader.loadByChurchId(
        churchId,
        seedTenantId: seedTenantId,
        userUid: userUid,
      );

  static Future<ChurchDataLoadResult> loadChurchData({
    required String seedTenantId,
    String? userUid,
    bool forceRefresh = false,
    bool directDocOnly = false,
  }) =>
      ChurchProfileLoader.loadChurchData(
        seedTenantId: seedTenantId,
        userUid: userUid,
        forceRefresh: forceRefresh,
        directDocOnly: directDocOnly,
      );

  static Future<ChurchSyncDiagnosticReport> runProfileDiagnostic({
    required String seedTenantId,
    String? userUid,
  }) =>
      ChurchProfileLoader.runDiagnostic(
        seedTenantId: seedTenantId,
        userUid: userUid,
      );

  static Future<ChurchSyncDiagnosticReport> runDiagnostic({
    required String seedTenantId,
    String? userUid,
  }) =>
      runProfileDiagnostic(seedTenantId: seedTenantId, userUid: userUid);

  /// Dados já ligados ao contexto da sessão — evita round-trip na abertura.
  static ChurchDataLoadResult? peekCached({
    required String seedTenantId,
    String? userUid,
  }) {
    final data = ChurchContextService.currentChurchData;
    final id = resolveChurchId(seedTenantId);
    if (data == null || data.isEmpty || id.isEmpty) return null;
    return ChurchDataLoadResult(
      seedTenantId: seedTenantId.trim(),
      churchId: id,
      firestorePath: ChurchDataPaths.churchRoot(id),
      data: data,
      fieldCount: data.length,
      loadedAt: ChurchContextService.boundAt ?? DateTime.now(),
      readSource: 'context_cache',
      logoStoragePath: '',
    );
  }

  static WriteBatch batch() => ChurchFirestoreAccess.batch();

  /// Lista com cache Hive primeiro — padrão obrigatório ao abrir módulo.
  static Future<ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>>
      listCacheFirst({
    required ChurchModuleRepositoryBase module,
    String? churchIdHint,
    int limit = 120,
    String? firestoreCacheKey,
  }) =>
      module.listCacheFirst(
        churchIdHint: churchIdHint,
        limit: limit,
        firestoreCacheKey: firestoreCacheKey,
      );

  static void cancelAllListeners() =>
      data.ChurchDataRepository.cancelAllListeners();

  /// Alias legado — `certificados_emitidos`.
  static Future<ChurchDataListResult<QueryDocumentSnapshot<Map<String, dynamic>>>>
      certificadosEmitidos({
    String? churchIdHint,
    int limit = 120,
  }) =>
      certificados.list(churchIdHint: churchIdHint, limit: limit);

  /// Registo opcional quando diagnóstico encontra perfil vazio (Master/debug).
  static Future<void> reportClientEmptyProfile(
    ChurchSyncDiagnosticReport report,
  ) async {}
}
