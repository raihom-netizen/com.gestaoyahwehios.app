import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/services/member_profile_photo_resolver.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, sanitizeImageUrl;

/// Referência a um membro da igreja para avatares no chat (foto com revisão de cache).
class ChurchChatMemberRef {
  const ChurchChatMemberRef({
    required this.memberId,
    required this.data,
    required this.authUid,
    this.photoUrl,
  });

  final String memberId;
  final Map<String, dynamic> data;
  final String authUid;
  final String? photoUrl;
}

/// Mapa `authUid` / `firebaseUid` → URL de foto (membros da igreja) para avatares no chat.
Map<String, String> churchChatMemberPhotoUrlByAuthUid(
  QuerySnapshot<Map<String, dynamic>>? memSnap,
) {
  final map = <String, String>{};
  for (final m in memSnap?.docs ?? []) {
    final ref = _refFromMemberDoc(m.id, m.data());
    if (ref == null) continue;
    final url = ref.photoUrl;
    if (url != null && url.isNotEmpty) {
      map[ref.authUid] = url;
    }
  }
  return map;
}

/// Mapa `authUid` → documento membro (para [FotoMembroWidget] / revisão de foto).
Map<String, ChurchChatMemberRef> churchChatMemberByAuthUid(
  QuerySnapshot<Map<String, dynamic>>? memSnap,
) {
  final map = <String, ChurchChatMemberRef>{};
  for (final m in memSnap?.docs ?? []) {
    final ref = _refFromMemberDoc(m.id, m.data());
    if (ref == null) continue;
    map[ref.authUid] = ref;
  }
  return map;
}

ChurchChatMemberRef? _refFromMemberDoc(
  String memberId,
  Map<String, dynamic> d,
) =>
    churchChatMemberRefFromMemberDoc(memberId, d);

/// Extrai [ChurchChatMemberRef] de um doc `membros/{id}`.
ChurchChatMemberRef? churchChatMemberRefFromMemberDoc(
  String memberId,
  Map<String, dynamic> d,
) {
  var au = (d['authUid'] ?? d['firebaseUid'] ?? '').toString().trim();
  if (au.isEmpty &&
      memberId.length >= 20 &&
      memberId.length <= 128 &&
      !RegExp(r'^\d{11}$').hasMatch(memberId)) {
    au = memberId;
  }
  if (au.isEmpty) return null;
  final resolved = MemberProfilePhotoResolver.displayRef(d, preferThumb: true);
  final url = sanitizeImageUrl(resolved ?? '');
  return ChurchChatMemberRef(
    memberId: memberId,
    data: d,
    authUid: au,
    photoUrl: (url.isNotEmpty &&
            (isValidImageUrl(url) ||
                url.contains('membros/') ||
                url.toLowerCase().startsWith('gs://')))
        ? url
        : null,
  );
}
