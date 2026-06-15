/// Perfil de compressão EcoFire antes do upload.
enum EcoFireMediaProfile {
  logo,
  memberProfile,
  memberThumb,
  feedPhoto,
  patrimonio,
  document,
  chat,
}

/// Metadados Firestore — **somente URLs/paths**, nunca blob/Base64.
abstract final class EcoFireFirestoreMeta {
  EcoFireFirestoreMeta._();

  static Map<String, dynamic> churchLogo({
    required String downloadUrl,
    required String storagePath,
  }) =>
      {
        'logoUrl': downloadUrl,
        'logoPath': downloadUrl,
        'logoStoragePath': storagePath,
        'fotoUrl': downloadUrl,
        'contentLastUpdated': DateTime.now().toUtc().toIso8601String(),
      };

  static Map<String, dynamic> memberPhoto({
    required String downloadUrl,
    required String storagePath,
    String? thumbUrl,
    String? thumbPath,
  }) =>
      {
        'photoUrl': downloadUrl,
        'fotoUrl': downloadUrl,
        'FOTO_URL_OU_ID': downloadUrl,
        'photoStoragePath': storagePath,
        'fotoPath': storagePath,
        if (thumbUrl != null && thumbUrl.isNotEmpty) 'photoThumbUrl': thumbUrl,
        if (thumbPath != null && thumbPath.isNotEmpty)
          'photoThumbStoragePath': thumbPath,
      };

  static Map<String, dynamic> evento({
    required String titulo,
    String? descricao,
    List<String> fotos = const [],
    String? videoUrl,
    String? videoStoragePath,
    String? thumbUrl,
    int? videoDurationSec,
  }) =>
      {
        'titulo': titulo,
        if (descricao != null) 'descricao': descricao,
        'fotos': fotos,
        if (videoUrl != null && videoUrl.isNotEmpty) 'video': videoUrl,
        if (videoStoragePath != null && videoStoragePath.isNotEmpty)
          'videoStoragePath': videoStoragePath,
        if (thumbUrl != null && thumbUrl.isNotEmpty) 'videoThumbUrl': thumbUrl,
        if (videoDurationSec != null) 'videoDurationSec': videoDurationSec,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };

  static Map<String, dynamic> aviso({
    required String titulo,
    String? descricao,
    List<String> fotos = const [],
  }) =>
      {
        'titulo': titulo,
        if (descricao != null) 'descricao': descricao,
        'fotos': fotos,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };

  static Map<String, dynamic> patrimonioPhoto({
    required String downloadUrl,
    required String storagePath,
    int slotIndex = 0,
  }) =>
      {
        'url': downloadUrl,
        'storagePath': storagePath,
        'slot': slotIndex,
      };

  static Map<String, dynamic> arquivo({
    required String nome,
    required String downloadUrl,
    required String storagePath,
    required String tipo,
    int? tamanhoBytes,
  }) =>
      {
        'nome': nome,
        'url': downloadUrl,
        'storagePath': storagePath,
        'tipo': tipo,
        if (tamanhoBytes != null) 'tamanho': tamanhoBytes,
      };

  static String cacheBust(String url, [DateTime? at]) {
    final u = url.trim();
    if (u.isEmpty) return u;
    final ts = (at ?? DateTime.now()).millisecondsSinceEpoch;
    final sep = u.contains('?') ? '&' : '?';
    return '$u${sep}_v=$ts';
  }
}
