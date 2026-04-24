import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/controle_total_sync/bank_notification_parser.dart';

void main() {
  test('parseManyForBatch: vários segmentos separados por |', () {
    const t = '50,00 no posto shell | 12,50 padaria | 30,00 luz enel';
    final rows = BankNotificationParser.parseManyForBatch(t);
    expect(rows.length, 3);
    expect(rows.every((r) => r.hasMinimumForConfirmation), isTrue);
  });
}
