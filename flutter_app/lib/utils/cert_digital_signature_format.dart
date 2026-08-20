/// Linha «Dados: DD/MM/AAAA HH:MM:SS» do selo de assinatura digital no PDF.
///
/// Padrão brasileiro, relógio de 24 horas e com segundos — lido como um
/// relógio (ex.: `20/08/2026 09:16:57`). Antes saia no formato ISO invertido
/// com fuso (`2026.03.09 14:29:13 -03'00'`), que é o carimbo do Adobe.
String formatCertificadoDigitalDadosLinha(DateTime when) {
  final da = when.day.toString().padLeft(2, '0');
  final mo = when.month.toString().padLeft(2, '0');
  final y = when.year.toString().padLeft(4, '0');
  final hh = when.hour.toString().padLeft(2, '0'); // 24 h
  final mm = when.minute.toString().padLeft(2, '0');
  final ss = when.second.toString().padLeft(2, '0');
  return 'Dados: $da/$mo/$y $hh:$mm:$ss';
}
