import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/system_health/system_last_error_registry.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';

/// `catch (e, s) { print; rethrow }` — padrão obrigatório produção premium.
abstract final class YahwehCatchLog {
  YahwehCatchLog._();

  static void log(Object e, StackTrace s, {String? tag, bool shouldRethrow = false}) {
    final prefix = tag != null ? 'ERROR $tag' : 'ERROR';
    // ignore: avoid_print
    print(prefix);
    // ignore: avoid_print
    print(e);
    // ignore: avoid_print
    print(s);
    if (kDebugMode) debugPrint('$prefix $e\n$s');
    SystemLastErrorRegistry.record(
      module: tag ?? 'APP',
      error: e,
      stackTrace: s,
    );
    unawaited(
      CrashlyticsService.record(e, s, reason: tag ?? 'yahweh_catch'),
    );
    if (shouldRethrow) {
      Error.throwWithStackTrace(e, s);
    }
  }

  static Never logAndRethrow(Object e, StackTrace s, {String? tag}) {
    log(e, s, tag: tag);
    Error.throwWithStackTrace(e, s);
  }
}
