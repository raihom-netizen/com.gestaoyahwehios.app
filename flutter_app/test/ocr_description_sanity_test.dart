import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/utils/ocr_description_sanity.dart';

void main() {
  test('looksLikeOcrNoise: curto demais', () {
    expect(OcrDescriptionSanity.looksLikeOcrNoise('A'), isTrue);
    expect(OcrDescriptionSanity.looksLikeOcrNoise(''), isTrue);
  });

  test('sanitize: BIDI mínimo de letras → placeholder', () {
    const garbled = '‏\u202eR\$1';
    expect(
      OcrDescriptionSanity.sanitize(garbled),
      'Lançamento (revisar descrição)',
    );
  });

  test('sanitize: texto legível passa', () {
    const ok = 'Supermercado Pão de Açúcar';
    expect(OcrDescriptionSanity.sanitize(ok), ok);
  });

  test('sanitize: muitos dígitos vs letras vira lixo', () {
    const noisy = '1234 56 78 90 12 34 56 78 90 12';
    expect(
      OcrDescriptionSanity.sanitize(noisy),
      'Lançamento (revisar descrição)',
    );
  });
}
