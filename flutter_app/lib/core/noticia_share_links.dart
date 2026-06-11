import 'package:gestao_yahweh/core/app_constants.dart';

/// URLs canónicas para partilha de aviso/evento.
class NoticiaShareLinks {
  const NoticiaShareLinks({
    required this.resolvedSlug,
    required this.publicSiteUrl,
    required this.eventPageUrl,
    required this.socialPreviewUrl,
  });

  /// Slug público efectivo (Firestore slug ou id da igreja).
  final String resolvedSlug;

  /// Home do site público da igreja — nunca a landing da marca.
  final String publicSiteUrl;

  /// Página do evento/aviso no site da igreja (`/{slug}/{id}`).
  final String eventPageUrl;

  /// Preview social (OG) — opcional na mensagem.
  final String socialPreviewUrl;
}

/// Slug público: campo `slug` / `slugId` / `alias` ou id da igreja.
String resolveChurchPublicSlug({
  String? churchSlug,
  String? tenantId,
  Map<String, dynamic>? churchData,
}) {
  if (churchData != null && churchData.isNotEmpty) {
    final fromDoc = (churchData['slug'] ??
            churchData['slugId'] ??
            churchData['alias'] ??
            '')
        .toString()
        .trim();
    if (fromDoc.isNotEmpty) return fromDoc;
  }
  final slug = (churchSlug ?? '').trim();
  if (slug.isNotEmpty) return slug;
  return (tenantId ?? '').trim();
}

NoticiaShareLinks resolveNoticiaShareLinks({
  required String tenantId,
  required String noticiaId,
  String? churchSlug,
  Map<String, dynamic>? churchData,
}) {
  final tid = tenantId.trim();
  final nid = noticiaId.trim();
  final slug = resolveChurchPublicSlug(
    churchSlug: churchSlug,
    tenantId: tid,
    churchData: churchData,
  );

  final publicSite = slug.isNotEmpty
      ? AppConstants.publicChurchHomeUrl(slug)
      : (tid.isNotEmpty
          ? AppConstants.publicChurchHomeUrl(tid)
          : AppConstants.effectivePublicWebBaseUrl);

  final eventSlug = slug.isNotEmpty ? slug : tid;
  final eventPage = eventSlug.isNotEmpty && nid.isNotEmpty
      ? AppConstants.shareNoticiaPublicUrl(eventSlug, nid)
      : (tid.isNotEmpty && nid.isNotEmpty
          ? AppConstants.shareNoticiaCardUrl(tid, nid)
          : publicSite);

  final social = AppConstants.shareNoticiaSocialPreviewUrl(
    slug,
    nid,
    tid,
  );

  return NoticiaShareLinks(
    resolvedSlug: eventSlug,
    publicSiteUrl: publicSite,
    eventPageUrl: eventPage,
    socialPreviewUrl: social,
  );
}
