/// Storage + Firestore do **site de divulgação** (Gestão YAHWEH — não confundir com `igrejas/{id}/`).
///
/// No Console Firebase → Storage, crie pastas como:
/// - `public/gestao_yahweh/videos/`
/// - `public/gestao_yahweh/fotos/`
/// - `public/gestao_yahweh/pdf/`
///
/// Opcional: documento Firestore `app_public/institutional_gallery` com campo `items` (lista ordenada)
/// para CMS: `title`, `description`, `category` (marketing|treinamento|institucional), `featured`, `kind`, `path`, `uploadedAt`.
/// Se vazio, o app lista arquivos direto em [storageRoot].
/// Os ficheiros permanecem no Storage até o master remover e optar por apagar o blob.
abstract final class MarketingStorageLayout {
  MarketingStorageLayout._();

  static const String storageRoot = 'public/gestao_yahweh';

  static const String firestoreCollection = 'app_public';
  static const String firestoreGalleryDocId = 'institutional_gallery';

  /// Mesmo formato em lista, grelha e Firestore (evita exclusão que não encontra o item).
  static String normalizeObjectPath(String p) {
    var s = p.replaceAll('\\', '/').trim();
    while (s.contains('//')) {
      s = s.replaceAll('//', '/');
    }
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    return s;
  }
}
