import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_paths.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_operational_firestore_trace.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// DiagnÃ³stico de sessÃ£o â€” churchId, paths, tempos e Ãºltimo erro.
class SystemDiagnosticSnapshot {
  const SystemDiagnosticSnapshot({
    required this.churchId,
    required this.seedId,
    required this.firestorePath,
    required this.storagePath,
    this.userUid,
    this.boundAt,
    this.fieldCount,
    this.loadDurationMs,
    this.firestoreReadMs,
    this.lastError,
    this.readSource,
    this.tenantMismatch = false,
    this.recentTraces = const [],
    this.bootstrapMs,
    this.fromLocalCache = false,
  });

  final String churchId;
  final String seedId;
  final String firestorePath;
  final String storagePath;
  final String? userUid;
  final DateTime? boundAt;
  final int? fieldCount;
  final int? loadDurationMs;
  final int? firestoreReadMs;
  final String? lastError;
  final String? readSource;
  final bool tenantMismatch;
  final List<ChurchFirestoreTraceEntry> recentTraces;
  final int? bootstrapMs;
  final bool fromLocalCache;

  Map<String, dynamic> toJson() => {
        'churchId': churchId,
        'seedId': seedId,
        'firestorePath': firestorePath,
        'storagePath': storagePath,
        if (userUid != null) 'userUid': userUid,
        if (boundAt != null) 'boundAt': boundAt!.toIso8601String(),
        if (fieldCount != null) 'fieldCount': fieldCount,
        if (loadDurationMs != null) 'loadDurationMs': loadDurationMs,
        if (firestoreReadMs != null) 'firestoreReadMs': firestoreReadMs,
        if (lastError != null) 'lastError': lastError,
        if (readSource != null) 'readSource': readSource,
        'tenantMismatch': tenantMismatch,
        'recentTraces': recentTraces.map((e) => e.toJson()).toList(),
        if (bootstrapMs != null) 'bootstrapMs': bootstrapMs,
        'fromLocalCache': fromLocalCache,
      };
}

abstract final class SystemDiagnosticService {
  SystemDiagnosticService._();

  static const Duration kProbeTimeout = Duration(seconds: 15);

  static Future<SystemDiagnosticSnapshot> probe({
    required String seedTenantId,
    String? userUid,
  }) async {
    final uid = userUid ?? firebaseDefaultAuth.currentUser?.uid;
    final sw = Stopwatch()..start();
    String? lastError = ChurchContextService.lastError;
    var churchId = ChurchContextService.currentChurchId ?? '';
    var fieldCount = 0;
    String? readSource;
    var mismatch = false;
    int? firestoreMs;

    try {
      if (churchId.isEmpty) {
        churchId = await ChurchContextService.resolveAndBind(
          seed: seedTenantId,
          userUid: uid,
        ).timeout(kProbeTimeout);
      }

      if (churchId.isNotEmpty) {
        if (kIsWeb) {
          await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
        }
        final fsSw = Stopwatch()..start();
        final result = await FirestoreWebGuard.runWithWebRecovery(
          () => (kIsWeb
                  ? ChurchRepository.loadByChurchId(
                      churchId,
                      seedTenantId: churchId,
                      userUid: uid,
                    )
                  : ChurchRepository.loadChurchData(
                      seedTenantId: churchId,
                      userUid: uid,
                      directDocOnly: true,
                    ))
              .timeout(kProbeTimeout),
          maxAttempts: kIsWeb ? 4 : 1,
        );
        fsSw.stop();
        firestoreMs = fsSw.elapsedMilliseconds;
        fieldCount = result.fieldCount;
        readSource = result.readSource;
        mismatch = result.tenantMismatch;
      }
    } catch (e) {
      lastError = e.toString();
    }

    sw.stop();
    final id = churchId.trim();
    return SystemDiagnosticSnapshot(
      churchId: id,
      seedId: ChurchContextService.seedId ?? seedTenantId.trim(),
      firestorePath: id.isEmpty ? '' : FirebasePaths.igreja(id),
      storagePath: id.isEmpty ? '' : FirebasePaths.storageRoot(id),
      userUid: uid,
      boundAt: ChurchContextService.boundAt,
      fieldCount: fieldCount,
      loadDurationMs: sw.elapsedMilliseconds,
      firestoreReadMs: firestoreMs,
      lastError: lastError,
      readSource: readSource,
      tenantMismatch: mismatch,
      recentTraces: ChurchOperationalFirestoreTrace.recent,
      bootstrapMs: ChurchContextService.lastBootstrapMs,
      fromLocalCache: ChurchContextService.currentChurchData != null &&
          ChurchContextService.boundAt != null,
    );
  }
}

