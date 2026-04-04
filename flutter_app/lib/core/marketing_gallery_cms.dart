/// CMS da galeria institucional no site (`app_public/institutional_gallery` + Storage `public/gestao_yahweh/`).
abstract final class MarketingGalleryCms {
  MarketingGalleryCms._();

  static const String categoryMarketing = 'marketing';
  static const String categoryTreinamento = 'treinamento';
  static const String categoryInstitucional = 'institucional';

  static const List<String> categoryKeys = [
    categoryMarketing,
    categoryTreinamento,
    categoryInstitucional,
  ];

  static String categoryLabel(String? key) {
    switch ((key ?? '').toLowerCase().trim()) {
      case categoryMarketing:
        return 'Marketing';
      case categoryTreinamento:
        return 'Treinamento';
      case categoryInstitucional:
        return 'Institucional';
      default:
        return 'Geral';
    }
  }

  static bool truthy(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v?.toString().toLowerCase().trim();
    return s == 'true' || s == '1' || s == 'sim';
  }

  static String normalizeCategory(String? raw) {
    final k = (raw ?? '').toLowerCase().trim();
    if (categoryKeys.contains(k)) return k;
    return categoryInstitucional;
  }
}
