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
}
