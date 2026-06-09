import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';

void main() {
  group('ChurchBrandService', () {
    test('logoPathFromData prioriza logoPath do Firestore', () {
      final path = ChurchBrandService.logoPathFromData(
        {
          'logoPath': 'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png',
          'logo_url': 'https://example.com/legado.png',
        },
        churchId: 'igreja_batista_renovada',
      );
      expect(path, 'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png');
    });

    test('logoPathFromData usa path canónico quando doc sem logoPath', () {
      final path = ChurchBrandService.logoPathFromData(
        const {},
        churchId: 'igreja_batista_renovada',
      );
      expect(
        path,
        'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png',
      );
    });

    test('logoPathFirestorePatch grava logoPath e remove URLs legadas', () {
      final patch = ChurchBrandService.logoPathFirestorePatch(
        'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png',
      );
      expect(
        patch['logoPath'],
        'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png',
      );
      expect(patch['updatedAt'], isA<FieldValue>());
      for (final k in ChurchBrandService.legacyLogoUrlFirestoreKeys) {
        expect(patch[k], isA<FieldValue>());
      }
    });
  });
}
