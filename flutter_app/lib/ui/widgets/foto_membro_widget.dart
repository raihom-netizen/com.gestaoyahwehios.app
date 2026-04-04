import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        ResilientNetworkImage,
        SafeCircleAvatarImage,
        imageUrlFromMap,
        isValidImageUrl,
        memCacheExtentForLogicalSize,
        sanitizeImageUrl;

/// Foto circular de membro com carregamento estável (menos “piscar” ao reconstruir listas).
///
/// **Não** use [Image.network] nem [CachedNetworkImage] direto com URLs do Firebase Storage:
/// no **web** costuma falhar (CORS/CanvasKit); no **Android/iOS** URLs tokenizadas do Storage
/// frequentemente travam no loading com cache HTTP puro. Este widget reutiliza o pipeline do app:
/// [ResilientNetworkImage] / [SafeMemberProfilePhoto], cache em memória
/// ([MemberProfilePhotoBytesCache]) e fallback para `igrejas/{tenant}/membros/{id}.jpg`.
///
/// Quando [tenantId] e [memberId] estão preenchidos, o fallback de Storage é ativado
/// (recomendado em listas, aniversariantes, carteirinha).
///
/// [size] é o diâmetro em pixels lógicos (equivalente a `radius * 2` do [CircleAvatar]).
class FotoMembroWidget extends StatelessWidget {
  final String? imageUrl;
  final double size;
  final String? tenantId;
  final String? memberId;
  final String? cpfDigits;
  /// Quando preenchido, resolve [photoStoragePath] / `gs://` do Firestore via [AppStorageImageService]
  /// (URLs só https em [imageUrlFromMap] não cobrem path legado sem URL).
  final Map<String, dynamic>? memberData;
  /// Quando a foto no Storage usa o UID (doc do membro pode ser CPF).
  final String? authUid;
  final Color? backgroundColor;
  final IconData fallbackIcon;
  /// Quando preenchido, substitui o ícone padrão (ex.: inicial do nome em listas).
  final Widget? fallbackChild;
  final int? memCacheWidth;
  final int? memCacheHeight;
  /// Se null e [memberData] preenchido, usa [memberPhotoDisplayCacheRevision].
  final int? imageCacheRevision;

  const FotoMembroWidget({
    super.key,
    this.imageUrl,
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

  /// `gs://` por vezes vem em [fotoUrl]/[photoUrl] em vez de [MemberImageFields.gsPhotoUrl].
  static String? _gsUrlForResolve(Map<String, dynamic> md, String? merged) {
    final from = MemberImageFields.gsPhotoUrl(md);
    if (from != null && from.trim().isNotEmpty) return from.trim();
    final m = merged?.trim() ?? '';
    if (m.toLowerCase().startsWith('gs://')) return m;
    for (final k in [
      'foto_url',
      'fotoUrl',
      'photoUrl',
      'photoURL',
      'FOTO_URL_OU_ID',
      'foto',
      'photo',
    ]) {
      final v = (md[k] ?? '').toString().trim();
      if (v.toLowerCase().startsWith('gs://')) return v;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
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
      final nomeOpt =
          nomeCompletoMd.isEmpty ? null : nomeCompletoMd;
      if (md != null) {
        final sp = MemberImageFields.photoStoragePath(md);
        final merged = _mergedMemberImageUrl(imageUrl, md);
        final gs = _gsUrlForResolve(md, merged);
        final cacheKey = AppStorageImageService.cacheKey(
          storagePath: sp,
          gsUrl: gs,
          imageUrl: merged,
        );
        final future = AppStorageImageService.instance.resolveImageUrl(
          storagePath: sp,
          gsUrl: gs,
          imageUrl: merged,
        );
        final mc = memCacheWidth ?? memCacheHeight ?? defaultMc;
        return FutureBuilder<String?>(
          key: ValueKey<String>('foto_membro_doc_${tid}_${mid}_${cacheKey}_$rev'),
          future: future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && snap.data == null && !snap.hasError) {
              return SizedBox(
                width: size,
                height: size,
                child: ClipOval(
                  child: ColoredBox(
                    color: bg,
                    child: Center(
                      child: SizedBox(
                        width: size * 0.32,
                        height: size * 0.32,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: ThemeCleanPremium.primary.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            final u = snap.hasError ? null : snap.data;
            final clean = u != null ? sanitizeImageUrl(u) : '';
            if (clean.isNotEmpty && isValidImageUrl(clean)) {
              return ClipOval(
                child: SizedBox(
                  width: size,
                  height: size,
                  child: ResilientNetworkImage(
                    key: ValueKey<String>('foto_membro_resolved_${clean}_$rev'),
                    imageUrl: clean,
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    memCacheWidth: mc,
                    memCacheHeight: mc,
                    placeholder: err,
                    errorWidget: SafeMemberProfilePhoto(
                      key: ValueKey<String>('foto_membro_fb_${tid}_${mid}_$rev'),
                      imageUrl: imageUrl,
                      tenantId: tid,
                      memberId: mid,
                      cpfDigits: cpfDigits,
                      authUid: authUid,
                      nomeCompleto: nomeOpt,
                      imageCacheRevision: rev,
                      width: size,
                      height: size,
                      circular: true,
                      fit: BoxFit.cover,
                      memCacheWidth: memCacheWidth ?? defaultMc,
                      memCacheHeight: memCacheHeight ?? defaultMc,
                      errorChild: err,
                    ),
                  ),
                ),
              );
            }
            return SafeMemberProfilePhoto(
              key: ValueKey<String>('foto_membro_${tid}_${mid}_$rev'),
              imageUrl: imageUrl,
              tenantId: tid,
              memberId: mid,
              cpfDigits: cpfDigits,
              authUid: authUid,
              nomeCompleto: nomeOpt,
              imageCacheRevision: rev,
              width: size,
              height: size,
              circular: true,
              fit: BoxFit.cover,
              memCacheWidth: memCacheWidth ?? defaultMc,
              memCacheHeight: memCacheHeight ?? defaultMc,
              errorChild: err,
            );
          },
        );
      }
      return SafeMemberProfilePhoto(
        key: ValueKey<String>('foto_membro_${tid}_${mid}_$rev'),
        imageUrl: imageUrl,
        tenantId: tid,
        memberId: mid,
        cpfDigits: cpfDigits,
        authUid: authUid,
        nomeCompleto: nomeOpt,
        imageCacheRevision: rev,
        width: size,
        height: size,
        circular: true,
        fit: BoxFit.cover,
        memCacheWidth: memCacheWidth ?? defaultMc,
        memCacheHeight: memCacheHeight ?? defaultMc,
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
