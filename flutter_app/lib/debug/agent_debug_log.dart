import 'agent_debug_log_stub.dart'
    if (dart.library.html) 'agent_debug_log_web.dart';

/// Logs NDJSON para sessão de debug (web → ingest local).
abstract final class AgentDebugLog {
  AgentDebugLog._();

  static const _sessionId = '7f8fb5';

  static void log({
    required String location,
    required String message,
    required String hypothesisId,
    Map<String, dynamic>? data,
    String runId = 'pre-fix',
  }) {
    // #region agent log
    agentDebugLogPost(<String, dynamic>{
      'sessionId': _sessionId,
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data ?? <String, dynamic>{},
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // #endregion
  }
}
