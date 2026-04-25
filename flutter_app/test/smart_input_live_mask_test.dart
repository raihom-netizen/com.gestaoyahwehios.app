import 'package:gestao_yahweh/controle_total_sync/smart_input_live_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmartInputLiveMask', () {
    test('completa dd/mm com ano quando válido', () {
      expect(
        SmartInputLiveMask.expandShortDates('compra 12/04 no mercado', 2026),
        'compra 12/04/2026 no mercado',
      );
      expect(
        SmartInputLiveMask.expandShortDates('12/04', 2026),
        '12/04/2026',
      );
    });

    test('completa d/m com um dígito e normaliza para dd/mm/aaaa', () {
      expect(SmartInputLiveMask.expandShortDates('compra 3/4 no mercado', 2026), 'compra 03/04/2026 no mercado');
      expect(SmartInputLiveMask.expandShortDates('12/4/2026 x', 2026), '12/4/2026 x');
      expect(SmartInputLiveMask.expandShortDates('7/5 mercado', 2026), '07/05/2026 mercado');
    });

    test('não altera data já com ano nem data parcial', () {
      expect(SmartInputLiveMask.expandShortDates('12/04/2025 x', 2026), '12/04/2025 x');
      expect(SmartInputLiveMask.expandShortDates('12/040', 2026), '12/040');
      expect(SmartInputLiveMask.expandShortDates('31/02', 2026), '31/02');
    });

    test('formata sufixo numérico como centavos quando há descrição com letra', () {
      final s = SmartInputLiveMask.apply('supermercado 25000', 2026);
      expect(s, contains('R\$'));
      expect(s, contains('250,00'));
    });

    test('linha composta com valor BR existente e novo bloco', () {
      final s = SmartInputLiveMask.apply('posto de gasolina 87,55 , supermercado 250000', 2026);
      expect(s, contains('87,55'));
      expect(s, contains('2.500,00'));
    });

    test('formata valor no início da frase como centavos', () {
      final s = SmartInputLiveMask.apply('100 mercado', 2026);
      expect(s, contains('R\$'));
      expect(s, contains('mercado'));
      expect(s, contains('1,00'));
    });

    test('formata prefixo e sufixo na mesma parte', () {
      final s = SmartInputLiveMask.apply('100 mercado 25000', 2026);
      expect(s, contains('mercado'));
      expect(s, contains('250,00'));
      expect(s, contains('1,00'));
    });

    test('múltiplos lançamentos com |: máscara em cada segmento', () {
      final s = SmartInputLiveMask.apply(
        '5/4 posto 5000 | 10/3 pad 8000',
        2026,
      );
      expect(s, contains(' | '));
      expect(s, contains('R\$'));
    });

    test('100 reais (com ou sem R\$ à frente) → 100,00 reais', () {
      var s = SmartInputLiveMask.apply('100 reais luz', 2026);
      expect(s, contains('100,00'));
      s = SmartInputLiveMask.apply(r'R$ 100 reais luz', 2026);
      expect(s, contains('100,00'));
    });

    test('teclado 8750 = 87,50 quando há descrição', () {
      final s = SmartInputLiveMask.apply('luz 8750', 2026);
      expect(s, contains('87,50'));
    });

    test('1, 000 com espaço vira 1.000,00 reais (mil)', () {
      final s = SmartInputLiveMask.apply('ENERGIA 1, 000', 2026);
      expect(s, contains('1.000,00'));
    });
  });
}
