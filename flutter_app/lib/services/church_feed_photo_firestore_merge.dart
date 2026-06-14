import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;

/// Merge de paths/URLs de fotos do feed (avisos/eventos) por índice de slot.
abstract final class ChurchFeedPhotoFirestoreMerge {
  ChurchFeedPhotoFirestoreMerge._();

  static List<String> stringListFromFirestore(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<String> photoUrlsFromFirestoreDoc(Map<String, dynamic> data) {
    final out = <String>[];
    for (final key in ['fotos', 'imageUrls', 'imagem_url', 'imageUrl']) {
      final raw = data[key];
      if (raw is List) {
        for (final e in raw) {
          final u = sanitizeImageUrl(e.toString());
          if (u.isNotEmpty && isValidImageUrl(u) && !out.contains(u)) {
            out.add(u);
          }
        }
      } else if (raw != null) {
        final u = sanitizeImageUrl(raw.toString());
        if (u.isNotEmpty && isValidImageUrl(u) && !out.contains(u)) {
          out.add(u);
        }
      }
    }
    return out;
  }

  /// Mantém ordem por slot (0 = capa/banner) sem apagar fotos anteriores.
  static List<String> mergeRefsBySlot({
    required List<String> current,
    required String value,
    required int slotIndex,
    bool skipInvalidUrls = false,
  }) {
    final v = value.trim();
    if (v.isEmpty) return List<String>.from(current);
    if (skipInvalidUrls && !isValidImageUrl(v)) {
      return List<String>.from(current);
    }
    final out = List<String>.from(current);
    while (out.length <= slotIndex) {
      out.add('');
    }
    out[slotIndex] = v;
    while (out.isNotEmpty && out.last.trim().isEmpty) {
      out.removeLast();
    }
    return out;
  }
}
