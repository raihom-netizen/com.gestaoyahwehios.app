import 'dart:html' as html;

/// Atualiza título, meta description, og:image e og:url (preview WhatsApp quando o crawler usa a SPA).
void updateChurchPublicSeoWeb({
  required String title,
  required String description,
  String? ogImageUrl,
  String? canonicalUrl,
}) {
  html.document.title = title;

  void upsertMetaByName(String name, String content) {
    html.MetaElement? el =
        html.document.head?.querySelector('meta[name="$name"]') as html.MetaElement?;
    el ??= html.MetaElement()..setAttribute('name', name);
    el.content = content;
    html.document.head?.append(el);
  }

  void upsertMetaProperty(String property, String content) {
    html.MetaElement? el = html.document.head
        ?.querySelector('meta[property="$property"]') as html.MetaElement?;
    el ??= html.MetaElement()..setAttribute('property', property);
    el.content = content;
    html.document.head?.append(el);
  }

  upsertMetaByName('description', description);
  upsertMetaProperty('og:title', title);
  upsertMetaProperty('og:description', description);
  upsertMetaProperty('og:type', 'website');
  final canon = (canonicalUrl ?? '').trim();
  if (canon.isNotEmpty) {
    upsertMetaProperty('og:url', canon);
  }
  upsertMetaByName('twitter:card', 'summary_large_image');
  upsertMetaByName('twitter:title', title);
  upsertMetaByName('twitter:description', description);
  final img = (ogImageUrl ?? '').trim();
  if (img.isNotEmpty) {
    upsertMetaProperty('og:image', img);
    upsertMetaByName('twitter:image', img);
    upsertMetaProperty('og:image:secure_url', img);
  }
}
