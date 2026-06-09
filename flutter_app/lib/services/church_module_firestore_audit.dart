import 'package:flutter/foundation.dart' show debugPrint;
import 'package:gestao_yahweh/services/church_operational_firestore_trace.dart';

/// Auditoria cirúrgica — log antes de cada consulta crítica do painel.
abstract final class ChurchModuleFirestoreAudit {
  ChurchModuleFirestoreAudit._();

  static void logBeforeQuery({
    required String module,
    required String churchId,
    required String path,
  }) {
    debugPrint('MODULO');
    debugPrint(module);
    debugPrint('churchId');
    debugPrint(churchId);
    debugPrint('PATH');
    debugPrint(path);
  }

  static Future<T> traceQuery<T>({
    required String module,
    required String churchId,
    required String path,
    required Future<T> Function() run,
  }) async {
    logBeforeQuery(module: module, churchId: churchId, path: path);
    final sw = Stopwatch()..start();
    try {
      final result = await run();
      ChurchOperationalFirestoreTrace.record(
        origin: module,
        firestorePath: path,
        churchId: churchId,
        durationMs: sw.elapsedMilliseconds,
      );
      return result;
    } catch (e, st) {
      ChurchOperationalFirestoreTrace.record(
        origin: module,
        firestorePath: path,
        churchId: churchId,
        durationMs: sw.elapsedMilliseconds,
        error: '$e',
      );
      Error.throwWithStackTrace(e, st);
    } finally {
      sw.stop();
    }
  }
}

/// Resultado de probe por módulo (Configurações → Diagnóstico).
class ChurchModuleProbeResult {
  const ChurchModuleProbeResult({
    required this.module,
    required this.churchId,
    required this.collectionPath,
    this.documentPath,
    this.ok = false,
    this.count,
    this.durationMs,
    this.error,
    this.usedLegacyPath = false,
  });

  final String module;
  final String churchId;
  final String collectionPath;
  final String? documentPath;
  final bool ok;
  final int? count;
  final int? durationMs;
  final String? error;
  final bool usedLegacyPath;

  Map<String, dynamic> toJson() => {
        'module': module,
        'churchId': churchId,
        'collectionPath': collectionPath,
        if (documentPath != null) 'documentPath': documentPath,
        'ok': ok,
        if (count != null) 'count': count,
        if (durationMs != null) 'durationMs': durationMs,
        if (error != null) 'error': error,
        'usedLegacyPath': usedLegacyPath,
      };

  factory ChurchModuleProbeResult.fromJson(Map<String, dynamic> json) {
    return ChurchModuleProbeResult(
      module: (json['module'] ?? '').toString(),
      churchId: (json['churchId'] ?? '').toString(),
      collectionPath: (json['collectionPath'] ?? '').toString(),
      documentPath: json['documentPath']?.toString(),
      ok: json['ok'] == true,
      count: json['count'] is int ? json['count'] as int : null,
      durationMs: json['durationMs'] is int ? json['durationMs'] as int : null,
      error: json['error']?.toString(),
      usedLegacyPath: json['usedLegacyPath'] == true,
    );
  }

  ChurchModuleProbeResult copyWith({
    String? module,
    String? churchId,
    String? collectionPath,
    String? documentPath,
    bool? ok,
    int? count,
    int? durationMs,
    String? error,
    bool? usedLegacyPath,
  }) {
    return ChurchModuleProbeResult(
      module: module ?? this.module,
      churchId: churchId ?? this.churchId,
      collectionPath: collectionPath ?? this.collectionPath,
      documentPath: documentPath ?? this.documentPath,
      ok: ok ?? this.ok,
      count: count ?? this.count,
      durationMs: durationMs ?? this.durationMs,
      error: error ?? this.error,
      usedLegacyPath: usedLegacyPath ?? this.usedLegacyPath,
    );
  }
}
