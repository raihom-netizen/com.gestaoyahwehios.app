import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';

void main() {
  group('ChurchBrandService', () {
    test('logoPathFromData prioriza logoStoragePath do Firestore', () {
      final path = ChurchBrandService.logoPathFromData(
        {
          'logoPath':
              'https://firebasestorage.googleapis.com/v0/b/x/o/igrejas%2Figreja_batista_renovada%2Fconfiguracoes%2Flogo_igreja.png?alt=media&token=abc',
          'logoStoragePath':
              'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png',
        },
        churchId: 'igreja_batista_renovada',
      );
      expect(path, 'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png');
    });

    test('logoPathFromData extrai path de logoPath legado (só path)', () {
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

    test('logoPathFirestorePatch grava URL https em logoPath e path auxiliar', () {
      const url =
          'https://firebasestorage.googleapis.com/v0/b/gestaoyahweh-21e23.firebasestorage.app/o/igrejas%2Figreja_batista_renovada%2Fconfiguracoes%2Flogo_igreja.png?alt=media&token=abc';
      const storagePath =
          'igrejas/igreja_batista_renovada/configuracoes/logo_igreja.png';
      final patch = ChurchBrandService.logoPathFirestorePatch(
        storagePath: storagePath,
        downloadUrl: url,
      );
      expect(patch['logoPath'], url);
      expect(patch['logoUrl'], url);
      expect(patch['logoStoragePath'], storagePath);
      expect(patch['updatedAt'], isA<FieldValue>());
      for (final k in ChurchBrandService.legacyLogoUrlFirestoreKeys) {
        if (k == 'logoUrl') continue;
        expect(patch[k], isA<FieldValue>());
      }
    });
  });
}
