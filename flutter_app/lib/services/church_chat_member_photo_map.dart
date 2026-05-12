import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap, isValidImageUrl, sanitizeImageUrl;

/// Mapa `authUid` / `firebaseUid` → URL de foto (membros da igreja) para avatares no chat.
Map<String, String> churchChatMemberPhotoUrlByAuthUid(
  QuerySnapshot<Map<String, dynamic>>? memSnap,
) {
  final map = <String, String>{};
  for (final m in memSnap?.docs ?? []) {
    final d = m.data();
    final au = (d['authUid'] ?? d['firebaseUid'] ?? '').toString().trim();
    if (au.isEmpty) continue;
    final url = sanitizeImageUrl(imageUrlFromMap(d));
    if (isValidImageUrl(url)) {
      map[au] = url;
    }
  }
  return map;
}
