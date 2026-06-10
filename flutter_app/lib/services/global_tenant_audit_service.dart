import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/chat_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_tenant_media_service.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/extended_publish_verification_services.dart';
import 'package:gestao_yahweh/services/membro_publish_verification_service.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_verification_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Contagens por subcoleção em `igrejas/{churchId}/`.
class ChurchModuleCounts {
  const ChurchModuleCounts({
    this.membros = 0,
    this.eventos = 0,
    this.avisos = 0,
    this.departamentos = 0,
    this.cargos = 0,
    this.patrimonio = 0,
    this.chats = 0,
    this.escalas = 0,
    this.financeiro = 0,
    this.fornecedores = 0,
    this.pedidosOracao = 0,
    this.cartasHistorico = 0,
    this.certificados = 0,
  });

  final int membros;
  final int eventos;
  final int avisos;
  final int departamentos;
  final int cargos;
  final int patrimonio;
  final int chats;
  final int escalas;
  final int financeiro;
  final int fornecedores;
  final int pedidosOracao;
  final int cartasHistorico;
  final int certificados;

  int get total =>
      membros +
      eventos +
      avisos +
      departamentos +
      cargos +
      patrimonio +
      chats +
      escalas +
      financeiro +
      fornecedores +
      pedidosOracao +
      cartasHistorico +
      certificados;
}

/// Status de padronização por módulo.
class ChurchModuleStandardizationStatus {
  const ChurchModuleStandardizationStatus({
    required this.module,
    required this.standardized,
    this.lastError,
    this.firestoreCollection,
    this.storagePrefix,
  });

  final String module;
  final bool standardized;
  final String? lastError;
  final String? firestoreCollection;
  final String? storagePrefix;
}

/// Relatório completo da auditoria global (Fases 1–16).
class GlobalTenantAuditReport {
  const GlobalTenantAuditReport({
    required this.syncReport,
    required this.moduleCounts,
    required this.moduleStatuses,
    required this.auditedAt,
    this.tenantMismatchDetected = false,
    this.legacySeedDetected = false,
    this.lastDocumentPath,
    this.auditNotes = const [],
  });

  final ChurchSyncDiagnosticReport syncReport;
  final ChurchModuleCounts moduleCounts;
  final List<ChurchModuleStandardizationStatus> moduleStatuses;
  final DateTime auditedAt;
  final bool tenantMismatchDetected;
  final bool legacySeedDetected;
  final String? lastDocumentPath;
  final List<String> auditNotes;
}

/// Auditoria global — Firestore + Storage + contagens + módulos.
abstract final class GlobalTenantAuditService {
  GlobalTenantAuditService._();

  static Future<GlobalTenantAuditReport> run({
    required String seedTenantId,
    String? userUid,
  }) async {
    final seed = seedTenantId.trim();
    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    final syncReport = await FirestoreWebGuard.runWithWebRecovery(
      () => ChurchTenantMediaService.runFullDiagnostic(
        seedTenantId: seed,
        userUid: userUid,
      ),
      maxAttempts: kIsWeb ? 4 : 1,
    );

    final churchId = syncReport.resolvedChurchId.trim();
    final legacySeed = TenantResolverService.kBpcLegacyTenantIds.contains(seed);
    final mismatch = syncReport.tenantMismatch || seed != churchId;

    final counts = await _countModules(churchId);
    final statuses = _moduleStatuses(churchId, syncReport);
    final notes = <String>[
      if (legacySeed)
        'Seed legado detectado ($seed) — resolver redireciona para $churchId.',
      if (mismatch) 'Mismatch seed/resolvido — verificar TenantResolver.',
      if (syncReport.storageAligned == false)
        'Storage desalinhado do Firestore.',
      'Plataforma: ${kIsWeb ? 'web' : 'mobile'}.',
      'Padrão: igrejas/{churchId} + igrejas/{churchId}/ no Storage.',
    ];

    return GlobalTenantAuditReport(
      syncReport: syncReport,
      moduleCounts: counts,
      moduleStatuses: statuses,
      auditedAt: DateTime.now(),
      tenantMismatchDetected: mismatch,
      legacySeedDetected: legacySeed,
      lastDocumentPath: syncReport.firestorePath,
      auditNotes: notes,
    );
  }

  static Future<ChurchModuleCounts> _countModules(String churchId) async {
    final id = churchId.trim();
    if (id.isEmpty) return const ChurchModuleCounts();

    Future<int> count(String module, String sub) async {
      try {
        return await ChurchFirestoreAccess.countOnce(
          module: module,
          churchId: id,
          subcollectionName: sub,
        );
      } catch (_) {
        return 0;
      }
    }

    const specs = <(String, String)>[
      ('MEMBROS', ChurchDataPaths.membros),
      ('EVENTOS', ChurchDataPaths.eventos),
      ('AVISOS', ChurchDataPaths.avisos),
      ('DEPARTAMENTOS', ChurchDataPaths.departamentos),
      ('CARGOS', ChurchDataPaths.cargos),
      ('PATRIMÔNIO', ChurchDataPaths.patrimonio),
      ('CHAT', ChurchDataPaths.chats),
      ('ESCALAS', ChurchDataPaths.escalas),
      ('FINANCEIRO', ChurchDataPaths.financeiro),
      ('FORNECEDORES', ChurchDataPaths.fornecedores),
      ('PEDIDOS ORAÇÃO', ChurchDataPaths.pedidosOracao),
      ('TRANSFERÊNCIAS', ChurchDataPaths.transferencias),
      ('CERTIFICADOS', ChurchDataPaths.certificados),
    ];

    final results = <int>[];
    if (kIsWeb) {
      for (final spec in specs) {
        results.add(await count(spec.$1, spec.$2));
        await Future<void>.delayed(const Duration(milliseconds: 70));
      }
    } else {
      results.addAll(
        await Future.wait(specs.map((s) => count(s.$1, s.$2))),
      );
    }

    return ChurchModuleCounts(
      membros: results[0],
      eventos: results[1],
      avisos: results[2],
      departamentos: results[3],
      cargos: results[4],
      patrimonio: results[5],
      chats: results[6],
      escalas: results[7],
      financeiro: results[8],
      fornecedores: results[9],
      pedidosOracao: results[10],
      cartasHistorico: results[11],
      certificados: results[12],
    );
  }

  static List<ChurchModuleStandardizationStatus> _moduleStatuses(
    String churchId,
    ChurchSyncDiagnosticReport sync,
  ) {
    final root = 'igrejas/$churchId';
    final storage = ChurchStorageLayout.churchRoot(churchId);

    String? err(String? e) =>
        (e ?? '').trim().isEmpty ? null : e!.trim();

    bool ok(String? e) => err(e) == null;

    return [
      ChurchModuleStandardizationStatus(
        module: 'Cadastro Igreja',
        standardized: ok(sync.lastError),
        lastError: sync.lastError,
        firestoreCollection: root,
        storagePrefix: '$storage/configuracoes/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Avisos',
        standardized: ok(AvisosPublishVerificationService.lastError),
        lastError: err(AvisosPublishVerificationService.lastError),
        firestoreCollection: '$root/${ChurchTenantPostsCollections.avisos}',
        storagePrefix: '$storage/avisos/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Eventos',
        standardized: ok(EventosPublishVerificationService.lastError),
        lastError: err(EventosPublishVerificationService.lastError),
        firestoreCollection: '$root/${ChurchTenantPostsCollections.eventos}',
        storagePrefix: '$storage/eventos/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Chat',
        standardized: ok(ChatPublishVerificationService.lastError),
        lastError: err(ChatPublishVerificationService.lastError),
        firestoreCollection: '$root/chats',
        storagePrefix: '$storage/chat_media/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Patrimônio',
        standardized: ok(PatrimonioPublishVerificationService.lastError),
        lastError: err(PatrimonioPublishVerificationService.lastError),
        firestoreCollection: '$root/patrimonio',
        storagePrefix: '$storage/patrimonio/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Perfil Membro',
        standardized: ok(MembroPublishVerificationService.lastError),
        lastError: err(MembroPublishVerificationService.lastError),
        firestoreCollection: '$root/membros',
        storagePrefix: '$storage/membros/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Departamentos',
        standardized: true,
        firestoreCollection: '$root/departamentos',
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Cargos',
        standardized: true,
        firestoreCollection: '$root/cargos',
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Escalas',
        standardized: true,
        firestoreCollection: '$root/escalas',
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Configurações',
        standardized: ok(sync.lastError),
        lastError: sync.lastError,
        firestoreCollection: '$root/config',
        storagePrefix: '$storage/configuracoes/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Financeiro',
        standardized: ok(FinanceiroPublishVerificationService.lastError),
        lastError: err(FinanceiroPublishVerificationService.lastError),
        firestoreCollection: '$root/finance',
        storagePrefix: '$storage/financeiro/',
      ),
      ChurchModuleStandardizationStatus(
        module: 'Fornecedores',
        standardized: ok(FornecedorPublishVerificationService.lastError),
        lastError: err(FornecedorPublishVerificationService.lastError),
        firestoreCollection: FornecedorPublishVerificationService.collectionPath(churchId),
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Aprovações',
        standardized: ok(AprovacoesPublishVerificationService.lastError),
        lastError: err(AprovacoesPublishVerificationService.lastError),
        firestoreCollection: '$root/membros',
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Cartão/Carteirinha',
        standardized: ok(CarteirinhaPublishVerificationService.lastError),
        lastError: err(CarteirinhaPublishVerificationService.lastError),
        firestoreCollection: '$root/config/carteira',
        storagePrefix: CarteirinhaPublishVerificationService.storagePrefix(churchId),
      ),
      ChurchModuleStandardizationStatus(
        module: 'Certificados',
        standardized: ok(CertificadosPublishVerificationService.lastError),
        lastError: err(CertificadosPublishVerificationService.lastError),
        firestoreCollection: '$root/certificados_emitidos',
        storagePrefix: CertificadosPublishVerificationService.storagePrefix(churchId),
      ),
      ChurchModuleStandardizationStatus(
        module: 'Pedidos de Oração',
        standardized: ok(OracaoPublishVerificationService.lastError),
        lastError: err(OracaoPublishVerificationService.lastError),
        firestoreCollection: OracaoPublishVerificationService.collectionPath(churchId),
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Transferências',
        standardized: ok(TransferenciaPublishVerificationService.lastError),
        lastError: err(TransferenciaPublishVerificationService.lastError),
        firestoreCollection:
            TransferenciaPublishVerificationService.collectionPath(churchId),
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Dashboard',
        standardized: ok(DashboardPublishVerificationService.lastError),
        lastError: err(DashboardPublishVerificationService.lastError),
        firestoreCollection: root,
        storagePrefix: storage,
      ),
      ChurchModuleStandardizationStatus(
        module: 'Site Público',
        standardized: ok(SitePublicoPublishVerificationService.lastError),
        lastError: err(SitePublicoPublishVerificationService.lastError),
        firestoreCollection: root,
        storagePrefix: storage,
      ),
    ];
  }

  /// Resumo estático da varredura de código (Fase 1) — valores atualizados na sessão de auditoria.
  static Map<String, int> codePatternInventory() => const {
        'FirebaseFirestore.instance (lib/)': 95,
        'FirebaseStorage.instance (lib/)': 18,
        'getDownloadURL() (lib/)': 19,
        'putFile/putData direto (lib/)': 12,
        'collection(igrejas) direto (lib/)': 24,
        'Source.server isolado (lib/)': 35,
      };

  static List<String> priorityMigrationTargets() => const [
        'ui/pages/members_page.dart — Firestore direto + getDownloadURL',
        'ui/pages/cargos_page.dart — Firestore direto',
        'ui/pages/member_card_page.dart — Firestore + Storage direto',
        'ui/pages/igreja_cadastro_page.dart — Storage direto (logo)',
        'services/firebase_storage_service.dart — legado getDownloadURL',
        'ui/widgets/safe_network_image.dart — refresh URL (exibição OK)',
        'ui/admin_* — painel master (fora do tenant igreja)',
        'jimsabores_frota/ — módulo separado',
      ];
}
