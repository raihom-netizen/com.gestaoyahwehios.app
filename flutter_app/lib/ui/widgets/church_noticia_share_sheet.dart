import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageBytesFromDownloadUrl,
        firebaseStorageMediaUrlLooksLike,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart' show looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show resolveNoticiaShareSheetMedia;

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
  if (!kIsWeb &&
      videoPlayUrl != null &&
      videoPlayUrl.trim().isNotEmpty) {
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
          final xFile = XFile.fromData(
            bytes,
            name: 'publicacao.mp4',
            mimeType: 'video/mp4',
          );
          await Share.shareXFiles(
            [xFile],
            text: message,
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
        await Share.shareXFiles(
          [xFile],
          text: message,
          subject: subject,
          sharePositionOrigin: sharePositionOrigin,
        );
        return;
      }
    } catch (_) {}
  }

  await Share.share(
    message,
    subject: subject,
    sharePositionOrigin: sharePositionOrigin,
  );
}

Future<void> noticiaOpenWhatsAppWithText(String message) async {
  final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}');
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

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
        resolveTimeout: const Duration(seconds: 8),
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
  final rootContext = context;
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
              _ShareSheetTile(
                icon: Icons.chat_rounded,
                label: 'WhatsApp',
                subtitle: 'Abrir com texto do convite',
                onTap: () {
                  Navigator.pop(ctx);
                  Future<void>.microtask(
                      () => noticiaOpenWhatsAppWithText(shareMessage));
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
