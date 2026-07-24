import 'dart:async' show TimeoutException, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show
        fetchNoticiaShareMediaBundle,
        noticiaGalleryRefsForShare,
        resolveNoticiaShareSheetMedia;
import 'package:gestao_yahweh/services/noticia_share_prefetch_service.dart';
import 'package:gestao_yahweh/services/yahweh_share_service.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/ui/widgets/whatsapp_channel_icon.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageBytesFromDownloadUrl,
        firebaseStorageMediaUrlLooksLike,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaVideosFromDoc,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/ui/widgets/noticia_photo_gallery_page.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;

/// Retângulo do botão para o popover de partilha no iPad.
Rect? shareRectFromContext(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final o = box.localToGlobal(Offset.zero);
  return o & box.size;
}

/// Partilha nativa: tenta vídeo (app), imagem, senão só texto ([Share.share]).
Future<void> noticiaShareNativeRich({
  required String message,
  required String subject,
  String? imageUrl,
  String? videoPlayUrl,
  Rect? sharePositionOrigin,
}) async {
  if (videoPlayUrl != null && videoPlayUrl.trim().isNotEmpty) {
    var vu = sanitizeImageUrl(videoPlayUrl.trim());
    if (!isValidImageUrl(vu) && firebaseStorageMediaUrlLooksLike(vu)) {
      vu = (await AppStorageImageService.instance.resolveImageUrl(
            imageUrl: vu,
          )) ??
          vu;
    }
    if (vu.isNotEmpty &&
        isValidImageUrl(vu) &&
        looksLikeHostedVideoFileUrl(vu)) {
      try {
        final bytes = await firebaseStorageBytesFromDownloadUrl(
          vu,
          maxBytes: 16 * 1024 * 1024,
        );
        if (bytes != null && bytes.length > 512) {
          await YahwehShareService.shareBytes(
            bytes: bytes,
            fileName: 'publicacao.mp4',
            mimeType: 'video/mp4',
            message: message,
            subject: subject,
            sharePositionOrigin: sharePositionOrigin,
          );
          return;
        }
      } catch (_) {}
    }
  }

  final u = imageUrl != null ? sanitizeImageUrl(imageUrl) : '';
  if (u.isNotEmpty && isValidImageUrl(u)) {
    Uint8List? bytes;
    try {
      if (isFirebaseStorageHttpUrl(u)) {
        bytes = await firebaseStorageBytesFromDownloadUrl(
          u,
          maxBytes: 4 * 1024 * 1024,
        );
      }
      if (bytes == null) {
        final response = await http
            .get(
              Uri.parse(u),
              headers: const {'Accept': 'image/*,*/*;q=0.8'},
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          bytes = response.bodyBytes;
        }
      }
      if (bytes != null && bytes.length > 32) {
        final xFile = XFile.fromData(
          bytes,
          name: 'convite.jpg',
          mimeType: 'image/jpeg',
        );
        await YahwehShareService.shareBytes(
          bytes: bytes,
          fileName: 'convite.jpg',
          mimeType: 'image/jpeg',
          message: message,
          subject: subject,
          sharePositionOrigin: sharePositionOrigin,
        );
        return;
      }
    } catch (_) {}
  }

  await YahwehShareService.shareText(
    message,
    subject: subject,
    sharePositionOrigin: sharePositionOrigin,
  );
}

Future<bool> noticiaOpenWhatsAppWithText(String message) =>
    YahwehWhatsAppService.openNoticiaBroadcast(message);

/// Resolve mídia só quando o utilizador escolhe “Compartilhar…” — o sheet abre antes.
Future<void> _runNativeShareWithOptionalLazyMedia({
  required BuildContext rootContext,
  required String shareMessage,
  required String shareSubject,
  String? previewImageUrl,
  String? videoPlayUrl,
  Rect? sharePositionOrigin,
  Map<String, dynamic>? noticiaDataForLazyMedia,
}) async {
  if (noticiaDataForLazyMedia != null) {
    if (rootContext.mounted) {
      showDialog<void>(
        context: rootContext,
        barrierDismissible: false,
        builder: (c) => Center(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
            child: const Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
    }
    var loadingPopped = false;
    void popLoading() {
      if (loadingPopped) return;
      loadingPopped = true;
      if (rootContext.mounted) {
        Navigator.of(rootContext, rootNavigator: true).pop();
      }
    }

    try {
      final media = await fetchNoticiaShareMediaBundle(
        noticiaDataForLazyMedia,
        maxPhotos: 5,
        includeVideo: true,
        tenantId: (noticiaDataForLazyMedia['tenantId'] ??
                noticiaDataForLazyMedia['churchId'])
            ?.toString(),
        postId: (noticiaDataForLazyMedia['id'] ??
                noticiaDataForLazyMedia['postId'])
            ?.toString(),
        collection: (noticiaDataForLazyMedia['collection'] ??
                noticiaDataForLazyMedia['type'])
            ?.toString(),
      ).timeout(const Duration(seconds: 12));
      // Fecha o loading ANTES de abrir a folha nativa (sem spinner preso).
      popLoading();
      if (media.isNotEmpty) {
        await YahwehShareService.shareMediaBundle(
          files: media,
          message: shareMessage,
          subject: shareSubject,
          sharePositionOrigin: sharePositionOrigin,
        );
        return;
      }
    } catch (_) {
      popLoading();
    }
    popLoading();
  }

  var img = previewImageUrl;
  var vid = videoPlayUrl;
  if (noticiaDataForLazyMedia != null &&
      (img == null || img.isEmpty) &&
      (vid == null || vid.isEmpty)) {
    if (rootContext.mounted) {
      showDialog<void>(
        context: rootContext,
        barrierDismissible: false,
        builder: (c) => Center(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            ),
            child: const Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
    }
    try {
      final m = await resolveNoticiaShareSheetMedia(
        noticiaDataForLazyMedia,
        resolveTimeout: const Duration(seconds: 5),
      );
      img = m.previewImageUrl;
      vid = m.videoPlayUrl;
    } finally {
      if (rootContext.mounted) {
        Navigator.of(rootContext, rootNavigator: true).pop();
      }
    }
  }
  await noticiaShareNativeRich(
    message: shareMessage,
    subject: shareSubject,
    imageUrl: img,
    videoPlayUrl: vid,
    sharePositionOrigin: sharePositionOrigin,
  );
}

/// Bottom sheet estilo feed: copiar link, partilha nativa, WhatsApp.
///
/// [noticiaDataForLazyMedia]: quando preenchido, URLs de imagem/vídeo podem ser omitidas;
/// a resolução (Storage) corre só ao tocar em **Compartilhar…**, para o sheet abrir na hora.
Future<void> showChurchNoticiaShareSheet(
  BuildContext context, {
  required String shareLink,
  required String shareMessage,
  required String shareSubject,
  String? previewImageUrl,
  String? videoPlayUrl,
  Rect? sharePositionOrigin,
  Map<String, dynamic>? noticiaDataForLazyMedia,
}) async {
  final galleryUrls = noticiaDataForLazyMedia != null
      ? noticiaGalleryRefsForShare(noticiaDataForLazyMedia)
      : <String>[];
  final rootContext = context;

  // Há mídia (fotos/vídeos) para enviar junto no WhatsApp? (web + Android + iOS)
  final bool hasVideoForShare = (() {
    if ((videoPlayUrl ?? '').trim().isNotEmpty) return true;
    if (noticiaDataForLazyMedia == null) return false;
    if ((eventNoticiaHostedVideoPlayUrl(noticiaDataForLazyMedia) ?? '')
        .trim()
        .isNotEmpty) {
      return true;
    }
    return eventNoticiaVideosFromDoc(noticiaDataForLazyMedia).isNotEmpty;
  })();
  final bool canShareWhatsAppMedia = noticiaDataForLazyMedia != null &&
      (galleryUrls.isNotEmpty || hasVideoForShare);
  final int photoCount = galleryUrls.length;
  final String whatsAppSubtitle = canShareWhatsAppMedia
      ? (photoCount > 1
          ? 'Vão as $photoCount fotos${hasVideoForShare ? ' e vídeos' : ''} + texto'
          : (hasVideoForShare
              ? 'Vão foto e vídeo + texto premium'
              : 'Vai a foto + texto premium'))
      : 'Texto premium + link com prévia (fotos/vídeos)';

  if (noticiaDataForLazyMedia != null) {
    final tid = (noticiaDataForLazyMedia['tenantId'] ??
            noticiaDataForLazyMedia['churchId'] ??
            '')
        .toString()
        .trim();
    final pid = (noticiaDataForLazyMedia['id'] ??
            noticiaDataForLazyMedia['postId'] ??
            noticiaDataForLazyMedia['docId'] ??
            '')
        .toString()
        .trim();
    final colRaw =
        (noticiaDataForLazyMedia['collection'] ?? noticiaDataForLazyMedia['type'] ?? 'eventos')
            .toString()
            .trim()
            .toLowerCase();
    final col = (colRaw == 'avisos' || colRaw == 'aviso') ? 'avisos' : 'eventos';
    if (tid.isNotEmpty && pid.isNotEmpty) {
      unawaited(NoticiaSharePrefetchService.warm(
        tenantId: tid,
        postId: pid,
        collection: col,
      ));
    }
    unawaited(
      resolveNoticiaShareSheetMedia(
        noticiaDataForLazyMedia,
        resolveTimeout: const Duration(seconds: 4),
      ),
    );
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(ctx).bottom + 8,
          left: 12,
          right: 12,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: const BorderRadius.all(
                Radius.circular(ThemeCleanPremium.radiusMd)),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFE8EDF3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Compartilhar',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Material(
                  color: const Color(0xFF16A34A),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (canShareWhatsAppMedia) {
                        // Com mídia: folha nativa leva TODAS as fotos + vídeos
                        // + legenda para o WhatsApp (API wa.me não anexa mídia).
                        unawaited(_runNativeShareWithOptionalLazyMedia(
                          rootContext: rootContext,
                          shareMessage: shareMessage,
                          shareSubject: shareSubject,
                          previewImageUrl: previewImageUrl,
                          videoPlayUrl: videoPlayUrl,
                          sharePositionOrigin: sharePositionOrigin,
                          noticiaDataForLazyMedia: noticiaDataForLazyMedia,
                        ));
                      } else {
                        unawaited(() async {
                          final ok =
                              await noticiaOpenWhatsAppWithText(shareMessage);
                          if (!ok && rootContext.mounted) {
                            YahwehWhatsAppService.showOpenFailedSnack(
                                rootContext);
                          }
                        }());
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          const WhatsappBrandIcon(size: 22, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Enviar no WhatsApp',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  whatsAppSubtitle,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white.withValues(alpha: 0.85),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (galleryUrls.length > 1 && noticiaDataForLazyMedia != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: galleryUrls.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final u = sanitizeImageUrl(galleryUrls[i]);
                        final path = eventNoticiaPhotoStoragePathAt(
                            noticiaDataForLazyMedia, i);
                        return Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              if (!rootContext.mounted) return;
                              Navigator.of(rootContext).push(
                                MaterialPageRoute<void>(
                                  fullscreenDialog: true,
                                  builder: (_) => NoticiaPhotoGalleryPage(
                                    firestoreData: noticiaDataForLazyMedia,
                                    imageRefs: galleryUrls,
                                    title: shareSubject,
                                    isEvento: (noticiaDataForLazyMedia['type'] ??
                                                '')
                                            .toString() ==
                                        'evento',
                                    initialIndex: i,
                                  ),
                                ),
                              );
                            },
                            child: SizedBox(
                              width: 86,
                              height: 86,
                              child: ColoredBox(
                                color: const Color(0xFFF1F5F9),
                                child: StableStorageImage(
                                  storagePath: path,
                                  imageUrl:
                                      isValidImageUrl(u) ? u : null,
                                  width: 86,
                                  height: 86,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 200,
                                  memCacheHeight: 200,
                                  skipFreshDisplayUrl: false,
                                  placeholder: const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                  errorWidget: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              _ShareSheetTile(
                icon: Icons.link_rounded,
                label: 'Copiar link',
                onTap: () async {
                  Navigator.pop(ctx);
                  await Clipboard.setData(ClipboardData(text: shareLink));
                  if (!rootContext.mounted) return;
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    ThemeCleanPremium.successSnackBar('Link copiado'),
                  );
                },
              ),
              _ShareSheetTile(
                icon: Icons.ios_share_rounded,
                label: 'Compartilhar…',
                subtitle: 'Escolher app (mensagens, e-mail, etc.)',
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_runNativeShareWithOptionalLazyMedia(
                    rootContext: rootContext,
                    shareMessage: shareMessage,
                    shareSubject: shareSubject,
                    previewImageUrl: previewImageUrl,
                    videoPlayUrl: videoPlayUrl,
                    sharePositionOrigin: sharePositionOrigin,
                    noticiaDataForLazyMedia: noticiaDataForLazyMedia,
                  ));
                },
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      minimumSize:
                          const Size(0, ThemeCleanPremium.minTouchTarget),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusMd),
                      ),
                    ),
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ShareSheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  const _ShareSheetTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ThemeCleanPremium.hapticAction();
          onTap();
        },
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(icon, color: ThemeCleanPremium.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
