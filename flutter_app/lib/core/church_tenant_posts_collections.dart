import 'package:cloud_firestore/cloud_firestore.dart';

/// Subcoleções de mural em `igrejas/{tenantId}/`: avisos e eventos.
abstract final class ChurchTenantPostsCollections {
  /// Coleção canónica de eventos no Firestore.
  static const String eventos = 'eventos';

  /// Legado (pré-migração v1) — só leitura de paths antigos até CF concluir.
  static const String legacyNoticias = 'noticias';

  static const String avisos = 'avisos';

  static bool isEventosSegment(String segment) =>
      segment == eventos || segment == legacyNoticias;

  /// Segmento canónico após `igrejas/{tenantId}/` (ex.: `avisos` ou `eventos`).
  static String segmentFromPostRef(DocumentReference<Map<String, dynamic>> ref) {
    final parts = ref.path.split('/');
    if (parts.length >= 4 && parts[0] == 'igrejas') {
      final seg = parts[2];
      if (seg == avisos) return avisos;
      if (isEventosSegment(seg)) return eventos;
    }
    return eventos;
  }
}
