import 'package:gestao_yahweh/core/event_noticia_media.dart';
import 'package:gestao_yahweh/core/noticia_share_utils.dart';

/// Validação defensiva — posts do feed do painel (avisos/eventos).
/// Descarta lixo (sem título válido ou sem mídia) antes da renderização.
abstract final class PanelFeedPostValidator {
  PanelFeedPostValidator._();

  static const int kPanelFeedPageSize = 20;

  static const Set<String> _junkTitles = {
    'sem título',
    'sem titulo',
    'sem titulo.',
    'sem título.',
  };

  static String resolveTitle(Map<String, dynamic> data) {
    for (final k in ['title', 'titulo', 'name', 'nome']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static String resolveText(Map<String, dynamic> data) {
    for (final k in ['text', 'texto', 'description', 'descricao', 'body']) {
      final v = (data[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }

  static bool hasSubstantialText(Map<String, dynamic> data, {int minLen = 12}) =>
      resolveText(data).length >= minLen;

  static bool hasValidTitle(Map<String, dynamic> data) {
    final t = resolveTitle(data);
    if (t.isEmpty) return false;
    if (_junkTitles.contains(t.toLowerCase())) return false;
    return true;
  }

  static bool hasValidMedia(
    Map<String, dynamic> data, {
    String? docId,
    String? churchId,
  }) {
    for (final k in [
      'imageUrl',
      'coverPhotoUrl',
      'coverPhoto',
      'photoUrl',
      'bannerUrl',
      'fotoUrl',
    ]) {
      if ((data[k] ?? '').toString().trim().isNotEmpty) return true;
    }

    for (final k in ['imageUrls', 'galeria', 'photos', 'photoUrls']) {
      final raw = data[k];
      if (raw is List &&
          raw.any((e) => e.toString().trim().isNotEmpty)) {
        return true;
      }
    }

    for (final k in [
      'imageStoragePath',
      'fotoPath',
      'thumbStoragePath',
      'videoPath',
      'bannerStoragePath',
      'storagePath',
    ]) {
      if ((data[k] ?? '').toString().trim().isNotEmpty) return true;
    }

    for (final k in ['imageStoragePaths', 'fotoStoragePaths', 'thumbStoragePaths']) {
      final raw = data[k];
      if (raw is List &&
          raw.any((e) => e.toString().trim().isNotEmpty)) {
        return true;
      }
    }

    final gallery = noticiaGalleryRefsForShare(data);
    if (gallery.any((g) => g.trim().isNotEmpty)) return true;

    final storagePath = eventNoticiaImageStoragePath(data);
    if (storagePath != null && storagePath.trim().isNotEmpty) return true;

    if (docId != null && churchId != null) {
      final p0 = eventNoticiaPhotoStoragePathAt(
        data,
        0,
        docIdHint: docId,
        churchIdHint: churchId,
      );
      if (p0 != null && p0.trim().isNotEmpty) return true;
    }

    for (final k in [
      'videoUrl',
      'thumbUrl',
      'thumbnailUrl',
      'videoThumbUrl',
    ]) {
      if ((data[k] ?? '').toString().trim().isNotEmpty) return true;
    }

    final videos = data['videos'];
    if (videos is List && videos.isNotEmpty) return true;

    return false;
  }

  /// Post apto para card no painel — título + (mídia ou texto substancial).
  static bool isRenderableForPanelFeed(
    Map<String, dynamic> data, {
    String? docId,
    String? churchId,
  }) {
    if (!hasValidTitle(data)) return false;
    if (hasValidMedia(data, docId: docId, churchId: churchId)) return true;
    return hasSubstantialText(data);
  }

  /// Lixo no banco — sem título ou stub vazio (sem mídia e sem texto).
  static bool isCorruptForCleanup(
    Map<String, dynamic> data, {
    String? docId,
    String? churchId,
  }) {
    if (!hasValidTitle(data)) return true;
    if (hasValidMedia(data, docId: docId, churchId: churchId)) return false;
    return !hasSubstantialText(data);
  }
}
