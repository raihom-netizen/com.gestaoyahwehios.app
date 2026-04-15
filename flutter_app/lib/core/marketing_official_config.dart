import 'package:gestao_yahweh/core/app_constants.dart';

/// Documento raiz com links oficiais (site de divulgação + telas de login).
/// Campos opcionais: quando vazios, usa [AppConstants].
class MarketingOfficialConfig {
  MarketingOfficialConfig._();

  static const String firestoreDocPath = 'config/marketing_official';

  static String _trim(dynamic v) => (v ?? '').toString().trim();

  static String effectiveInstagramUrl(Map<String, dynamic>? data) {
    final v = _trim(
      data?['instagramUrl'] ?? data?['instagram'] ?? data?['linkInstagram'],
    );
    if (v.isNotEmpty) return v;
    return AppConstants.marketingOfficialInstagramUrl.trim();
  }

  static String effectiveYoutubeUrl(Map<String, dynamic>? data) {
    final v = _trim(
      data?['youtubeUrl'] ?? data?['youtube'] ?? data?['linkYoutube'],
    );
    if (v.isNotEmpty) return v;
    return AppConstants.marketingOfficialYoutubeUrl.trim();
  }

  /// Dígitos com DDI, ou URL `wa.me` / `api.whatsapp.com`, ou vazio.
  static String effectiveWhatsAppRaw(Map<String, dynamic>? data) {
    final v = _trim(
      data?['whatsapp'] ??
          data?['whatsappDigits'] ??
          data?['whatsappUrl'] ??
          data?['linkWhatsapp'],
    );
    if (v.isNotEmpty) return v;
    return AppConstants.marketingOfficialWhatsAppDigits.trim();
  }

  /// Nome exibido junto ao título «Canais oficiais» (site e app). Vazio = só marca.
  static String effectiveContactName(Map<String, dynamic>? data) {
    return _trim(
      data?['contactName'] ?? data?['nomeExibicao'] ?? data?['displayName'],
    );
  }
}
