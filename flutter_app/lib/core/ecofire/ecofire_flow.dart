import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Arquitetura **EcoFire** — Auth → Firestore → Storage → Tela (upload directo).
///
/// Mantém [directStorageUpload] (rápido, sem filas fantasmas legadas).
/// Filas de retry, recovery e FirestoreWebGuard **activos** — não bloqueiam código novo.
abstract final class EcoFireFlow {
  EcoFireFlow._();

  /// Upload directo Storage + bootstrap EcoFire (produção).
  static const bool enabled = true;

  /// FirestoreWebGuard activo em **todas** as plataformas (não saltar recovery na web).
  static bool get passThroughFirestore => false;

  /// Recovery automático ao retomar app / rede.
  static bool get disableAutomaticRecovery => false;

  /// Filas disco/outbox activas como rede de segurança (direct upload continua primário).
  static bool get disableUploadQueues => false;

  static bool get disableRepairMyChurchBinding => false;

  /// Bootstrap completo (queues + recovery) — não usar só minimal.
  static bool get disableComplexBootstrap => false;

  static bool get directStorageUpload => enabled;

  static void log(String msg) {
    if (kDebugMode) debugPrint('EcoFireFlow: $msg');
  }
}
