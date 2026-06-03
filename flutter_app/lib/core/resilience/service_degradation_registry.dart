import 'package:gestao_yahweh/core/resilience/degraded_services.dart';
import 'package:gestao_yahweh/core/system_health/system_last_error_registry.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';

class ServiceDegradationState {
  const ServiceDegradationState({
    required this.up,
    this.detail,
    this.since,
  });

  final bool up;
  final String? detail;
  final DateTime? since;
}

/// Modo degradação automática — falha isolada por serviço.
abstract final class ServiceDegradationRegistry {
  ServiceDegradationRegistry._();

  static final Map<DegradedService, ServiceDegradationState> _states = {
    for (final s in DegradedService.values)
      s: const ServiceDegradationState(up: true),
  };

  static Map<DegradedService, ServiceDegradationState> get snapshot =>
      Map<DegradedService, ServiceDegradationState>.unmodifiable(_states);

  static bool isUp(DegradedService service) => _states[service]?.up ?? true;

  static void markUp(DegradedService service) {
    _states[service] = ServiceDegradationState(up: true);
    YahwehFlowLog.online(service.name.toUpperCase());
  }

  static void markDown(DegradedService service, Object error, {String? detail}) {
    _states[service] = ServiceDegradationState(
      up: false,
      detail: detail ?? error.toString(),
      since: DateTime.now(),
    );
    SystemLastErrorRegistry.record(
      module: service.name.toUpperCase(),
      error: error,
      context: 'degradation',
    );
    YahwehFlowLog.error(service.name.toUpperCase(), error, StackTrace.current);
  }

  /// Executa [fn]; se falhar, marca serviço em degradação e devolve [fallback].
  static Future<T> runOptional<T>(
    DegradedService service,
    Future<T> Function() fn, {
    required T fallback,
  }) async {
    if (!isUp(service)) return fallback;
    try {
      final result = await fn();
      markUp(service);
      return result;
    } catch (e, st) {
      markDown(service, e);
      SystemLastErrorRegistry.record(
        module: service.name.toUpperCase(),
        error: e,
        stackTrace: st,
        context: 'runOptional',
      );
      return fallback;
    }
  }

  static void applyHealth({
    required bool storageOk,
    required bool fcmOk,
    required bool publicSiteOk,
    required bool firestoreOk,
    required bool functionsOk,
  }) {
    void set(DegradedService s, bool ok, String label) {
      if (ok) {
        markUp(s);
      } else {
        markDown(s, StateError('$label indisponível'));
      }
    }

    set(DegradedService.storage, storageOk, 'Storage');
    set(DegradedService.push, fcmOk, 'Push');
    set(DegradedService.publicSite, publicSiteOk, 'Site público');
    set(DegradedService.firestore, firestoreOk, 'Firestore');
    set(DegradedService.functions, functionsOk, 'Functions');
  }
}
