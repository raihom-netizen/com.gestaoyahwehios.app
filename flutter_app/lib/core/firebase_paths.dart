import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Fachada de paths Firebase (Firestore + Storage) para uso em UI/serviços.
///
/// Regra: sempre resolve [churchId] dinamicamente; nunca hardcode de tenant.
abstract final class FirebasePaths {
  FirebasePaths._();

  static String _id(String churchId) => ChurchRepository.churchId(churchId.trim());

  // --- Firestore ---
  static String igreja(String churchId) => ChurchDataPaths.churchRoot(_id(churchId));

  static String departamentos(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.departamentos);

  static String departamentoDoc(String churchId, String deptId) =>
      '${departamentos(churchId)}/${deptId.trim()}';

  static String membros(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.membros);

  static String visitantes(String churchId) => '${igreja(churchId)}/visitantes';

  static String cargos(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.cargos);

  static String chat(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.chats);

  static String escalas(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.escalas);

  static String muralAvisos(String churchId) => '${igreja(churchId)}/mural_avisos';

  static String avisos(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.avisos);

  static String eventos(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.eventos);

  static String chatMessages(String churchId, String chatId) =>
      '${chat(churchId)}/${chatId.trim()}/messages';

  static String certificados(String churchId) => '${igreja(churchId)}/certificados';

  static String patrimonio(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.patrimonio);

  static String pedidosOracao(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.pedidosOracao);

  static String transferencias(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.transferencias);

  static String configMercadoPago(String churchId) =>
      '${ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.config)}/mercado_pago';

  static String finance(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.financeiro);

  static String financeDoc(String churchId, String financeId) =>
      '${finance(churchId)}/${financeId.trim()}';

  static String financeLogs(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.financeLogs);

  static String financeMpNotifications(String churchId) =>
      ChurchDataPaths.subcollection(
        _id(churchId),
        ChurchDataPaths.financeMpNotifications,
      );

  static String fornecedores(String churchId) =>
      ChurchDataPaths.subcollection(_id(churchId), ChurchDataPaths.fornecedores);

  static String fornecedorDoc(String churchId, String fornecedorId) =>
      '${fornecedores(churchId)}/${fornecedorId.trim()}';

  static String fornecedorCompromissos(String churchId) => ChurchDataPaths
      .subcollection(_id(churchId), ChurchDataPaths.fornecedorCompromissos);

  static String fornecedorCompromissoDoc(String churchId, String compromissoId) =>
      '${fornecedorCompromissos(churchId)}/${compromissoId.trim()}';

  // --- Storage (delega a [ChurchStorageLayout]) ---
  static String storageRoot(String churchId) =>
      ChurchStorageLayout.churchRoot(_id(churchId));

  static String storageLogoPath(String churchId) =>
      ChurchStorageLayout.churchIdentityLogoPath(_id(churchId));

  static String storageMemberProfilePhoto(
    String churchId,
    String memberStorageFolderId,
  ) =>
      ChurchStorageLayout.memberProfilePhotoPath(
        _id(churchId),
        memberStorageFolderId,
      );

  static String storageMemberProfileThumb(
    String churchId,
    String memberStorageFolderId,
  ) =>
      ChurchStorageLayout.memberProfileThumbPath(
        _id(churchId),
        memberStorageFolderId,
      );

  static String storageAvisoPhoto(
    String churchId,
    String postId,
    int slotIndex,
  ) =>
      ChurchStorageLayout.avisoPostPhotoPath(_id(churchId), postId, slotIndex);

  static String storageEventoPhoto(
    String churchId,
    String postId,
    int slotIndex,
  ) =>
      ChurchStorageLayout.eventPostPhotoPath(_id(churchId), postId, slotIndex);

  static String storageEventoVideo(
    String churchId,
    String postId,
    int videoSlot,
  ) =>
      ChurchStorageLayout.eventHostedVideoMp4Path(
        _id(churchId),
        postId,
        videoSlot,
      );

  static String storageEventoVideoThumb(
    String churchId,
    String postId,
    int videoSlot,
  ) =>
      ChurchStorageLayout.eventHostedVideoThumbPath(
        _id(churchId),
        postId,
        videoSlot,
      );

  static String storagePatrimonioPhoto(
    String churchId,
    String itemId,
    int slot,
  ) =>
      ChurchStorageLayout.patrimonioPhotoPath(_id(churchId), itemId, slot);

  static String storageFinanceComprovante({
    required String churchId,
    required String lancamentoId,
    DateTime? referenceDate,
    String ext = 'jpg',
  }) =>
      ChurchStorageLayout.financeComprovantePath(
        tenantId: _id(churchId),
        lancamentoId: lancamentoId,
        referenceDate: referenceDate,
        ext: ext,
      );

  static String storageFornecedorComprovante({
    required String churchId,
    required String fornecedorId,
    required String compromissoId,
    String ext = 'jpg',
  }) =>
      ChurchStorageLayout.fornecedorCompromissoComprovantePath(
        tenantId: _id(churchId),
        fornecedorId: fornecedorId,
        compromissoId: compromissoId,
        ext: ext,
      );

  static String storageChatMediaObject({
    required String churchId,
    required String threadId,
    required String kind,
    required String uid,
    required int timestampMs,
    required String fileName,
  }) =>
      ChurchStorageLayout.buildChatMediaObjectPath(
        tenantId: _id(churchId),
        threadId: threadId,
        kind: kind,
        uid: uid,
        timestampMs: timestampMs,
        fileName: fileName,
      );

  static String storageChatMediaThumb({
    required String churchId,
    required String uid,
    required int timestampMs,
    String suffix = 'thumb',
  }) =>
      ChurchStorageLayout.buildChatMediaThumbPath(
        tenantId: _id(churchId),
        uid: uid,
        timestampMs: timestampMs,
        suffix: suffix,
      );

  static String storageCartaoMembroLogo(String churchId) =>
      ChurchStorageLayout.cartaoMembroLogoPath(_id(churchId));

  static String storageCertificadosPrefix(String churchId) =>
      ChurchStorageLayout.certificadoDedicatedMediaPrefix(_id(churchId));

  static String storageMarketingCapa(String churchId) =>
      ChurchStorageLayout.marketingClienteShowcaseCapaPath(_id(churchId));

  static String storageCertificadoGestorP12(
    String churchId,
    String uid,
    int timestampMs,
  ) =>
      '${storageRoot(churchId)}/certificados_gestor/${uid.trim()}_$timestampMs.p12';

  static String storageChatMediaProbe(String churchId) =>
      '${storageChatMediaPrefix(churchId)}.probe';

  static String storageChatMediaPrefix(String churchId) =>
      '${storageRoot(churchId)}/chat_media/';

  static String storageEventTemplateCover(String churchId, String uniqueId) =>
      ChurchStorageLayout.eventTemplateCoverPath(_id(churchId), uniqueId);

  /// Upload genérico com pasta + doc + timestamp sob a raiz da igreja.
  static String storageGenericUploadPath({
    required String churchId,
    required String folder,
    required String documentId,
    required int timestampMs,
  }) =>
      '${storageRoot(churchId)}/${folder.trim()}/${documentId.trim()}/$timestampMs';

  // --- Marketing / site de divulgação (global, não tenant) ---
  static String marketingInstitutionalVideoPath() =>
      MarketingStorageLayout.defaultInstitutionalVideoPath;

  static String marketingGalleryFirestorePath() =>
      '${MarketingStorageLayout.firestoreCollection}/${MarketingStorageLayout.firestoreGalleryDocId}';

  static String marketingClientesFirestorePath() =>
      '${MarketingStorageLayout.firestoreCollection}/${MarketingStorageLayout.firestoreMarketingClientesDocId}';

  static String marketingSiteFirestorePath() =>
      '${MarketingStorageLayout.firestoreCollection}/${MarketingStorageLayout.firestoreSiteDocId}';

  static String appDownloadsConfigFirestorePath() =>
      MarketingStorageLayout.appDownloadsConfigPath;
}
