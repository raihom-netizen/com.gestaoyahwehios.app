import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Arquitetura **EcoFire** — Auth → Firestore → Storage → Tela.
///
/// Substitui camadas pesadas (FirestoreWebGuard recovery, filas automáticas,
/// bootstrap recursivo, repairMyChurchBinding) por fluxo directo igual Web/Android/iOS.
abstract final class EcoFireFlow {
  EcoFireFlow._();

  /// Activar padrão EcoFire em todo o app (recomendado produção).
  static const bool enabled = true;

  static bool get passThroughFirestore => enabled;

  static bool get disableAutomaticRecovery => enabled;

  static bool get disableUploadQueues => enabled;

  static bool get disableRepairMyChurchBinding => enabled;

  static bool get disableComplexBootstrap => enabled;

  static bool get directStorageUpload => enabled;

  static void log(String msg) {
    if (kDebugMode) debugPrint('EcoFireFlow: $msg');
  }
}
