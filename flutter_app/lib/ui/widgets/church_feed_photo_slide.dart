import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        cacheBustImageUrl,
        eventNoticiaMediaCacheRevision,
        eventNoticiaPhotoStoragePathAt,
        feedPostStoragePathFromRef;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        FreshFirebaseStorageImage,
        SafeNetworkImage,
        firebaseStorageMediaUrlLooksLike,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;

/// Uma foto do feed (avisos/eventos) — URL https ou path Storage `igrejas/…`.
class ChurchFeedPhotoSlide extends StatelessWidget {
  const ChurchFeedPhotoSlide({
    super.key,
    required this.mediaRef,
    this.postData,
    this.docId,
    this.churchId,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.memCacheWidth,
    this.memCacheHeight,
    this.skipFreshDisplayUrl = true,
    this.placeholder,
    this.errorWidget,
  });

  final String mediaRef;
  final Map<String, dynamic>? postData;
  final String? docId;
  final String? churchId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final bool skipFreshDisplayUrl;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final raw = mediaRef.trim();
    if (raw.isEmpty) {
      return errorWidget ?? const SizedBox.shrink();
    }

    final w = width ?? 400.0;
    final h = height ?? 300.0;

    final ph = placeholder ??
        Container(
          color: const Color(0xFFF8FAFC),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
    final err = errorWidget ??
        Container(
          color: const Color(0xFFF1F5F9),
          alignment: Alignment.center,
          child: Icon(Icons.image_not_supported_outlined,
              color: Colors.grey.shade500, size: 36),
        );

    final data = postData;
    final rev = data != null ? eventNoticiaMediaCacheRevision(data) : null;
    final url = sanitizeImageUrl(raw);
    final displayUrl =
        rev != null ? cacheBustImageUrl(url, revisionMs: rev) : url;

    String? storagePath;
    if (data != null) {
      for (var i = 0; i < 10; i++) {
        final p = eventNoticiaPhotoStoragePathAt(
          data,
          i,
          docIdHint: docId,
          churchIdHint: churchId,
        );
        if (p != null && p.trim() == raw.replaceAll('\\', '/').trim()) {
          storagePath = p;
          break;
        }
      }
    }
    storagePath ??= feedPostStoragePathFromRef(raw);

    if (isValidImageUrl(displayUrl) &&
        (displayUrl.startsWith('http://') ||
            displayUrl.startsWith('https://'))) {
      return SafeNetworkImage(
        key: ValueKey('feed_https_$displayUrl'),
        imageUrl: displayUrl,
        fit: fit,
        width: w,
        height: h,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: skipFreshDisplayUrl,
      );
    }

    final sp = (storagePath ?? '').trim();
    if (sp.isNotEmpty) {
      return StableStorageImage(
        key: ValueKey('feed_sp_$sp'),
        storagePath: sp,
        imageUrl: isValidImageUrl(url) ? displayUrl : null,
        gsUrl: url.toLowerCase().startsWith('gs://') ? url : null,
        width: w,
        height: h,
        fit: fit,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: skipFreshDisplayUrl,
      );
    }

    final storageLike = url.isNotEmpty &&
        (isFirebaseStorageHttpUrl(url) || firebaseStorageMediaUrlLooksLike(url));
    if (storageLike) {
      return FreshFirebaseStorageImage(
        key: ValueKey('feed_ff_$displayUrl'),
        imageUrl: displayUrl,
        fit: fit,
        width: w,
        height: h,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: ph,
        errorWidget: err,
      );
    }

    if (isValidImageUrl(url)) {
      return SafeNetworkImage(
        key: ValueKey('feed_sn_$displayUrl'),
        imageUrl: displayUrl,
        fit: fit,
        width: w,
        height: h,
        memCacheWidth: memCacheWidth,
        memCacheHeight: memCacheHeight,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: skipFreshDisplayUrl,
      );
    }

    return err;
  }
}
