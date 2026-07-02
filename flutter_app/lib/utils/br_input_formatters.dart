import 'package:flutter/services.dart';

/// Ex.: `R$ 1.234,56` — dígitos são interpretados como centavos.
class BrCurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    var v = int.tryParse(digits);
    if (v == null) return oldValue;
    const maxCent = 999999999999;
    if (v > maxCent) v = maxCent;
    final reais = v / 100;
    final intPart = reais.floor();
    final frac = (v % 100).toString().padLeft(2, '0');
    final intStr = intPart.toString();
    final buf = StringBuffer();
    final len = intStr.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write('.');
      buf.write(intStr[i]);
    }
    final text = 'R\$ ${buf.toString()},$frac';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Valor inicial para [TextEditingController] com [BrCurrencyInputFormatter].
String formatBrCurrencyInitial(double value) {
  if (value <= 0) return '';
  final cents = (value * 100).round();
  if (cents < 0 || cents > 999999999999) return '';
  final reais = cents / 100;
  final intPart = reais.floor();
  final frac = (cents % 100).toString().padLeft(2, '0');
  final intStr = intPart.toString();
  final buf = StringBuffer();
  final len = intStr.length;
  for (var i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buf.write('.');
    buf.write(intStr[i]);
  }
  return 'R\$ ${buf.toString()},$frac';
}

/// Interpreta texto de moeda mascarada (`R$ …`) ou legado (`500,00` / `500.5`).
double parseBrCurrencyInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 0;
  if (t.startsWith('R\$')) {
    final digits = t.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return 0;
    return int.parse(digits) / 100.0;
  }
  if (t.contains(',')) {
    final norm = t.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(norm) ?? 0;
  }
  return double.tryParse(t.replaceAll(',', '.')) ?? 0;
}

/// Máscara numérica → DD/MM/AAAA ao digitar.
class BrDateDdMmYyyyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length > 8) {
      return oldValue;
    }
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

String formatBrDateDdMmYyyy(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

DateTime? _dateFromDmy(int d, int m, int y) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  try {
    final dt = DateTime(y, m, d);
    if (dt.day != d || dt.month != m) return null;
    return dt;
  } catch (_) {
    return null;
  }
}

/// Interpreta [raw] como DD/MM/AAAA (com ou sem separadores).
DateTime? parseBrDateDdMmYyyy(
  String raw, {
  int minYear = 1900,
  int maxYear = 2100,
}) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final only = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (only.length == 8) {
    final d = int.tryParse(only.substring(0, 2));
    final m = int.tryParse(only.substring(2, 4));
    final y = int.tryParse(only.substring(4, 8));
    if (d == null || m == null || y == null) return null;
    if (y < minYear || y > maxYear) return null;
    return _dateFromDmy(d, m, y);
  }
  final parts = s.split(RegExp(r'[/\-.]'));
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0].trim());
  final m = int.tryParse(parts[1].trim());
  final y = int.tryParse(parts[2].trim());
  if (d == null || m == null || y == null) return null;
  if (y < minYear || y > maxYear) return null;
  return _dateFromDmy(d, m, y);
}

/// Apenas dígitos do telefone (máx. 11 — celular BR).
String brPhoneDigitsOnly(String raw) {
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.length <= 11) return d;
  return d.substring(0, 11);
}

/// Máscara ao digitar — celular: `(62) 9.9170-5247`; fixo 10 díg.: `(62) 3210-5247`.
String brPhoneMaskLive(String raw) {
  final d = brPhoneDigitsOnly(raw);
  if (d.isEmpty) return '';
  if (d.length <= 2) {
    return d.length == 1 ? '($d' : '($d)';
  }

  final ddd = d.substring(0, 2);
  final rest = d.substring(2);
  final b = StringBuffer('($ddd)');

  if (rest.isEmpty) return b.toString();

  final mobile = rest.startsWith('9') || d.length > 10;
  if (mobile) {
    b.write(' ${rest[0]}');
    if (rest.length == 1) return b.toString();
    b.write('.');
    final mid = rest.substring(1);
    if (mid.length <= 4) {
      b.write(mid);
      return b.toString();
    }
    b.write(mid.substring(0, 4));
    if (mid.length > 4) {
      b.write('-');
      b.write(mid.substring(4));
    }
    return b.toString();
  }

  b.write(' ');
  if (rest.length <= 4) {
    b.write(rest);
    return b.toString();
  }
  b.write(rest.substring(0, 4));
  b.write('-');
  b.write(rest.substring(4));
  return b.toString();
}

/// [TextInputFormatter] — telefone BR com máscara `(DD) 9.XXXX-XXXX`.
class BrPhoneInputFormatter extends TextInputFormatter {
  const BrPhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final masked = brPhoneMaskLive(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
