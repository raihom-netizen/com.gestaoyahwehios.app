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
}
