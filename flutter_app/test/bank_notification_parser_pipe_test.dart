import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/controle_total_sync/bank_notification_parser.dart';

void main() {
  test('parseManyForBatch: vários segmentos separados por |', () {
    const t = '50,00 no posto shell | 12,50 padaria | 30,00 luz enel';
    final rows = BankNotificationParser.parseManyForBatch(t);
    expect(rows.length, 3);
    expect(rows.every((r) => r.hasMinimumForConfirmation), isTrue);
  });

  test('parcelas: 10x de 250,00 gera 10 linhas, total 2.500', () {
    final rows = BankNotificationParser.parseManyForBatch('10x de 250,00 compra geladeira');
    expect(rows.length, 10);
    expect(
      rows
          .map((e) => e.valor)
          .fold<double>(0, (a, b) => a + (b ?? 0)),
      closeTo(2500, 0.01),
    );
    expect(
      (rows.first.descricao ?? '').toLowerCase(),
      contains('geladeira'),
    );
    expect(rows.first.descricao, contains('(1/10)'));
  });

  test('parcelas: 1.500,00 em 6x (total parcelado, 6 meses)', () {
    final rows = BankNotificationParser.parseManyForBatch('1.500,00 em 6x compra geladeira');
    expect(rows.length, 6);
    expect(
      rows.map((e) => e.valor).fold<double>(0, (a, b) => a + (b ?? 0)),
      closeTo(1500, 0.1),
    );
    expect((rows[2].descricao ?? '').toLowerCase(), contains('(3/6)'));
  });

  test('parcelas: 6 parcelas de 200,00 material', () {
    final rows = BankNotificationParser.parseManyForBatch('6 parcelas de 200,00 material creche');
    expect(rows.length, 6);
    expect(
      rows.map((e) => e.valor).fold<double>(0, (a, b) => a + (b ?? 0)),
      closeTo(1200, 0.1),
    );
  });

  test('texto e pipe: parcelado + outro', () {
    const t = '10x de 250,00 cadeiras | 45,00 canetas';
    final rows = BankNotificationParser.parseManyForBatch(t);
    expect(rows.length, 11);
  });

  test('Bradesco cartões: várias mensagens coladas geram vários lançamentos', () {
    const t = r'''
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:21. VALOR DE R$ 41,98 MR FARMA                 ANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:15. VALOR DE R$ 18,00 CHEIRO VERDE SACOLAO     ANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:11. VALOR DE R$ 50,99 FAZBEMDROGARIAE          ANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:07. VALOR DE R$ 83,20 CASA DE CARNES CANADA BEEANAPOLIS.
BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 08:21. VALOR DE R$ 36,97 SUPERMERCADOS ATENDE MA  ANAPOLIS.
''';
    final rows = BankNotificationParser.parseManyForBatch(t);
    expect(rows.length, 5);
    expect(rows.every((r) => r.hasMinimumForConfirmation), isTrue);
    expect(rows.every((r) => r.type == 'expense'), isTrue);
    expect(
      rows.map((r) => r.valor).fold<double>(0, (a, b) => a + (b ?? 0)),
      closeTo(231.14, 0.01),
    );
    expect((rows.first.descricao ?? '').toUpperCase(), contains('MR FARMA'));
  });

  test('Bradesco cartões: mensagem única gera 1 lançamento', () {
    const t = r'BRADESCO CARTOES: COMPRA APROVADA NO CARTAO FINAL 2524 EM 25/04/2026 10:21. VALOR DE R$ 41,98 MR FARMA                 ANAPOLIS.';
    final rows = BankNotificationParser.parseManyForBatch(t);
    expect(rows.length, 1);
    final r = rows.first;
    expect(r.hasMinimumForConfirmation, isTrue);
    expect(r.type, 'expense');
    expect(r.valor, closeTo(41.98, 0.001));
    expect((r.descricao ?? '').toUpperCase(), contains('MR FARMA'));
    expect(r.data, isNotNull);
    expect(r.data!.year, 2026);
    expect(r.data!.month, 4);
    expect(r.data!.day, 25);
  });
}
