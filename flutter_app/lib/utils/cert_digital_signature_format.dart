/// Linha «Dados: aaaa.mm.dd HH:mm:ss ±HH'mm'» para selo de assinatura digital no PDF
/// (padrão próximo a carimbos tipo Adobe Reader).
String formatCertificadoDigitalDadosLinha(DateTime when) {
  final y = when.year.toString().padLeft(4, '0');
  final mo = when.month.toString().padLeft(2, '0');
  final da = when.day.toString().padLeft(2, '0');
  final hh = when.hour.toString().padLeft(2, '0');
  final mm = when.minute.toString().padLeft(2, '0');
  final ss = when.second.toString().padLeft(2, '0');
  final off = when.timeZoneOffset;
  final neg = off.isNegative;
  final totalMin = off.inMinutes.abs();
  final oh = (totalMin ~/ 60).toString().padLeft(2, '0');
  final om = (totalMin % 60).toString().padLeft(2, '0');
  final sign = neg ? '-' : '+';
  return "Dados: $y.$mo.$da $hh:$mm:$ss $sign$oh'$om'";
}
