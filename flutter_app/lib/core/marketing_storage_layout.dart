import 'package:gestao_yahweh/core/church_storage_layout.dart';

/// Storage + Firestore do **site de divulgação** (Gestão YAHWEH — não confundir com dados operacionais).
///
/// Pastas canónicas no Storage (galeria institucional):
/// - [institutionalFotosPrefix] — imagens
/// - [institutionalVideosPrefix] — vídeos
/// - [institutionalPdfPrefix] — PDFs
///
/// Igrejas em destaque (foto + dados no Firestore `app_public/marketing_clientes`):
/// - **Novo:** `igrejas/{igrejaTenantId}/marketing_destaque/capa.jpg` (ID = documento em `igrejas/`, ex. `igreja_o_brasil_para_cristo_jardim_goiano`).
/// - **Legado:** [legacyClienteShowcasePhotoPath] → `public/gestao_yahweh/clientes/{entryId}/capa.jpg`
///
/// Firestore `app_public/institutional_gallery` — campo `items` (CMS da galeria).
abstract final class MarketingStorageLayout {
  MarketingStorageLayout._();

  static const String storageRoot = 'public/gestao_yahweh';

  static const String segmentFotos = 'fotos';
  static const String segmentVideos = 'videos';
  static const String segmentPdf = 'pdf';
  static const String segmentClientes = 'clientes';

  static String get institutionalFotosPrefix => '$storageRoot/$segmentFotos';
  static String get institutionalVideosPrefix => '$storageRoot/$segmentVideos';
  static String get institutionalPdfPrefix => '$storageRoot/$segmentPdf';
  static String get clientesRootPrefix => '$storageRoot/$segmentClientes';

  static String segmentFolderForMediaKind(String kind) {
    switch (kind) {
      case 'video':
        return segmentVideos;
      case 'pdf':
        return segmentPdf;
      default:
        return segmentFotos;
    }
  }

  static String institutionalUploadPath(String kind, String fileName) {
    final folder = segmentFolderForMediaKind(kind);
    return '$storageRoot/$folder/$fileName';
  }

  /// ID seguro para pasta legada em `clientes/{id}/` (Firestore + Storage).
  static String sanitizeClienteEntryId(String raw) {
    var s = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.isEmpty ? 'cliente' : s;
  }

  /// Legado — só para leitura de entradas antigas.
  static String clienteShowcaseFolder(String entryId) =>
      '$storageRoot/$segmentClientes/${sanitizeClienteEntryId(entryId)}';

  /// Legado: `public/gestao_yahweh/clientes/{entryId}/capa.jpg`
  static String legacyClienteShowcasePhotoPath(String entryId) =>
      '${clienteShowcaseFolder(entryId)}/capa.jpg';

  @Deprecated('Use resolveClienteCapaStoragePath(item) ou marketing path com igrejaTenantId')
  static String clienteShowcasePhotoPath(String entryId) =>
      legacyClienteShowcasePhotoPath(entryId);

  /// Caminho Storage para exibir capa: `fotoPath` gravado → `igrejas/{tenant}/marketing_destaque/capa.jpg` → legado por [id].
  static String resolveClienteCapaStoragePath(Map<String, dynamic> item) {
    final fp = (item['fotoPath'] ?? '').toString().trim();
    if (fp.isNotEmpty) return fp;
    final tenant = (item['igrejaTenantId'] ?? item['tenantId'] ?? '')
        .toString()
        .trim();
    if (tenant.isNotEmpty) {
      return ChurchStorageLayout.marketingClienteShowcaseCapaPath(tenant);
    }
    final id = (item['id'] ?? '').toString();
    return legacyClienteShowcasePhotoPath(id);
  }

  static const String firestoreCollection = 'app_public';
  static const String firestoreGalleryDocId = 'institutional_gallery';
  static const String firestoreMarketingClientesDocId = 'marketing_clientes';

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
