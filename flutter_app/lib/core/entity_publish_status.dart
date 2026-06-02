/// Estados canónicos de publicação/gravação (avisos, eventos, patrimônio, foto membro).
///
/// Campos Firestore usuais: `publishState`, `photoUploadState`, `deliveryStatus`.
abstract final class EntityPublishStatus {
  EntityPublishStatus._();

  static const String creating = 'creating';
  static const String uploading = 'uploading';
  static const String published = 'published';
  static const String error = 'error';

  /// Legado mural: `uploading` ≡ [uploading].
  static const String legacyProcessing = uploading;

  static const String photoUploadStateField = 'photoUploadState';
  static const String publishStateField = 'publishState';
}
