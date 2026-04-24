import 'package:gestao_yahweh/utils/finance_smart_input_text.dart';

/// Sugere categoria a partir de palavras comuns (voz ou colagem). Só devolve rótulo
/// que **existe** em [validCategorias] (nome canónico do Firestore/tenant).
class FinanceSmartInputCategoryHints {
  FinanceSmartInputCategoryHints._();

  /// (palavras-chave) → categoria padrão do módulo financeiro.
  static const _rules = <(List<String>, String)>[
    (
      ['sabesp', 'cedae', 'copasa', 'caesb', 'corsan', 'agua e es', 'esgoto', 'saneam'],
      'Água',
    ),
    (
      ['luz', 'enel', 'cemig', 'cpfl', 'celesc', 'energi', 'elétric', 'eletric', 'kwh', 'k w h'],
      'Energia Elétrica',
    ),
    (
      ['internet', 'fibra', 'claro', 'net virt', 'o i ', 'banda larga', 'roteador'],
      'Internet',
    ),
    (
      ['míd', 'mid', 'tela de', 'comunicaudi', 'palco', 'sistema de som', 'comunica'],
      'Investimentos em Mídia',
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
        'táx',
        'onibus',
        'lotacao',
        'lotação',
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
        'açougue',
        'açougu',
        'restaur',
        'lanchon',
        'lanche',
        'pão d',
        'pao d',
        'mercad',
        'feira',
        'hortifrut',
        'pastelar',
      ],
      'Alimentação',
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
      'Material de Escritório',
    ),
    (
      ['reparo', 'manutenc', 'encanad', 'pedreir', 'civil '],
      'Manutenção',
    ),
    (
      ['oferta miss', 'missao d', 'missa d', 'sustento miss', 'casa de miss'],
      'Oferta Missionária',
    ),
    (['feste', 'aniversa da igreja', 'culto de gala', 'decora'], 'Eventos'),
    (
      ['hono obreir', 'pagamento a obreir', 'cachê obreir', 'caché obreir', 'caché mis'],
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
    MapEntry('á', 'a'),
    MapEntry('à', 'a'),
    MapEntry('ã', 'a'),
    MapEntry('â', 'a'),
    MapEntry('é', 'e'),
    MapEntry('ê', 'e'),
    MapEntry('í', 'i'),
    MapEntry('ó', 'o'),
    MapEntry('ô', 'o'),
    MapEntry('õ', 'o'),
    MapEntry('ú', 'u'),
    MapEntry('ç', 'c'),
  ];
}
