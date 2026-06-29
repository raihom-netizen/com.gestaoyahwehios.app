import 'dart:convert';

/// Repara texto UTF-8 que foi gravado/lido como Latin-1 (mojibake: `gÃªnero`, `Ã§`, `Â·`).
abstract final class Utf8MojibakeFix {
  Utf8MojibakeFix._();

  static final RegExp _hint = RegExp(
    r'Ã.|Â.|â€|â†|â€œ|â€™|ï¿½',
  );

  /// Repara mojibake quando detectado; caso contrário devolve o original.
  static String repair(String? input) {
    if (input == null || input.isEmpty) return input ?? '';
    var s = input;
    if (!_hint.hasMatch(s)) return s;

    for (var pass = 0; pass < 2; pass++) {
      final fixed = _tryDecode(s);
      if (fixed == null || fixed == s) break;
      s = fixed;
      if (!_hint.hasMatch(s)) break;
    }
    return s;
  }

  static String? _tryDecode(String s) {
    try {
      return utf8.decode(latin1.encode(s));
    } catch (_) {
      return null;
    }
  }
}

/// Atalho para UI / PDF / Firestore.
extension Utf8MojibakeFixExtension on String {
  String get fixedUtf8 => Utf8MojibakeFix.repair(this);
}
