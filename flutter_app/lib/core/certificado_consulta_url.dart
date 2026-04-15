import 'package:gestao_yahweh/core/carteirinha_consulta_url.dart';

/// URL pública (hash routing) para o QR de autenticidade nos certificados **Gala Luxo**.
///
/// A página confirma que o documento pertence ao ecossistema Gestão YAHWEH; a validação
/// plena permanece com a secretaria da igreja.
///
/// **Protocolo UUID** ([protocolValidationUrl]): aponta para `/#/validar?cid=` e resolve
/// `igrejas/{tenantId}/certificados_protocol_index` (collection group) → `certificados_emitidos` (legado na raiz).
/// O QR no PDF é gerado em vetor pelo pacote `pdf`
/// ([BarcodeWidget]), sem ficheiro de imagem no Storage.
class CertificadoConsultaUrl {
  CertificadoConsultaUrl._();

  /// QR com protocolo único (ex.: após gravar em [certificados_emitidos]).
  /// Alinhado a `gestaoyahweh.com.br/validar/{id}` quando o domínio aponta para o mesmo hosting.
  static String protocolValidationUrl(String certificadoId) {
    final cid = certificadoId.trim();
    if (cid.isEmpty) return '';
    final q = Uri(queryParameters: {'cid': cid}).query;
    return '${CarteirinhaConsultaUrl.baseHost}/#/validar?$q';
  }

  /// Formato legado (query tenant/member/tipo) — mantido para links antigos.
  static String validationUrl({
    required String tenantId,
    required String memberId,
    required String certTipoId,
    required String issuedKey,
  }) {
    final tid = tenantId.trim();
    final mid = memberId.trim();
    final tipo = certTipoId.trim();
    final iss = issuedKey.trim();
    final q = Uri(queryParameters: {
      'tenantId': tid,
      'memberId': mid,
      'tipo': tipo,
      'emitido': iss,
    }).query;
    return '${CarteirinhaConsultaUrl.baseHost}/#/certificado-validar?$q';
  }
}
