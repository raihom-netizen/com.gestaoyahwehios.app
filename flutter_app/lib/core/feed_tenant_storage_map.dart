import 'package:gestao_yahweh/core/church_storage_layout.dart';

/// Paths físicos `tenants/{id}/media/…` para **novos** uploads de avisos/eventos.
///
/// Leitura continua a aceitar URLs em `igrejas/{id}/…` (legado). Firestore guarda a URL
/// real do objeto (bucket). [canonicalIgrejasPathHint] documenta o alias legado.
abstract final class FeedTenantStorageMap {
  FeedTenantStorageMap._();

  /// `false` = paths canónicos `igrejas/{id}/avisos|eventos/…` (regras Storage + spec).
  /// `true` = legado `tenants/{id}/media/…` (só leitura de URLs antigas).
  static const bool usePhysicalTenantPaths = false;

  static String _safeDocId(String id) {
    var s = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.isEmpty ? 'doc' : s;
  }

  static String tenantRoot(String tenantId) => 'tenants/${tenantId.trim()}';

  /// Extrai tenant de `igrejas/…` ou `tenants/…`.
  static String? tenantIdFromStoragePath(String storagePath) {
    final m = RegExp(r'(?:igrejas|tenants)/([^/]+)/').firstMatch(storagePath);
    final id = m?.group(1)?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Alias documental (não é o path do PUT) — útil em logs / migração.
  static String? canonicalIgrejasPathHint(String physicalPath) {
    final tid = tenantIdFromStoragePath(physicalPath);
    if (tid == null) return null;
    if (physicalPath.startsWith('igrejas/')) return physicalPath;

    final avisoCapa = RegExp(
      r'^tenants/[^/]+/media/avisos/images/([^/]+)/capa_aviso\.webp$',
    ).firstMatch(physicalPath);
    if (avisoCapa != null) {
      return ChurchStorageLayout.avisoPostPhotoVariantPath(
        tid,
        avisoCapa.group(1)!,
        0,
        'full_1920',
      );
    }

    final avisoGal = RegExp(
      r'^tenants/[^/]+/media/avisos/images/([^/]+)/galeria_(\d+)\.webp$',
    ).firstMatch(physicalPath);
    if (avisoGal != null) {
      final slot = int.tryParse(avisoGal.group(2)!) ?? 1;
      return ChurchStorageLayout.avisoPostPhotoPath(tid, avisoGal.group(1)!, slot);
    }

    final evBanner = RegExp(
      r'^tenants/[^/]+/media/eventos/images/([^/]+)/banner_evento\.webp$',
    ).firstMatch(physicalPath);
    if (evBanner != null) {
      return ChurchStorageLayout.eventPostPhotoPath(tid, evBanner.group(1)!, 0);
    }

    final evVid = RegExp(
      r'^tenants/[^/]+/media/eventos/videos/([^/]+)_v(\d)\.mp4$',
    ).firstMatch(physicalPath);
    if (evVid != null) {
      return ChurchStorageLayout.eventHostedVideoMp4Path(
        tid,
        evVid.group(1)!,
        int.tryParse(evVid.group(2)!) ?? 0,
      );
    }

    return null;
  }

  /// Capa / galeria de **aviso** (WebP após compressão no cliente).
  static String feedAvisoPhotoPath(
    String tenantId,
    String postDocId,
    int slotIndex,
  ) {
    if (!usePhysicalTenantPaths) {
      return ChurchStorageLayout.avisoPostPhotoPath(
        tenantId,
        postDocId,
        slotIndex,
      );
    }
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${tenantRoot(tid)}/media/avisos/images/$pid';
    if (slotIndex <= 0) return '$root/capa_aviso.webp';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/galeria_$n.webp';
  }

  /// Banner / galeria de **evento** (notícias no mural).
  static String feedEventoPhotoPath(
    String tenantId,
    String postDocId,
    int slotIndex,
  ) {
    if (!usePhysicalTenantPaths) {
      return ChurchStorageLayout.eventPostPhotoPath(
        tenantId,
        postDocId,
        slotIndex,
      );
    }
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final root = '${tenantRoot(tid)}/media/eventos/images/$pid';
    if (slotIndex <= 0) return '$root/banner_evento.webp';
    final n = slotIndex.toString().padLeft(2, '0');
    return '$root/galeria_$n.webp';
  }

  static String feedEventoHostedVideoMp4Path(
    String tenantId,
    String postDocId,
    int videoSlot,
  ) {
    if (!usePhysicalTenantPaths) {
      return ChurchStorageLayout.eventHostedVideoMp4Path(
        tenantId,
        postDocId,
        videoSlot,
      );
    }
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final s = videoSlot.clamp(0, 1);
    return '${tenantRoot(tid)}/media/eventos/videos/${pid}_v$s.mp4';
  }

  static String feedEventoHostedVideoThumbPath(
    String tenantId,
    String postDocId,
    int videoSlot,
  ) {
    if (!usePhysicalTenantPaths) {
      return ChurchStorageLayout.eventHostedVideoThumbPath(
        tenantId,
        postDocId,
        videoSlot,
      );
    }
    final tid = tenantId.trim();
    final pid = _safeDocId(postDocId);
    final s = videoSlot.clamp(0, 1);
    return '${tenantRoot(tid)}/media/eventos/videos/${pid}_v${s}_thumb.jpg';
  }

  /// Path de upload conforme tipo de post do mural.
  static String feedPhotoPath({
    required String postType,
    required String tenantId,
    required String postDocId,
    required int slotIndex,
  }) {
    final t = postType.trim().toLowerCase();
    if (t == 'evento' || t == 'noticia' || t == 'noticias') {
      return feedEventoPhotoPath(tenantId, postDocId, slotIndex);
    }
    return feedAvisoPhotoPath(tenantId, postDocId, slotIndex);
  }

  /// Spec legado (só documentação).
  static String specAvisoImageHint(String tenantId, String postId) =>
      'tenants/$tenantId/media/avisos/images/$postId';

  static String specEventoVideoHint(String tenantId, String postId) =>
      'tenants/$tenantId/media/eventos/videos/$postId';
}
