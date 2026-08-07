/// Status do pagamento no `back_url` do Checkout Pro (Mercado Pago), a partir de
/// `status`/`collection_status`. Usado para não afirmar "pagamento concluído" quando o
/// retorno foi só uma navegação (recusado, pendente, ou status desconhecido).
///
/// O app usa rotas com `#` (hash router), então o MP às vezes acrescenta a query DENTRO
/// do fragmento (`.../#/slug?status=approved`) em vez de antes dele — por isso checamos
/// os dois lugares antes de assumir que não veio status nenhum.
String? mpPaymentReturnStatus(String url) {
  Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return null;
  }
  String? fromParams(Map<String, String> q) =>
      (q['status'] ?? q['collection_status'])?.trim().toLowerCase();
  final direct = fromParams(uri.queryParameters);
  if (direct != null && direct.isNotEmpty) return direct;
  final frag = uri.fragment;
  final qIdx = frag.indexOf('?');
  if (qIdx >= 0 && qIdx < frag.length - 1) {
    try {
      final fromFrag = fromParams(Uri.splitQueryString(frag.substring(qIdx + 1)));
      if (fromFrag != null && fromFrag.isNotEmpty) return fromFrag;
    } catch (_) {}
  }
  return null;
}
