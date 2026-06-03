import 'package:gestao_yahweh/core/resilience/degraded_services.dart';
import 'package:gestao_yahweh/core/resilience/service_degradation_registry.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';

/// Modo emergência — Firebase indisponível ou offline; trabalho local + sync depois.
abstract final class EmergencyModeService {
  EmergencyModeService._();

  static bool _firebaseUnavailable = false;

  static bool get isActive =>
      !AppConnectivityService.instance.isOnline ||
      _firebaseUnavailable ||
      !ServiceDegradationRegistry.isUp(DegradedService.firestore);

  static String get userMessage => isActive
      ? 'Modo emergência: a trabalhar localmente. Sincroniza ao voltar online.'
      : 'Operação normal.';

  static void setFirebaseUnavailable(bool value) {
    _firebaseUnavailable = value;
  }

  static void refreshFromConnectivity() {
    if (AppConnectivityService.instance.isOnline &&
        ServiceDegradationRegistry.isUp(DegradedService.firestore)) {
      _firebaseUnavailable = false;
    }
  }
}
