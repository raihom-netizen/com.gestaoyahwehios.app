import 'dart:math';

/// Identificador estilo UUID v4 para protocolo público de certificado (QR).
String generateCertificateProtocolId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = '0123456789abcdef';
  String two(int v) => '${hex[v >> 4]}${hex[v & 0x0f]}';
  return '${two(b[0])}${two(b[1])}${two(b[2])}${two(b[3])}-'
      '${two(b[4])}${two(b[5])}-'
      '${two(b[6])}${two(b[7])}-'
      '${two(b[8])}${two(b[9])}-'
      '${two(b[10])}${two(b[11])}${two(b[12])}${two(b[13])}${two(b[14])}${two(b[15])}';
}
