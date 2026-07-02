import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';

/// Acesso **directo** do painel igreja — Web = Android = iOS.
///
/// Firestore: `igrejas/{churchId}/{sub}`
/// Storage:   `igrejas/{churchId}/…`
///
/// SaaS directo: `igrejas/{churchId}/…` — sem alias, `church_aliases` nem fallback irmãos.
abstract final class ChurchPanelPaths {
  ChurchPanelPaths._();

  static String churchId([String? shellHint]) =>
      ChurchContext.resolveChurchId(shellHint);

  static String firestoreRoot([String? h]) {
    final id = churchId(h);
    return id.isEmpty ? '' : ChurchDataPaths.churchRoot(id);
  }

  static String storageRoot([String? h]) => ChurchContext.churchStorageRoot(h);

  static DocumentReference<Map<String, dynamic>> churchDoc([String? h]) =>
      ChurchRepository.churchDoc(h);

  static DocumentReference<Map<String, dynamic>> configDoc(
    String docId, [
    String? h,
  ]) =>
      ChurchUiCollections.config(h).doc(docId.trim());

  // ─── Firestore — módulos do painel ───────────────────────────────────────

  static CollectionReference<Map<String, dynamic>> membros([String? h]) =>
      ChurchUiCollections.membros(h);

  static CollectionReference<Map<String, dynamic>> departamentos([String? h]) =>
      ChurchUiCollections.departamentos(h);

  static CollectionReference<Map<String, dynamic>> cargos([String? h]) =>
      ChurchUiCollections.cargos(h);

  static CollectionReference<Map<String, dynamic>> financeiro([String? h]) =>
      ChurchUiCollections.financeiro(h);

  static CollectionReference<Map<String, dynamic>> contas([String? h]) =>
      ChurchUiCollections.contas(h);

  static CollectionReference<Map<String, dynamic>> patrimonio([String? h]) =>
      ChurchUiCollections.patrimonio(h);

  static CollectionReference<Map<String, dynamic>> escalas([String? h]) =>
      ChurchUiCollections.escalas(h);

  static CollectionReference<Map<String, dynamic>> agenda([String? h]) =>
      ChurchUiCollections.agenda(h);

  static CollectionReference<Map<String, dynamic>> eventos([String? h]) =>
      ChurchUiCollections.eventos(h);

  static CollectionReference<Map<String, dynamic>> pedidosOracao([String? h]) =>
      ChurchUiCollections.pedidosOracao(h);

  static CollectionReference<Map<String, dynamic>> visitantes([String? h]) =>
      ChurchUiCollections.visitantes(h);

  static CollectionReference<Map<String, dynamic>> usersIndex([String? h]) =>
      ChurchUiCollections.usersIndex(h);

  static CollectionReference<Map<String, dynamic>> cartoes([String? h]) =>
      ChurchUiCollections.cartoes(h);

  static CollectionReference<Map<String, dynamic>> mercadopago([String? h]) =>
      ChurchUiCollections.mercadopago(h);

  // ─── Storage — pastas canónicas ──────────────────────────────────────────

  static String logoIgreja([String? h]) =>
      ChurchStorageLayout.churchIdentityLogoPath(churchId(h));

  static String membroFoto(String memberId, [String? h]) =>
      ChurchStorageLayout.memberProfilePhotoPath(churchId(h), memberId);

  static String membroThumb(String memberId, [String? h]) =>
      ChurchStorageLayout.memberProfileThumbPath(churchId(h), memberId);

  static String financeComprovante(
    String lancamentoId,
    DateTime when, [
    String? h,
  ]) =>
      ChurchStorageLayout.financeComprovantePath(
        tenantId: churchId(h),
        lancamentoId: lancamentoId,
        referenceDate: when,
      );

  static String patrimonioImagem(String itemId, [String? h]) =>
      ChurchStorageLayout.patrimonioPhotoPath(churchId(h), itemId, 1);

  static String cartaoMembroRoot([String? h]) =>
      '${storageRoot(h)}/${ChurchStorageLayout.kSegCartaoMembro}';

  /// Catálogo canónico — Firestore + Storage por módulo (DEBUG CHURCH / aceite).
  ///
  /// Ex.: `igrejas/igreja_o_brasil_para_cristo_jardim_goiano/membros`
  /// Storage: `igrejas/{churchId}/membros/`
  static List<({String module, String firestorePath, String storagePath})>
      productionModulePaths([String? shellHint]) {
    final id = churchId(shellHint);
    if (id.isEmpty) return const [];
    final fs = firestoreRoot(shellHint);
    final st = storageRoot(shellHint);
    return [
      (
        module: 'CADASTRO',
        firestorePath: fs,
        storagePath: logoIgreja(shellHint),
      ),
      (
        module: 'DEPARTAMENTOS',
        firestorePath: '$fs/${ChurchDataPaths.departamentos}',
        storagePath: st,
      ),
      (
        module: 'CARGOS',
        firestorePath: '$fs/${ChurchDataPaths.cargos}',
        storagePath: st,
      ),
      (
        module: 'MEMBROS',
        firestorePath: '$fs/${ChurchDataPaths.membros}',
        storagePath: '${st}${ChurchStorageLayout.kSegMembros}/',
      ),
      (
        module: 'VISITANTES',
        firestorePath: '$fs/visitantes',
        storagePath: st,
      ),
      (
        module: 'FORNECEDORES',
        firestorePath: '$fs/${ChurchDataPaths.fornecedores}',
        storagePath: '${st}${ChurchStorageLayout.kSegFornecedores}/',
      ),
      (
        module: 'FINANCEIRO',
        firestorePath: '$fs/${ChurchDataPaths.financeiro}',
        storagePath:
            ChurchStorageLayout.financeiroFolderPlaceholderPath(id),
      ),
      (
        module: 'EVENTOS',
        firestorePath: '$fs/${ChurchDataPaths.eventos}',
        storagePath: '${st}${ChurchStorageLayout.kSegEventos}/',
      ),
      (
        module: 'AVISOS',
        firestorePath: '$fs/${ChurchDataPaths.avisos}',
        storagePath: '${st}${ChurchStorageLayout.kSegAvisos}/',
      ),
      (
        module: 'CHAT',
        firestorePath: '$fs/${ChurchDataPaths.chats}',
        storagePath: '${st}${ChurchStorageLayout.kSegChatMedia}/',
      ),
      (
        module: 'PATRIMONIO',
        firestorePath: '$fs/${ChurchDataPaths.patrimonio}',
        storagePath: '${st}${ChurchStorageLayout.kSegPatrimonio}/',
      ),
      (
        module: 'ESCALAS',
        firestorePath: '$fs/${ChurchDataPaths.escalas}',
        storagePath: st,
      ),
      (
        module: 'AGENDA',
        firestorePath: '$fs/${ChurchDataPaths.agenda}',
        storagePath: st,
      ),
      (
        module: 'PEDIDOS_ORACAO',
        firestorePath: '$fs/${ChurchDataPaths.pedidosOracao}',
        storagePath: st,
      ),
      (
        module: 'CERTIFICADOS',
        firestorePath: '$fs/${ChurchDataPaths.certificados}',
        storagePath: '${st}${ChurchStorageLayout.kSegCertificadosMidia}/',
      ),
    ];
  }

  static String storagePathForModuleLabel(String moduleLabel, [String? h]) {
    final normalized = moduleLabel.trim().toUpperCase();
    for (final row in productionModulePaths(h)) {
      if (row.module == normalized ||
          moduleLabel.trim() == _moduleLabelFromKey(row.module)) {
        return row.storagePath;
      }
    }
    return storageRoot(h);
  }

  static String? _moduleLabelFromKey(String key) => switch (key) {
        'CADASTRO' => 'Cadastro Igreja',
        'DEPARTAMENTOS' => 'Departamentos',
        'CARGOS' => 'Cargos',
        'MEMBROS' => 'Membros',
        'VISITANTES' => 'Visitantes',
        'FORNECEDORES' => 'Fornecedores',
        'FINANCEIRO' => 'Financeiro',
        'EVENTOS' => 'Eventos',
        'AVISOS' => 'Avisos',
        'CHAT' => 'Chat',
        'PATRIMONIO' => 'Patrimônio',
        'ESCALAS' => 'Escalas',
        'AGENDA' => 'Agenda',
        'PEDIDOS_ORACAO' => 'Pedidos Oração',
        'CERTIFICADOS' => 'Certificados',
        _ => null,
      };
}
