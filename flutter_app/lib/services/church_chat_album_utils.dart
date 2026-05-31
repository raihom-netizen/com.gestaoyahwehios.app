import 'package:cloud_firestore/cloud_firestore.dart';

/// Agrupa fotos/vídeos enviados juntos (estilo WhatsApp).
abstract final class ChurchChatAlbumUtils {
  ChurchChatAlbumUtils._();

  static String? albumGroupIdFrom(Map<String, dynamic> data) {
    final g = (data['albumGroupId'] ?? '').toString().trim();
    return g.isEmpty ? null : g;
  }

  static int albumIndexFrom(Map<String, dynamic> data) {
    final v = data['albumIndex'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  static int albumCountFrom(Map<String, dynamic> data) {
    final v = data['albumCount'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 1;
  }

  static bool isAlbumCapableType(String type) =>
      type == 'image' || type == 'video';

  /// Lista invertida (mais recente = índice 0). Devolve índice âncora do álbum ou `docIndex` se não for álbum.
  static int? anchorDocIndexOrNull(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int docIndex,
  ) {
    if (docIndex < 0 || docIndex >= docs.length) return null;
    final m = docs[docIndex].data();
    final gid = albumGroupIdFrom(m);
    if (gid == null) return docIndex;
    final sender = (m['senderUid'] ?? '').toString();
    final indices = <int>[];
    for (var j = 0; j < docs.length; j++) {
      final d = docs[j].data();
      if (albumGroupIdFrom(d) == gid &&
          (d['senderUid'] ?? '').toString() == sender &&
          isAlbumCapableType((d['type'] ?? '').toString())) {
        indices.add(j);
      }
    }
    if (indices.isEmpty) return docIndex;
    final anchor = indices.reduce((a, b) => a < b ? a : b);
    return docIndex == anchor ? anchor : null;
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> collectAlbumDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int anchorIndex,
  ) {
    final m = docs[anchorIndex].data();
    final gid = albumGroupIdFrom(m);
    if (gid == null) return [docs[anchorIndex]];
    final sender = (m['senderUid'] ?? '').toString();
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      final data = d.data();
      if (albumGroupIdFrom(data) == gid &&
          (data['senderUid'] ?? '').toString() == sender &&
          isAlbumCapableType((data['type'] ?? '').toString())) {
        out.add(d);
      }
    }
    out.sort((a, b) =>
        albumIndexFrom(a.data()).compareTo(albumIndexFrom(b.data())));
    return out;
  }

  static String threadPreviewForAlbum(int count, {bool hasVideo = false}) {
    if (count <= 1) return hasVideo ? '🎬 Vídeo' : '📷 Foto';
    if (hasVideo) return '📷 $count itens';
    return '📷 $count fotos';
  }
}
