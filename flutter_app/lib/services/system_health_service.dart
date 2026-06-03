import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/hive_local_store.dart';
import 'package:gestao_yahweh/core/resilience/degraded_services.dart';
import 'package:gestao_yahweh/core/resilience/emergency_mode_service.dart';
import 'package:gestao_yahweh/core/resilience/service_degradation_registry.dart';
import 'package:gestao_yahweh/core/system_health/system_last_error_registry.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/services/yahweh_telemetry.dart';

class SystemHealthCheck {
  const SystemHealthCheck({
    required this.label,
    required this.ok,
    this.detail = '',
    this.severity = SystemHealthSeverity.ok,
  });

  final String label;
  final bool ok;
  final String detail;
  final SystemHealthSeverity severity;
}

enum SystemHealthSeverity { ok, warn, critical, info }

class SystemHealthSnapshot {
  const SystemHealthSnapshot({
    required this.firebase,
    required this.checks,
    required this.productionReady,
    required this.blockingReasons,
    this.tenantId,
  });

  final FirebaseHealthReport firebase;
  final List<SystemHealthCheck> checks;
  final bool productionReady;
  final List<String> blockingReasons;
  final String? tenantId;
}

/// Central de Saúde — probes runtime (painel Master ADM).
abstract final class SystemHealthService {
  SystemHealthService._();

  static Future<SystemHealthSnapshot> probe({
    String? tenantIdHint,
    bool requireAuth = false,
  }) async {
    final checks = <SystemHealthCheck>[];
    final blocking = <String>[];

    FirebaseHealthReport firebase;
    try {
      if (!FirebaseBootstrapService.isReady()) {
        await FirebaseBootstrapService.initialize();
      }
      firebase = await FirebaseBootstrapService.healthCheck(
        requireAuthSession: requireAuth,
        logLabel: 'system_health',
      );
    } catch (e, st) {
      SystemLastErrorRegistry.record(
        module: 'FIREBASE',
        error: e,
        stackTrace: st,
        context: 'healthCheck',
      );
      rethrow;
    }

    void addCheck(SystemHealthCheck c, {bool blocksProduction = false}) {
      checks.add(c);
      if (blocksProduction && !c.ok) {
        blocking.add('${c.label}: ${c.detail}');
      }
    }

    addCheck(
      SystemHealthCheck(
        label: 'Firebase Core',
        ok: firebase.coreInitialized,
        detail: firebase.coreInitialized ? 'OK' : 'Não inicializado',
        severity: firebase.coreInitialized
            ? SystemHealthSeverity.ok
            : SystemHealthSeverity.critical,
      ),
      blocksProduction: true,
    );

    addCheck(
      SystemHealthCheck(
        label: 'Firebase Auth',
        ok: firebase.authOk,
        detail: firebase.authDetail ?? (firebase.authOk ? 'Sessão OK' : 'Sem sessão'),
        severity:
            firebase.authOk ? SystemHealthSeverity.ok : SystemHealthSeverity.warn,
      ),
      blocksProduction: requireAuth && !firebase.authOk,
    );

    addCheck(
      SystemHealthCheck(
        label: 'Firestore',
        ok: firebase.firestoreOk,
        detail:
            firebase.firestoreDetail ?? (firebase.firestoreOk ? 'OK' : 'Falha'),
        severity: firebase.firestoreOk
            ? SystemHealthSeverity.ok
            : SystemHealthSeverity.critical,
      ),
      blocksProduction: true,
    );

    addCheck(
      SystemHealthCheck(
        label: 'Storage',
        ok: firebase.storageOk,
        detail:
            firebase.storageDetail ?? (firebase.storageOk ? 'OK' : 'Falha'),
        severity: firebase.storageOk
            ? SystemHealthSeverity.ok
            : SystemHealthSeverity.critical,
      ),
      blocksProduction: true,
    );

    addCheck(
      SystemHealthCheck(
        label: 'Sync (Hive + rede)',
        ok: await _syncOk(),
        detail: await _syncDetail(),
        severity: SystemHealthSeverity.info,
      ),
      blocksProduction: false,
    );

    final tid = await _resolveTenant(tenantIdHint);
    if (tid != null && tid.isNotEmpty) {
      addCheck(await _chatCheck(tid), blocksProduction: false);
      addCheck(await _feedCheck(tid, collection: 'avisos'), blocksProduction: false);
      addCheck(await _feedCheck(tid, collection: 'eventos'), blocksProduction: false);
      addCheck(await _publicSiteCheck(tid), blocksProduction: false);
    } else {
      addCheck(
        const SystemHealthCheck(
          label: 'Chat / Avisos / Eventos',
          ok: true,
          detail: 'Sem tenant — teste com igreja vinculada',
          severity: SystemHealthSeverity.warn,
        ),
      );
    }

    final uploadOk = await _uploadQueuesOk();
    addCheck(
      SystemHealthCheck(
        label: 'Upload',
        ok: uploadOk.ok,
        detail: uploadOk.detail,
        severity: uploadOk.ok ? SystemHealthSeverity.ok : SystemHealthSeverity.warn,
      ),
      blocksProduction: !uploadOk.ok,
    );

    addCheck(
      SystemHealthCheck(
        label: 'Backup automático',
        ok: true,
        detail:
            'CF backupDailyToGcs (Firestore) + backupDailyToDrive — ver Firebase Console',
        severity: SystemHealthSeverity.info,
      ),
    );

    addCheck(
      SystemHealthCheck(
        label: 'Monitoramento',
        ok: !kIsWeb,
        detail: kIsWeb
            ? 'Crashlytics/Performance: mobile nativo; Analytics: web+mobile'
            : 'Crashlytics + Analytics + Performance ativos em release',
        severity: SystemHealthSeverity.info,
      ),
    );

    addCheck(
      SystemHealthCheck(
        label: 'Modo emergência',
        ok: !EmergencyModeService.isActive,
        detail: EmergencyModeService.userMessage,
        severity: EmergencyModeService.isActive
            ? SystemHealthSeverity.warn
            : SystemHealthSeverity.ok,
      ),
    );

    final degraded = DegradedService.values
        .where((s) => !ServiceDegradationRegistry.isUp(s))
        .toList();
    addCheck(
      SystemHealthCheck(
        label: 'Degradação automática',
        ok: degraded.isEmpty,
        detail: degraded.isEmpty
            ? 'Todos os serviços opcionais OK'
            : 'Degradados: ${degraded.map((s) => s.name).join(', ')} — app continua',
        severity: degraded.isEmpty ? SystemHealthSeverity.ok : SystemHealthSeverity.warn,
      ),
    );

    final productionReady = blocking.isEmpty &&
        firebase.coreInitialized &&
        firebase.firestoreOk;

    ServiceDegradationRegistry.applyHealth(
      storageOk: firebase.storageOk,
      fcmOk: firebase.fcmOk,
      publicSiteOk: checks.any((c) => c.label == 'Site Público' && c.ok),
      firestoreOk: firebase.firestoreOk,
      functionsOk: firebase.functionsOk,
    );
    EmergencyModeService.refreshFromConnectivity();

    return SystemHealthSnapshot(
      firebase: firebase,
      checks: checks,
      productionReady: productionReady,
      blockingReasons: blocking,
      tenantId: tid,
    );
  }

  static Future<String?> _resolveTenant(String? hint) async {
    final h = hint?.trim();
    if (h != null && h.isNotEmpty) return h;
    try {
      return await PendingUploadsFirestoreService.resolveTenantForCurrentUser();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _syncOk() async {
    if (!AppConnectivityService.instance.isOnline) return true;
    final pending = await HiveLocalStore.instance.listTasks();
    return pending.length < 200;
  }

  static Future<String> _syncDetail() async {
    final online = AppConnectivityService.instance.isOnline;
    final pending = await HiveLocalStore.instance.listTasks();
    if (!online) {
      return 'Offline — ${pending.length} tarefa(s) na fila Hive';
    }
    if (pending.isEmpty) return 'Online — fila Hive vazia';
    return 'Online — ${pending.length} tarefa(s) pendente(s)';
  }

  static Future<SystemHealthCheck> _chatCheck(String tenantId) async {
    try {
      final uid = firebaseDefaultAuth.currentUser?.uid;
      if (uid == null || uid.isEmpty) {
        return const SystemHealthCheck(
          label: 'Chat',
          ok: false,
          detail: 'Sem utilizador autenticado',
          severity: SystemHealthSeverity.warn,
        );
      }
      await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantId)
          .collection('chats')
          .where('participantUids', arrayContains: uid)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return const SystemHealthCheck(
        label: 'Chat',
        ok: true,
        detail: 'Leitura chats OK (regras + índice)',
        severity: SystemHealthSeverity.ok,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return SystemHealthCheck(
          label: 'Chat',
          ok: false,
          detail: 'permission-denied — publicar firestore.rules',
          severity: SystemHealthSeverity.critical,
        );
      }
      return SystemHealthCheck(
        label: 'Chat',
        ok: false,
        detail: e.message ?? e.code,
        severity: SystemHealthSeverity.warn,
      );
    } catch (e) {
      return SystemHealthCheck(
        label: 'Chat',
        ok: false,
        detail: e.toString(),
        severity: SystemHealthSeverity.warn,
      );
    }
  }

  static Future<SystemHealthCheck> _feedCheck(
    String tenantId, {
    required String collection,
  }) async {
    final label = collection == 'avisos' ? 'Avisos' : 'Eventos';
    try {
      await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantId)
          .collection(collection)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return SystemHealthCheck(
        label: label,
        ok: true,
        detail: 'Leitura $collection OK',
        severity: SystemHealthSeverity.ok,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return SystemHealthCheck(
          label: label,
          ok: false,
          detail: 'permission-denied',
          severity: SystemHealthSeverity.critical,
        );
      }
      return SystemHealthCheck(
        label: label,
        ok: false,
        detail: e.message ?? e.code,
        severity: SystemHealthSeverity.warn,
      );
    } catch (e) {
      return SystemHealthCheck(
        label: label,
        ok: false,
        detail: e.toString(),
        severity: SystemHealthSeverity.warn,
      );
    }
  }

  static Future<SystemHealthCheck> _publicSiteCheck(String tenantId) async {
    final warmed = await ServiceDegradationRegistry.runOptional<bool>(
      DegradedService.publicSite,
      () async {
        final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('warmChurchPublicFeedCache');
        await fn.call({'tenantId': tenantId}).timeout(const Duration(seconds: 25));
        return true;
      },
      fallback: false,
    );
    if (warmed) {
      return const SystemHealthCheck(
        label: 'Site Público',
        ok: true,
        detail: 'Cache público aquecido',
        severity: SystemHealthSeverity.ok,
      );
    }
    return const SystemHealthCheck(
      label: 'Site Público',
      ok: false,
      detail: 'Degradado — painel e app continuam',
      severity: SystemHealthSeverity.warn,
    );
  }

  static Future<({bool ok, String detail})> _uploadQueuesOk() async {
    final mem = StorageUploadQueueService.instance.pendingCount;
    final chat = await ChurchChatMediaOutboxService.pendingJobCount();
    final mural = await MuralPublishOutboxService.pendingJobCount();
    final total = mem + chat + mural;
    if (total == 0) {
      return (ok: true, detail: 'Filas locais vazias');
    }
    if (total < 15) {
      return (ok: true, detail: '$total job(s) em fila local (normal)');
    }
    return (ok: false, detail: '$total jobs presos — usar reenvio');
  }

  static const Duration periodicInterval = Duration(minutes: 5);

  static Timer? _periodicTimer;
  static DateTime? lastPeriodicAt;
  static SystemHealthSnapshot? lastPeriodicSnapshot;
  static String? lastPeriodicError;

  /// Health check automático a cada 5 minutos (logs em YahwehFlowLog + Telemetry).
  static void bindPeriodicProbe() {
    _periodicTimer?.cancel();
    unawaited(_runPeriodicProbe(reason: 'startup'));
    _periodicTimer = Timer.periodic(periodicInterval, (_) {
      unawaited(_runPeriodicProbe(reason: 'interval'));
    });
  }

  static void stopPeriodicProbe() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  static Future<SystemHealthSnapshot?> _runPeriodicProbe({
    required String reason,
  }) async {
    try {
      final snap = await probe(requireAuth: false);
      lastPeriodicAt = DateTime.now();
      lastPeriodicSnapshot = snap;
      lastPeriodicError = null;
      YahwehFlowLog.sync(
        'HEALTH',
        'periodic_$reason ready=${snap.productionReady} online=${AppConnectivityService.instance.isOnline}',
      );
      YahwehTelemetry.log(
        'health_periodic reason=$reason ready=${snap.productionReady} '
        'firestore=${snap.firebase.firestoreOk} auth=${snap.firebase.authOk}',
      );
      return snap;
    } catch (e, st) {
      lastPeriodicError = e.toString();
      SystemLastErrorRegistry.record(
        module: 'HEALTH_PERIODIC',
        error: e,
        stackTrace: st,
        context: reason,
      );
      YahwehFlowLog.error('HEALTH', e, st);
      return null;
    }
  }
}
