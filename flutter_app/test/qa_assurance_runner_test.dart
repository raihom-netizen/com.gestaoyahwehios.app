import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/core/qa/multiplatform_qa_matrix.dart';
import 'package:gestao_yahweh/core/qa/qa_assurance_runner.dart';
import 'package:gestao_yahweh/core/system_health/session_performance_metrics.dart';

void main() {
  test('Modo QA define exactamente 28 testes', () {
    expect(QaAssuranceRunner.testNames.length, 28);
    expect(QaAssuranceRunner.testNames.first, 'Login Google');
    expect(QaAssuranceRunner.testNames.last, 'Painel Master');
  });

  test('Matriz multiplataforma cobre modulos unificados', () {
    expect(MultiplatformQaMatrix.unifiedModules.length, greaterThanOrEqualTo(10));
    expect(MultiplatformQaMatrix.releasePlatforms.length, 3);
    expect(MultiplatformQaMatrix.releaseBlockedIfAnyPlatformFails, isTrue);
    for (final m in MultiplatformQaMatrix.unifiedModules) {
      expect(m.sameExperienceOnAndroid, isTrue);
      expect(m.sameExperienceOnIos, isTrue);
      expect(m.sameExperienceOnWeb, isTrue);
    }
  });

  test('Metas de performance incluem dashboard e upload', () {
    final metrics = SessionPerformanceMetrics.snapshotWithPlaceholders();
    expect(metrics.length, greaterThanOrEqualTo(8));
    expect(
      metrics.any((m) => m.label.contains('Dashboard')),
      isTrue,
    );
    expect(
      metrics.any((m) => m.label.contains('Upload')),
      isTrue,
    );
  });
}
