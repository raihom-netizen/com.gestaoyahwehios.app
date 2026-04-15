import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        SafeCircleAvatarImage,
        imageUrlFromMap,
        memCacheExtentForLogicalSize,
        sanitizeImageUrl;

/// Foto circular de membro com carregamento estável (menos “piscar” ao reconstruir listas).
///
/// **Não** use [Image.network] nem [CachedNetworkImage] **só** com URLs `firebasestorage.googleapis.com`:
/// no **web** costuma falhar (CORS/CanvasKit); no **Android/iOS** URLs tokenizadas do Storage
/// frequentemente travam no loading. Este widget usa [SafeMemberProfilePhoto] → [FirebaseStorageMemoryImage],
/// cache de bytes em RAM com chave estável por **path** do objeto (30 dias) e [memCacheWidth] para não
/// descodificar 4K na lista. Miniaturas `thumb_foto_perfil.jpg` (extensão Resize Images):
/// `ChurchStorageLayout.memberProfileResizeThumbPath`.
///
/// Com [memberData] + [tenantId] + [memberId], **não** bloqueia a UI num `FutureBuilder` global
/// de resolução de URL (isso gerava spinner longo em aniversariantes, listas, etc.). A foto
/// aparece logo: URL do Firestore ou fallback `igrejas/{tenant}/membros/...` em paralelo.
///
/// [size] é o diâmetro em pixels lógicos (equivalente a `radius * 2` do [CircleAvatar]).
class FotoMembroWidget extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String? tenantId;
  final String? memberId;
  final String? cpfDigits;
  final Map<String, dynamic>? memberData;
  final String? authUid;
  final Color? backgroundColor;
  final IconData fallbackIcon;
  final Widget? fallbackChild;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final int? imageCacheRevision;
  /// Pré-visualização local (ex.: logo após escolher foto, antes do upload terminar).
  final Uint8List? memoryPreviewBytes;

  const FotoMembroWidget({
    super.key,
    this.imageUrl,
    this.memoryPreviewBytes,
    this.size = 100,
    this.tenantId,
    this.memberId,
    this.cpfDigits,
    this.memberData,
    this.authUid,
    this.backgroundColor,
    this.fallbackIcon = Icons.person_rounded,
    this.fallbackChild,
    this.memCacheWidth,
    this.memCacheHeight,
    this.imageCacheRevision,
  });

  static String? _mergedMemberImageUrl(String? imageUrl, Map<String, dynamic> d) {
    final u = imageUrl?.trim();
    if (u != null && u.isNotEmpty) return u;
    final m = imageUrlFromMap(d);
    return m.isNotEmpty ? m : null;
  }

  static String? _authUidFromData(Map<String, dynamic> md, String? explicit) {
    final e = explicit?.trim() ?? '';
    if (e.isNotEmpty) return e;
    final a = (md['authUid'] ?? '').toString().trim();
    return a.isEmpty ? null : a;
  }

  @override
  Widget build(BuildContext context) {
    final preview = memoryPreviewBytes;
    if (preview != null && preview.isNotEmpty) {
      return ClipOval(
        child: Image.memory(
          preview,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final defaultMc = memCacheExtentForLogicalSize(
      size,
      dpr,
      oversample: 1.25,
      maxPx: 600,
    );
    final tid = tenantId?.trim();
    final mid = memberId?.trim();
    final bg = backgroundColor ?? ThemeCleanPremium.primary.withOpacity(0.15);
    final err = fallbackChild ??
        CircleAvatar(
          radius: size / 2,
          backgroundColor: bg,
          child: Icon(fallbackIcon,
              size: (size / 2) * 1.05, color: ThemeCleanPremium.primary),
        );

    if (tid != null && tid.isNotEmpty && mid != null && mid.isNotEmpty) {
      final md = memberData;
      final rev = imageCacheRevision ??
          (md != null ? memberPhotoDisplayCacheRevision(md) : null) ??
          0;
      final nomeCompletoMd = md != null
          ? (md['NOME_COMPLETO'] ?? md['nome'] ?? md['name'] ?? '')
              .toString()
              .trim()
          : '';
      final nomeOpt = nomeCompletoMd.isEmpty ? null : nomeCompletoMd;
      final merged =
          md != null ? _mergedMemberImageUrl(imageUrl, md) : imageUrl?.trim();
      final authRaw =
          md != null ? _authUidFromData(md, authUid) : authUid?.trim();
      final authOpt =
          (authRaw == null || authRaw.isEmpty) ? null : authRaw;

      return SafeMemberProfilePhoto(
        key: ValueKey<String>('foto_membro_${tid}_${mid}_$rev'),
        imageUrl: merged,
        tenantId: tid,
        memberId: mid,
        cpfDigits: cpfDigits,
        authUid: authOpt,
        nomeCompleto: nomeOpt,
        memberFirestoreHint: md,
        imageCacheRevision: rev,
        width: size,
        height: size,
        circular: true,
        fit: BoxFit.cover,
        memCacheWidth: memCacheWidth ?? defaultMc,
        memCacheHeight: memCacheHeight ?? defaultMc,
        placeholder: err,
        errorChild: err,
      );
    }

    final urlKey = sanitizeImageUrl(imageUrl);
    final mc = memCacheWidth ?? memCacheHeight ?? defaultMc;
    return SafeCircleAvatarImage(
      key: ValueKey<String>('foto_membro_url_$urlKey'),
      imageUrl: imageUrl,
      radius: size / 2,
      fallbackIcon: fallbackIcon,
      backgroundColor: backgroundColor ?? Colors.grey.shade200,
      memCacheSize: mc,
    );
  }
}
