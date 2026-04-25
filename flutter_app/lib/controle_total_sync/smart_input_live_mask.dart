import 'currency_formats.dart';

/// Máscara em tempo real para o campo «Lançamento expresso»: completa datas `d/m` ou `dd/mm` com o ano
/// corrente (saída sempre `dd/mm/aaaa`) e formata valores em centavos (3+ dígitos) no fim **ou** no
/// início da frase → `R$ …` (padrão do app).
///
/// Ditado «cem reais» / «100 reais»: tratados como **reais inteiros**, não centavos (evita R$ 1,00).
class SmartInputLiveMask {
  SmartInputLiveMask._();

  static const String _phStart = '\uE000';
  static const String _phEnd = '\uE001';

  /// Sufixo final `dd/mm` ou `dd/mm/ano` (ano incompleto) — não expandir o `dd/mm` curto outra vez
  /// (evita o ano a «voltar» ao apagar) quando há texto antes da data.
  static final RegExp _trailingCalendarSuffix = RegExp(
    r'(\d{1,2}/\d{1,2}(?:/\d*)?)\s*$',
    unicode: true,
  );

  /// Expande `d/m` ou `dd/mm` válido (não seguido de `/` ou dígito) para `dd/mm/aaaa` com [year].
  ///
  /// - Não expande `dd/mm` **colado** a letra (`supermer13/04`) — exige separador antes do dia.
  /// - Se a linha termina em `… texto dd/mm` ou `… dd/mm/20` em edição, **não** re-completa o ano
  ///   até o utilizador apagar também o mês/dia ou continuar a escrever o ano à mão.
  static String expandShortDates(String text, int year) {
    if (text.isEmpty) return text;
    final m = _trailingCalendarSuffix.firstMatch(text);
    if (m != null) {
      final head = text.substring(0, m.start);
      if (head.trim().isNotEmpty) {
        final tail = text.substring(m.start);
        return '${_expandShortDatesInner(head, year)}$tail';
      }
    }
    return _expandShortDatesInner(text, year);
  }

  static String _expandShortDatesInner(String text, int year) {
    if (text.isEmpty) return text;
    return text.replaceAllMapped(
      RegExp(
        r'(?<![0-9/])(?<!\p{L})(\d{1,2})/(\d{1,2})(?![0-9/])',
        unicode: true,
      ),
      (m) {
        final d = int.tryParse(m.group(1)!);
        final mo = int.tryParse(m.group(2)!);
        if (d == null || mo == null) return m.group(0)!;
        if (d < 1 || d > 31 || mo < 1 || mo > 12) return m.group(0)!;
        if (!_validCalendarDay(year, mo, d)) return m.group(0)!;
        final dd = d.toString().padLeft(2, '0');
        final mm = mo.toString().padLeft(2, '0');
        return '$dd/$mm/$year';
      },
    );
  }

  static bool _validCalendarDay(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1) return false;
    final lastDay = DateTime(y, m + 1, 0).day;
    return d <= lastDay;
  }

  /// Converte «cem reais», «mil reais», «vinte e cinco reais»… em dígitos antes da máscara monetária.
  /// Só substitui quando a palavra está imediatamente antes de `real`/`reais` (não altera «cem gramas»).
  static String expandSpokenReaisWords(String s) {
    if (s.isEmpty) return s;
    var t = s;

    const tensE = <String, int>{
      'vinte': 20,
      'trinta': 30,
      'quarenta': 40,
      'cinquenta': 50,
      'sessenta': 60,
      'setenta': 70,
      'oitenta': 80,
      'noventa': 90,
    };
    const unitsE = <String, int>{
      'um': 1,
      'uma': 1,
      'dois': 2,
      'duas': 2,
      'três': 3,
      'tres': 3,
      'quatro': 4,
      'cinco': 5,
      'seis': 6,
      'sete': 7,
      'oito': 8,
      'nove': 9,
      'dez': 10,
      'onze': 11,
      'doze': 12,
      'treze': 13,
      'catorze': 14,
      'quatorze': 14,
      'quinze': 15,
      'dezesseis': 16,
      'dezassete': 17,
      'dezesete': 17,
      'dezoito': 18,
      'dezenove': 19,
    };

    t = t.replaceAllMapped(
      RegExp(
        r'\b(vinte|trinta|quarenta|cinquenta|sessenta|setenta|oitenta|noventa)\s+e\s+(um|uma|dois|duas|três|tres|quatro|cinco|seis|sete|oito|nove|dez|onze|doze|treze|catorze|quatorze|quinze|dezesseis|dezassete|dezesete|dezoito|dezenove)\s+reais?\b',
        caseSensitive: false,
      ),
      (m) {
        final ti = tensE[m.group(1)!.toLowerCase()];
        final ui = unitsE[m.group(2)!.toLowerCase()];
        if (ti == null || ui == null) return m.group(0)!;
        return '${ti + ui} reais';
      },
    );

    const milDez = <String, int>{
      'dez': 10,
      'vinte': 20,
      'trinta': 30,
      'quarenta': 40,
      'cinquenta': 50,
      'sessenta': 60,
      'setenta': 70,
      'oitenta': 80,
      'noventa': 90,
    };
    t = t.replaceAllMapped(
      RegExp(r'\b(dez|vinte|trinta|quarenta|cinquenta|sessenta|setenta|oitenta|noventa)\s+mil\s+reais?\b', caseSensitive: false),
      (m) {
        final v = milDez[m.group(1)!.toLowerCase()];
        if (v == null) return m.group(0)!;
        return '${v * 1000} reais';
      },
    );

    t = t.replaceAllMapped(
      RegExp(r'\b(dois|duas|três|tres|quatro|cinco|seis|sete|oito|nove)\s+mil\s+reais?\b', caseSensitive: false),
      (m) {
        const m2 = {'dois': 2, 'duas': 2, 'três': 3, 'tres': 3, 'quatro': 4, 'cinco': 5, 'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9};
        final v = m2[m.group(1)!.toLowerCase()];
        if (v == null) return m.group(0)!;
        return '${v * 1000} reais';
      },
    );

    t = t.replaceAllMapped(RegExp(r'\b(um|uma)\s+mil\s+reais?\b', caseSensitive: false), (_) => '1000 reais');

    const hundreds = <String, int>{
      'duzentos': 200,
      'duzentas': 200,
      'trezentos': 300,
      'trezentas': 300,
      'quatrocentos': 400,
      'quatrocentas': 400,
      'quinhentos': 500,
      'quinhentas': 500,
      'seiscentos': 600,
      'seiscentas': 600,
      'setecentos': 700,
      'setecentas': 700,
      'oitocentos': 800,
      'oitocentas': 800,
      'novecentos': 900,
      'novecentas': 900,
    };
    for (final e in hundreds.entries) {
      t = t.replaceAllMapped(
        RegExp('\\b${e.key}\\s+reais?\\b', caseSensitive: false),
        (_) => '${e.value} reais',
      );
    }

    t = t.replaceAllMapped(RegExp(r'\b(cem)\s+reais?\b', caseSensitive: false), (_) => '100 reais');
    t = t.replaceAllMapped(RegExp(r'\b(mil)\s+reais?\b', caseSensitive: false), (_) => '1000 reais');

    const tensAlone = <String, int>{
      'vinte': 20,
      'trinta': 30,
      'quarenta': 40,
      'cinquenta': 50,
      'sessenta': 60,
      'setenta': 70,
      'oitenta': 80,
      'noventa': 90,
    };
    for (final e in tensAlone.entries) {
      t = t.replaceAllMapped(RegExp('\\b${e.key}\\s+reais?\\b', caseSensitive: false), (_) => '${e.value} reais');
    }

    const dezenas = <String, int>{
      'dez': 10,
      'onze': 11,
      'doze': 12,
      'treze': 13,
      'catorze': 14,
      'quatorze': 14,
      'quinze': 15,
      'dezesseis': 16,
      'dezassete': 17,
      'dezesete': 17,
      'dezoito': 18,
      'dezenove': 19,
    };
    for (final e in dezenas.entries) {
      t = t.replaceAllMapped(RegExp('\\b${e.key}\\s+reais?\\b', caseSensitive: false), (_) => '${e.value} reais');
    }

    const unitsAlone = <String, int>{
      'um': 1,
      'uma': 1,
      'dois': 2,
      'duas': 2,
      'três': 3,
      'tres': 3,
      'quatro': 4,
      'cinco': 5,
      'seis': 6,
      'sete': 7,
      'oito': 8,
      'nove': 9,
    };
    for (final e in unitsAlone.entries) {
      t = t.replaceAllMapped(RegExp('\\b${e.key}\\s+reais?\\b', caseSensitive: false), (_) => '${e.value} reais');
    }

    return t;
  }

  /// `… 100 reais` no fim do fragmento → valor em reais inteiros (não centavos).
  static String _maskWholeReaisTrailing(String s) {
    if (s.isEmpty) return s;
    final m = RegExp(r'^(.+?)\s+(\d{1,})\s+reais?\s*$', caseSensitive: false, unicode: true).firstMatch(s.trim());
    if (m == null) return s;
    final prefix = m.group(1)!.trimRight();
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(prefix)) return s;
    final n = int.tryParse(m.group(2)!);
    if (n == null) return s;
    final brl = CurrencyFormats.formatBRL(n.toDouble());
    return '$prefix $brl';
  }

  /// `100 reais` ou `R$ 100 reais` ou `100 reais mercado` no início → reais inteiros.
  static String _maskWholeReaisLeading(String s) {
    if (s.isEmpty) return s;
    var head = s.trim();
    head = head.replaceFirst(RegExp(r'^(R\$\s*)+', caseSensitive: false), '');
    final m = RegExp(r'^(\d{1,})\s+reais?\b\s*(.*)$', caseSensitive: false, unicode: true).firstMatch(head);
    if (m == null) return s;
    final n = int.tryParse(m.group(1)!);
    if (n == null) return s;
    final tail = (m.group(2) ?? '').trim();
    final brl = CurrencyFormats.formatBRL(n.toDouble());
    if (tail.isEmpty) return brl;
    return '$brl $tail';
  }

  /// Junta `1, 000` / `1 ,000` em padrão de milhares; cola `12, 34` em `12,34` (vírgula decimal).
  static String _normalizeLooseCommaAmounts(String line) {
    if (line.isEmpty) return line;
    var t = line;
    t = t.replaceAllMapped(
      RegExp(r'(\d{1,3}(?:\.\d{3})*),\s+(\d{3})(?![\d,])', unicode: true),
      (m) => '${m[1]}.${m[2]}',
    );
    t = t.replaceAllMapped(
      RegExp(r'(\d+),\s+(\d{2})(?![\d])', unicode: true),
      (m) => '${m[1]},${m[2]}',
    );
    t = t.replaceAll(RegExp(r'R\$(?:\s*R\$)+', caseSensitive: false), r'R$');
    t = t.replaceAll(RegExp(r'R\$\s+R\$', caseSensitive: false), r'R$ ');
    return t;
  }

  /// Formata, em cada fragmento separado por vírgula (respeitando valores `1.234,56`), valores em
  /// centavos (3+ dígitos): `… texto 25000` ou `25000 mercado` (com letras na outra parte).
  static String applyMoneyMaskToLine(String line) {
    if (line.isEmpty) return line;
    final lineNorm = _normalizeLooseCommaAmounts(line);
    final amounts = <String>[];
    var masked = lineNorm.replaceAllMapped(
      RegExp(r'\d{1,3}(?:\.\d{3})*,\d{2}\b'),
      (m) {
        amounts.add(m.group(0)!);
        return '$_phStart${amounts.length - 1}$_phEnd';
      },
    );
    final parts = masked.split(RegExp(r'\s*,\s*'));
    final out = <String>[];
    for (final rawPart in parts) {
      var seg = rawPart;
      for (var i = 0; i < amounts.length; i++) {
        seg = seg.replaceAll('$_phStart$i$_phEnd', amounts[i]);
      }
      final spoken = expandSpokenReaisWords(seg.trimLeft());
      out.add(_maskSegmentMoney(spoken));
    }
    return out.join(', ');
  }

  /// Centavos: sufixo `descrição 25000` e prefixo `25000 descrição` (dois passes), depois de `… reais`.
  static String _maskSegmentMoney(String s) {
    var t = _maskWholeReaisTrailing(s);
    t = _maskWholeReaisLeading(t);
    t = _maskTrailingDigitAmount(t);
    t = _maskLeadingDigitAmount(t);
    return t;
  }

  static String _maskTrailingDigitAmount(String s) {
    if (s.isEmpty) return s;
    final mMil = RegExp(
      r'^(.+?)\s+(\d{1,3}(?:\.\d{3})+)(?:,00)?\s*$',
      unicode: true,
    ).firstMatch(s);
    if (mMil != null) {
      final desc = mMil.group(1)!;
      if (RegExp(r'\p{L}', unicode: true).hasMatch(desc)) {
        final reais = int.tryParse(mMil.group(2)!.replaceAll('.', ''));
        if (reais != null && reais > 0 && reais <= 999999999) {
          return '$desc ${CurrencyFormats.formatBRL(reais.toDouble())}';
        }
      }
    }
    final m = RegExp(r'^(.+)\s+(\d{3,})$', unicode: true).firstMatch(s);
    if (m == null) return s;
    final desc = m.group(1)!;
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(desc)) return s;
    final digits = m.group(2)!;
    if (digits.length > 14) return s;
    final cents = int.tryParse(digits);
    if (cents == null) return s;
    final value = cents / 100.0;
    final brl = CurrencyFormats.formatBRL(value);
    return '$desc $brl';
  }

  static String _maskLeadingDigitAmount(String s) {
    if (s.isEmpty) return s;
    var head = s.trim();
    head = head.replaceFirst(RegExp(r'^(R\$\s*)+', caseSensitive: false), '');
    final m = RegExp(r'^(\d{3,})\s+(.+)$', unicode: true).firstMatch(head);
    if (m == null) return s;
    final digits = m.group(1)!;
    var rest = m.group(2)!;
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(rest)) return s;
    if (digits.length > 14) return s;
    if (RegExp(r'^R\$\s', caseSensitive: false).hasMatch(rest)) return s;
    final cents = int.tryParse(digits);
    if (cents == null) return s;
    final brl = CurrencyFormats.formatBRL(cents / 100.0);
    return '$brl $rest';
  }

  /// Aplica [expandShortDates] e máscara monetária a um bloco (uma linha ou parágrafo);
  /// não divide por `|` (use [apply]).
  static String applyToFragment(String text, int year) {
    if (text.isEmpty) return text;
    var t = expandShortDates(text, year);
    final lines = t.split('\n');
    return lines.map(applyMoneyMaskToLine).join('\n');
  }

  /// Máscara de data (dd/mm/aaaa) + valores R$; vários lançamentos no mesmo campo: separador `|`.
  static String apply(String text, int year) {
    if (text.isEmpty) return text;
    if (!text.contains('|')) {
      return applyToFragment(text, year);
    }
    final parts = text.split('|');
    final out = <String>[];
    for (final p in parts) {
      final seg = p.trim();
      if (seg.isEmpty) continue;
      out.add(applyToFragment(seg, year));
    }
    if (out.isEmpty) return text;
    return out.join(' | ');
  }
}
