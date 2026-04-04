/// URL pública (web) apontada pelo QR da carteirinha para consulta/validação.
/// O conteúdo exibido depende das regras de privacidade (dados sensíveis não são públicos no Firestore).
class CarteirinhaConsultaUrl {
  CarteirinhaConsultaUrl._();

  /// Hosting Firebase; se usar CNAME (ex.: gestaoyahweh.com.br), altere para o domínio público.
  static const String baseHost = 'https://gestaoyahweh-21e23.web.app';

  /// Link público usado no QR — path (`/carteirinha-validar?...`) alinhado ao `usePathUrlStrategy` do app web.
  static String validationUrl(String tenantId, String memberId) {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    final q = Uri(queryParameters: {
      'tenantId': tid,
      'memberId': mid,
    }).query;
    return '$baseHost/carteirinha-validar?$q';
  }
}
