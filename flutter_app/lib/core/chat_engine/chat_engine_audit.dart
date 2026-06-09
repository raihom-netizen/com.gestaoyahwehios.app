import 'package:flutter/foundation.dart' show kIsWeb;

/// Auditoria do motor de mensagens — tempos de envio, recebimento, cache, abertura.
class ChatEngineAuditEntry {
  const ChatEngineAuditEntry({
    required this.operation,
    required this.durationMs,
    this.docs = 0,
    this.fromCache = false,
    this.error,
    required this.at,
  });

  final String operation;
  final int durationMs;
  final int docs;
  final bool fromCache;
  final String? error;
  final DateTime at;
}

class ChatEngineAuditTimer {
  ChatEngineAuditTimer(this.operation) : startedAt = DateTime.now();
  final String operation;
  final DateTime startedAt;
}

abstract final class ChatEngineAudit {
  ChatEngineAudit._();

  static final List<ChatEngineAuditEntry> _entries = [];
  static final Map<String, ChatEngineAuditTimer> _active = {};
  static int? _conversationOpenMs;

  static ChatEngineAuditTimer start(String operation) {
    final t = ChatEngineAuditTimer(operation);
    _active[operation] = t;
    return t;
  }

  static void end(
    ChatEngineAuditTimer timer, {
    int docs = 0,
    bool fromCache = false,
    String? error,
  }) {
    final ms = DateTime.now().difference(timer.startedAt).inMilliseconds;
    _entries.add(
      ChatEngineAuditEntry(
        operation: timer.operation,
        durationMs: ms,
        docs: docs,
        fromCache: fromCache,
        error: error,
        at: DateTime.now(),
      ),
    );
    _active.remove(timer.operation);
    if (_entries.length > 200) {
      _entries.removeRange(0, _entries.length - 200);
    }
  }

  static void recordConversationOpen(int ms) => _conversationOpenMs = ms;

  static String toReport() {
    final platform = kIsWeb ? 'WEB' : 'MOBILE';
    final b = StringBuffer()
      ..writeln('=== CHAT ENGINE AUDIT — $platform ===')
      ..writeln('')
      ..writeln('| Operação | ms | docs | cache | erro |');
    for (final e in _entries.reversed.take(40)) {
      b.writeln(
        '| ${e.operation} | ${e.durationMs} | ${e.docs} | ${e.fromCache ? "sim" : "—"} | ${e.error ?? "—"} |',
      );
    }
    if (_conversationOpenMs != null) {
      b.writeln('');
      b.writeln('Tempo abertura conversa: ${_conversationOpenMs}ms');
    }
    return b.toString().trimRight();
  }

  static void clear() {
    _entries.clear();
    _conversationOpenMs = null;
  }
}
