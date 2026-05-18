import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/member_profile_photo_update_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Avatar de parceiro no chat — usa [StableMemberAvatar] (revisão `fotoUrlCacheRevision`).
class ChurchChatPeerAvatar extends StatelessWidget {
  const ChurchChatPeerAvatar({
    super.key,
    required this.tenantId,
    required this.peerAuthUid,
    this.memberRef,
    this.radius = 26,
  });

  final String tenantId;
  final String peerAuthUid;
  final ChurchChatMemberRef? memberRef;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ref = memberRef;
    final size = radius * 2;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cachePx = (size * dpr).round().clamp(96, 280);

    final rev = ref != null
        ? MemberProfilePhotoUpdateService.cacheRevisionFromData(ref.data)
        : 0;

    if (ref != null && ref.memberId.isNotEmpty) {
      return StableMemberAvatar(
        key: ValueKey('chat_peer_${tenantId}_${ref.memberId}_$rev'),
        imageUrl: ref.photoUrl,
        tenantId: tenantId,
        memberId: ref.memberId,
        authUid: ref.authUid,
        memberData: ref.data,
        size: size,
        memCacheWidth: cachePx,
        memCacheHeight: cachePx,
      );
    }

    final url = ref?.photoUrl;
    if (url != null && url.isNotEmpty) {
      return SafeCircleAvatarImage(
        imageUrl: url,
        radius: radius,
        memCacheSize: cachePx,
        fallbackIcon: Icons.person_rounded,
        fallbackColor: ThemeCleanPremium.primary,
        backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.1),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: ThemeCleanPremium.primary.withValues(alpha: 0.12),
      child: Icon(
        Icons.person_rounded,
        color: ThemeCleanPremium.primary,
        size: radius,
      ),
    );
  }
}
