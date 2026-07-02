import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/cache/yahweh_module_cache_base.dart';
import 'package:gestao_yahweh/services/church_agenda_load_service.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/church_cargos_load_service.dart';
import 'package:gestao_yahweh/services/church_certificados_load_service.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_eventos_load_service.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/services/church_fornecedores_load_service.dart';
import 'package:gestao_yahweh/services/church_members_load_service.dart';
import 'package:gestao_yahweh/services/church_patrimonio_load_service.dart';
import 'package:gestao_yahweh/services/church_schedules_load_service.dart';
import 'package:gestao_yahweh/services/church_visitantes_load_service.dart';

YahwehModuleLoadSnapshot _docsSnapshot({
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required String readSource,
  String? softError,
  bool fromCache = false,
}) {
  return YahwehModuleLoadSnapshot(
    docs: docs,
    readSource: readSource,
    softError: softError,
    fromCache: fromCache,
  );
}

/// Registo central — um cache ChangeNotifier por módulo (matriz doc mestre §4).
abstract final class YahwehModuleCaches {
  YahwehModuleCaches._();

  static final membros = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_membros',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchMembersLoadService.load(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
        fromCache: r.fromCache,
      );
    },
  );

  static final avisos = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_avisos',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchAvisosLoadService.loadActive(
        churchIdHint: churchId,
        limit: ChurchAvisosLoadService.kModuleListLimit,
      );
      return YahwehModuleLoadSnapshot(
        docs: const [],
        readSource: 'church_avisos_v2_${r.length}',
      );
    },
  );

  static final eventos = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_eventos',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchEventosLoadService.loadFeed(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
        fromCache: r.fromCache,
      );
    },
  );

  static final financeiro = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_financeiro',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
        fromCache: r.fromCache,
      );
    },
  );

  static final escalas = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_escalas',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchSchedulesLoadService.loadEscalas(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
      );
    },
  );

  static final cargos = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_cargos',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchCargosLoadService.load(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
      );
    },
  );

  static final departamentos = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_departamentos',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchDepartmentsLoadService.load(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
      );
    },
  );

  static final certificados = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_certificados',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchCertificadosLoadService.load(
        seedTenantId: churchId,
        forceRefresh: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
      );
    },
  );

  static final patrimonio = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_patrimonio',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchPatrimonioLoadService.load(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
        fromCache: r.fromCache,
      );
    },
  );

  static final fornecedores = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_fornecedores',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchFornecedoresLoadService.load(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
        fromCache: r.fromCache,
      );
    },
  );

  static final agenda = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_agenda',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchAgendaLoadService.loadAll(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
      );
    },
  );

  static final visitantes = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_visitantes',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchVisitantesLoadService.load(
        seedTenantId: churchId,
        forceServer: forceServer,
      );
      return _docsSnapshot(
        docs: r.docs,
        readSource: r.readSource,
        softError: r.softError,
      );
    },
  );

  static final igrejaRoot = YahwehModuleCacheBase(
    prefsKeyPrefix: 'yahweh_igreja_root',
    loader: (churchId, {forceServer = false}) async {
      final r = await ChurchCadastroLoadService.load(
        seedTenantId: churchId,
        forceRefresh: forceServer,
      );
      if (r.data.isEmpty) {
        return const YahwehModuleLoadSnapshot(docs: [], readSource: 'empty');
      }
      return _docsSnapshot(
        docs: [
          _SingleDocSnapshot(id: r.churchId, data: r.data),
        ],
        readSource: r.readSource,
        softError: r.softError,
      );
    },
  );

  /// Fase 1 — P0
  static List<YahwehModuleCacheBase> get phase1 => [
        membros,
        avisos,
        eventos,
        financeiro,
        escalas,
      ];

  /// Fase 2 — P1
  static List<YahwehModuleCacheBase> get phase2 => [
        cargos,
        departamentos,
        certificados,
        patrimonio,
      ];

  /// Fase 2+ — P2
  static List<YahwehModuleCacheBase> get phase3 => [
        fornecedores,
        agenda,
        visitantes,
        igrejaRoot,
      ];

  static List<YahwehModuleCacheBase> get all => [
        ...phase1,
        ...phase2,
        ...phase3,
      ];

  static Future<void> warmUpTenant(String churchId) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    await Future.wait(
      all.map((c) => c.warmUp(cid).catchError((_) {})),
    );
  }

  static Future<void> ensurePhase1(String churchId, {bool forceServer = false}) {
    return Future.wait(
      phase1.map(
        (c) => c.ensureLoaded(churchId, forceServer: forceServer).catchError((_) {}),
      ),
    );
  }

  static Future<void> ensurePhase2(String churchId, {bool forceServer = false}) {
    return Future.wait(
      phase2.map(
        (c) => c.ensureLoaded(churchId, forceServer: forceServer).catchError((_) {}),
      ),
    );
  }

  static Future<void> ensureProductionModules(String churchId,
      {bool forceServer = false}) {
    return Future.wait([
      ensurePhase1(churchId, forceServer: forceServer),
      ensurePhase2(churchId, forceServer: forceServer),
      ensurePhase3(churchId, forceServer: forceServer),
    ]);
  }

  static Future<void> ensurePhase3(String churchId, {bool forceServer = false}) {
    return Future.wait(
      phase3.map(
        (c) => c.ensureLoaded(churchId, forceServer: forceServer).catchError((_) {}),
      ),
    );
  }

  /// Site público + cadastro membro — só avisos/eventos/perfil (rápido).
  static Future<void> warmPublicSiteModules(String churchId) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    await Future.wait([
      avisos.warmUp(cid),
      eventos.warmUp(cid),
      igrejaRoot.warmUp(cid),
    ]);
  }

  static void invalidateTenant(String churchId) {
    for (final c in all) {
      c.invalidate(churchId);
    }
  }
}

class _SingleDocSnapshot implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _SingleDocSnapshot({required this.id, required Map<String, dynamic> data})
      : _dataMap = Map<String, dynamic>.from(data);

  @override
  final String id;

  final Map<String, dynamic> _dataMap;

  @override
  Map<String, dynamic> data() => Map<String, dynamic>.from(_dataMap);

  @override
  SnapshotMetadata get metadata => const _SingleCachedMeta();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('Synthetic doc');

  @override
  bool get exists => true;

  @override
  dynamic operator [](Object field) => _dataMap[field];

  @override
  dynamic get(Object field) => _dataMap[field];
}

class _SingleCachedMeta implements SnapshotMetadata {
  const _SingleCachedMeta();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
