/// Parser leve de extratos OFX/QFX (1.x SGML e 2.x XML) — Dart puro, sem rede.
class OfxStatementTransaction {
  const OfxStatementTransaction({
    required this.fitId,
    required this.amount,
    required this.date,
    required this.memo,
    required this.trnType,
  });

  final String fitId;
  /// Valor com sinal: positivo = crédito, negativo = débito.
  final double amount;
  final DateTime date;
  final String memo;
  final String trnType;

  bool get isCredit => amount > 0.009;
  double get absAmount => amount.abs();
}

class OfxParseResult {
  const OfxParseResult({
    required this.transactions,
    this.accountId,
    this.currency,
  });

  final List<OfxStatementTransaction> transactions;
  final String? accountId;
  final String? currency;

  bool get isEmpty => transactions.isEmpty;
}

abstract final class FinanceOfxParser {
  FinanceOfxParser._();

  static OfxParseResult parse(String raw) {
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final txs = <OfxStatementTransaction>[];
    String? accountId;
    String? currency;

    accountId = _tagValue(text, 'ACCTID');
    currency = _tagValue(text, 'CURDEF');

    final blocks = _extractStmtTrnBlocks(text);
    for (final block in blocks) {
      final fitId = _tagValue(block, 'FITID') ?? '';
      final amtRaw = _tagValue(block, 'TRNAMT');
      final amount = _parseAmount(amtRaw);
      if (amount == null || fitId.isEmpty) continue;
      final dt = _parseOfxDate(_tagValue(block, 'DTPOSTED') ?? '') ??
          _parseOfxDate(_tagValue(block, 'DTUSER') ?? '');
      if (dt == null) continue;
      final memo = (_tagValue(block, 'MEMO') ??
              _tagValue(block, 'NAME') ??
              _tagValue(block, 'PAYEE') ??
              '')
          .trim();
      txs.add(
        OfxStatementTransaction(
          fitId: fitId,
          amount: amount,
          date: dt,
          memo: memo,
          trnType: (_tagValue(block, 'TRNTYPE') ?? '').toUpperCase(),
        ),
      );
    }

    txs.sort((a, b) => b.date.compareTo(a.date));
    return OfxParseResult(
      transactions: txs,
      accountId: accountId,
      currency: currency,
    );
  }

  static List<String> _extractStmtTrnBlocks(String text) {
    final out = <String>[];
    final re = RegExp(
      r'<STMTTRN>(.*?)</STMTTRN>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final m in re.allMatches(text)) {
      out.add(m.group(1) ?? '');
    }
    if (out.isNotEmpty) return out;

    // OFX 1.x SGML: tags sem fechamento explícito.
    final lines = text.split('\n');
    var buf = <String>[];
    var inBlock = false;
    for (final line in lines) {
      final t = line.trim();
      if (t.toUpperCase().startsWith('<STMTTRN>')) {
        inBlock = true;
        buf = [t];
        continue;
      }
      if (inBlock) {
        buf.add(t);
        if (t.toUpperCase().startsWith('</STMTTRN>') ||
            t.toUpperCase() == '</STMTTRN>') {
          out.add(buf.join('\n'));
          inBlock = false;
          buf = [];
        }
      }
    }
    if (inBlock && buf.isNotEmpty) out.add(buf.join('\n'));
    return out;
  }

  static String? _tagValue(String block, String tag) {
    final xml = RegExp(
      '<$tag>([^<]*)</$tag>',
      caseSensitive: false,
    ).firstMatch(block);
    if (xml != null) return xml.group(1)?.trim();

    final sgml = RegExp(
      '<$tag>([^\\n<]+)',
      caseSensitive: false,
    ).firstMatch(block);
    return sgml?.group(1)?.trim();
  }

  static double? _parseAmount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final n = raw.trim().replaceAll(',', '.');
    return double.tryParse(n);
  }

  static DateTime? _parseOfxDate(String raw) {
    if (raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8) return null;
    final y = int.tryParse(digits.substring(0, 4));
    final mo = int.tryParse(digits.substring(4, 6));
    final d = int.tryParse(digits.substring(6, 8));
    if (y == null || mo == null || d == null) return null;
    var h = 0, mi = 0, s = 0;
    if (digits.length >= 14) {
      h = int.tryParse(digits.substring(8, 10)) ?? 0;
      mi = int.tryParse(digits.substring(10, 12)) ?? 0;
      s = int.tryParse(digits.substring(12, 14)) ?? 0;
    }
    return DateTime(y, mo, d, h, mi, s);
  }
}
