import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/offline/hive_local_store.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/resilience/degraded_services.dart';
import 'package:gestao_yahweh/core/resilience/emergency_mode_service.dart';
import 'package:gestao_yahweh/core/resilience/service_degradation_registry.dart';
import 'package:gestao_yahweh/core/system_health/system_last_error_registry.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/church_chat_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/services/system_health_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

class AdminDiagnosticSnapshot {
  const AdminDiagnosticSnapshot({
    required this.health,
    required this.pendingSyncCount,
    required this.pendingUploadCount,
    required this.emergencyMode,
    required this.degradedServices,
    required this.chatOnlineCount,
    required this.lastError,
    required this.lastBackupHint,
    required this.lastSyncAt,
    required this.pendingChatMessages,
    required this.pendingAvisos,
    required this.pendingEventos,
    required this.hiveModulesCached,
  });

  final SystemHealthSnapshot health;
  final int pendingSyncCount;
  final int pendingUploadCount;
  final bool emergencyMode;
  final List<(DegradedService service, ServiceDegradationState state)> degradedServices;
  final int chatOnlineCount;
  final SystemLastErrorEntry? lastError;
  final String lastBackupHint;
  final DateTime? lastSyncAt;
  final int pendingChatMessages;
  final int pendingAvisos;
  final int pendingEventos;
  final List<String> hiveModulesCached;
}

/// Painel diagnóstico — só administradores (Master / Saúde do Sistema).
abstract final class AdminDiagnosticService {
  AdminDiagnosticService._();

  static Future<AdminDiagnosticSnapshot> load({
    String? tenantIdHint,
  }) async {
    final health = await SystemHealthService.probe(
      tenantIdHint: tenantIdHint,
      requireAuth: false,
    );

    final pendingSync = (await HiveLocalStore.instance.listTasks()).length;
    final pendingChatHive =
        (await HiveLocalStore.instance.listTasks(module: OfflineModules.chat))
            .length;
    final pendingAvisosHive =
        (await HiveLocalStore.instance.listTasks(module: OfflineModules.avisos))
            .length;
    final pendingEventosHive =
        (await HiveLocalStore.instance.listTasks(module: OfflineModules.eventos))
            .length;
    final memQ = StorageUploadQueueService.instance.pendingCount;
    final chatQ = await ChurchChatMediaOutboxService.pendingJobCount();
    final muralQ = await MuralPublishOutboxService.pendingJobCount();
    final pendingUpload = memQ + chatQ + muralQ;
    final pendingChatMessages = chatQ + pendingChatHive;

    var chatOnline = 0;
    final tid = health.tenantId?.trim() ?? '';

    DateTime? lastSync;
    final cachedModules = <String>[];
    if (tid.isNotEmpty) {
      lastSync = await TenantModuleHiveCache.latestSyncForTenant(tid);
      for (final mod in const [
        'membros',
        'avisos',
        'eventos',
        'chat',
        'patrimonio',
        'financeiro',
        'agenda',
      ]) {
        final docs = await TenantModuleHiveCache.readDocs(tid, mod);
        if (docs.isNotEmpty) cachedModules.add(mod);
      }
    }
    if (tid.isNotEmpty) {
      try {
        final op = await ChurchOperationalPaths.resolveCached(tid.trim());
        final q = await             ChurchOperationalPaths.churchDoc(op)
            .collection('chat_presence')
            .limit(80)
            .get();
        for (final d in q.docs) {
          if (ChurchChatService.isOnlineFromSnapshot(d)) chatOnline++;
        }
      } catch (_) {}
    }

    final degraded = DegradedService.values
        .map((s) => (s, ServiceDegradationRegistry.snapshot[s]!))
        .where((e) => !e.$2.up)
        .toList();

    EmergencyModeService.refreshFromConnectivity();

    return AdminDiagnosticSnapshot(
      health: health,
      pendingSyncCount: pendingSync,
      pendingUploadCount: pendingUpload,
      emergencyMode: EmergencyModeService.isActive,
      degradedServices: degraded,
      chatOnlineCount: chatOnline,
      lastError: SystemLastErrorRegistry.latest,
      lastBackupHint:
          'Diário 00:05 BRT — CF backupDailyToGcs + backupDailyToDrive',
      lastSyncAt: lastSync,
      pendingChatMessages: pendingChatMessages,
      pendingAvisos: pendingAvisosHive + muralQ,
      pendingEventos: pendingEventosHive,
      hiveModulesCached: cachedModules,
    );
  }
}
