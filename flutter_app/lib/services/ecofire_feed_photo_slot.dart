/// Resultado de um slot — URL + path em `igrejas/{id}/avisos|eventos/{postId}/`.
class EcoFireFeedPhotoSlot {
  const EcoFireFeedPhotoSlot({
    required this.fullUrl,
    required this.thumbUrl,
    required this.fullPath,
    required this.thumbPath,
  });

  final String fullUrl;
  final String thumbUrl;
  final String fullPath;
  final String thumbPath;
}
