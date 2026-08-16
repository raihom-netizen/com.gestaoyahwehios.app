import 'dart:convert';

/// Repara texto UTF-8 que foi gravado/lido como Latin-1 (mojibake).
///
/// IMPORTANTE: este ficheiro e mantido em ASCII puro de proposito. Os
/// caracteres acentuados aparecem apenas como escapes \u..... Ja houve um
/// incidente em que um script de "correcao de acentos" reescreveu os literais
/// deste ficheiro e partiu o padrao, gerando
/// `Illegal RegExp pattern ... Nothing to repeat` e derrubando todos os
/// modulos que leem dados do Firestore. Em ASCII isso nao volta a acontecer.
abstract final class Utf8MojibakeFix {
  Utf8MojibakeFix._();

  /// Marcadores de mojibake (UTF-8 lido como Latin-1):
  /// - A-til / A-circunflexo seguidos de um byte de continuacao \u0080-\u00bf.
  /// - \u00e2\u0080 + continuacao: aspas curvas e travessao.
  static final RegExp _hint = RegExp(
    '[\u00c3\u00c2][\u0080-\u00bf]|\u00e2\u0080[\u0080-\u00bf]',
  );

  /// Repara mojibake quando detectado; caso contrario devolve o original.
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
