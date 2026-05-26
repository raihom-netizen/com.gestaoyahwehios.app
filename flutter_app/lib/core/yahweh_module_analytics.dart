import 'dart:async' show unawaited;

import 'package:gestao_yahweh/services/analytics_service.dart';

/// Uma linha no [initState] dos módulos principais do painel.
void logYahwehModuleScreen(String module) {
  unawaited(AnalyticsService.logScreen(module));
}
