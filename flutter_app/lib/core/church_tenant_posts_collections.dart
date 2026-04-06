import 'package:cloud_firestore/cloud_firestore.dart';

/// Subcoleções de mural em `igrejas/{tenantId}/`: avisos separados de eventos.
abstract final class ChurchTenantPostsCollections {
  static const String noticias = 'noticias';
  static const String avisos = 'avisos';

  /// Segmento após `igrejas/{tenantId}/` (ex.: `avisos` ou `noticias`).
  static String segmentFromPostRef(DocumentReference<Map<String, dynamic>> ref) {
    final parts = ref.path.split('/');
    if (parts.length >= 4 && parts[0] == 'igrejas') {
      final seg = parts[2];
      if (seg == avisos || seg == noticias) return seg;
    }
    return noticias;
  }
}
