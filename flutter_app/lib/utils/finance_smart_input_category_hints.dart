import 'package:gestao_yahweh/utils/finance_smart_input_text.dart';

/// Sugere categoria a partir de palavras comuns (voz ou colagem). S├│ devolve r├│tulo
/// que **existe** em [validCategorias] (nome can├│nico do Firestore/tenant).
class FinanceSmartInputCategoryHints {
  FinanceSmartInputCategoryHints._();

  /// (palavras-chave) ÔåÆ categoria padr├úo do m├│dulo financeiro.
  static const _rules = <(List<String>, String)>[
    (
      ['sabesp', 'cedae', 'copasa', 'caesb', 'corsan', 'agua e es', 'esgoto', 'saneam'],
      '├ügua',
    ),
    (
      ['luz', 'enel', 'cemig', 'cpfl', 'celesc', 'energi', 'el├®tric', 'eletric', 'kwh', 'k w h'],
      'Energia El├®trica',
    ),
    (
      ['internet', 'fibra', 'claro', 'net virt', 'o i ', 'banda larga', 'roteador'],
      'Internet',
    ),
    (
      ['m├¡d', 'mid', 'tela de', 'comunicaudi', 'palco', 'sistema de som', 'comunica'],
      'Investimentos em M├¡dia',
    ),
    (
      [
        'gasolina',
        'etanol',
        'posto',
        'shell',
        'ipiranga',
        'uber',
        'taxi',
        't├íx',
        'onibus',
        'lotacao',
        'lota├º├úo',
        'estaciona',
        '99 pop',
        ' pedag',
        'r 99,',
        'r99,',
        'r 9 9,',
        'lota',
      ],
      'Transporte',
    ),
    (
      [
        'supermerc',
        'atacad',
        'alimenta',
        'ifood',
        'rappi',
        'padar',
        'a├ºougue',
        'a├ºougu',
        'restaur',
        'lanchon',
        'lanche',
        'p├úo d',
        'pao d',
        'mercad',
        'feira',
        'hortifrut',
        'pastelar',
      ],
      'Alimenta├º├úo',
    ),
    (
      ['darf', 'dctf', 'inss', 'irpf', 'receit federal', 'prefeitur', ' guia de', 'iss '],
      'Impostos',
    ),
    (
      ['deterg', 'limpeza geral', 'higie', 'sabao', 'mop ', 'luvas desc'],
      'Material de Limpeza',
    ),
    (
      ['papel a4', 'a4 75', 'grampe', 'pasta susp', 'toner', 'cartucho'],
      'Material de Escrit├│rio',
    ),
    (
      ['reparo', 'manutenc', 'encanad', 'pedreir', 'civil '],
      'Manuten├º├úo',
    ),
    (
      ['oferta miss', 'missao d', 'missa d', 'sustento miss', 'casa de miss'],
      'Oferta Mission├íria',
    ),
    (['feste', 'aniversa da igreja', 'culto de gala', 'decora'], 'Eventos'),
    (
      ['hono obreir', 'pagamento a obreir', 'cach├¬ obreir', 'cach├® obreir', 'cach├® mis'],
      'Pagamento de Obreiros',
    ),
    (['alugue', 'aluguel', 'condomini', 'loteamento', 'sala terceir', 'sala terci'], 'Outros'),
  ];

  static String? suggestDespesaCategoria(
    String descricao, {
    required List<String> validCategorias,
  }) {
    if (descricao.trim().isEmpty || validCategorias.isEmpty) return null;
    final key = _fold(FinanceSmartInputText.sanitize(descricao));
    if (key.isEmpty) return null;

    String? canon(String alvo) {
      for (final c in validCategorias) {
        if (c.toLowerCase() == alvo.toLowerCase()) return c;
      }
      return null;
    }

    for (final r in _rules) {
      for (final k in r.$1) {
        if (k.length < 3) continue;
        if (key.contains(_fold(k))) {
          final c = canon(r.$2);
          if (c != null) return c;
          break;
        }
      }
    }
    return null;
  }

  static String _fold(String s) {
    var t = s.toLowerCase();
    for (final e in _diac) {
      t = t.replaceAll(e.key, e.value);
    }
    return t;
  }

  static const _diac = <MapEntry<String, String>>[
    MapEntry('├í', 'a'),
    MapEntry('├á', 'a'),
    MapEntry('├ú', 'a'),
    MapEntry('├ó', 'a'),
    MapEntry('├®', 'e'),
    MapEntry('├¬', 'e'),
    MapEntry('├¡', 'i'),
    MapEntry('├│', 'o'),
    MapEntry('├┤', 'o'),
    MapEntry('├Á', 'o'),
    MapEntry('├║', 'u'),
    MapEntry('├º', 'c'),
  ];
}
