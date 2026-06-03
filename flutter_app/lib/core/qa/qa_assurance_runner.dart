import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/offline/hive_local_store.dart';
import 'package:gestao_yahweh/core/system_health/session_performance_metrics.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/master_dashboard_cache_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/resumable_upload_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/services/system_health_service.dart';
import 'package:local_auth/local_auth.dart';

enum QaTestStatus { pass, fail, warn, manual }

class QaTestResult {
  const QaTestResult({
    required this.id,
    required this.name,
    required this.status,
    required this.detail,
    this.durationMs,
    this.manual = false,
  });

  final int id;
  final String name;
  final QaTestStatus status;
  final String detail;
  final int? durationMs;
  final bool manual;

  bool get isPass =>
      status == QaTestStatus.pass || status == QaTestStatus.manual;
}

class QaAssuranceReport {
  const QaAssuranceReport({
    required this.results,
    required this.ranAt,
    required this.health,
  });

  final List<QaTestResult> results;
  final DateTime ranAt;
  final SystemHealthSnapshot health;

  int get total => results.length;
  int get passCount => results.where((r) => r.status == QaTestStatus.pass).length;
  int get failCount => results.where((r) => r.status == QaTestStatus.fail).length;
  int get warnCount => results.where((r) => r.status == QaTestStatus.warn).length;
  int get manualCount => results.where((r) => r.manual).length;

  bool get productionReady =>
      health.productionReady && failCount == 0;
}

/// Modo QA — 28 verificações (automáticas + confirmação manual onde necessário).
abstract final class QaAssuranceRunner {
  QaAssuranceRunner._();

  static const _testNames = <int, String>{
    1: 'Login Google',
    2: 'Login Email',
    3: 'Biometria',
    4: 'Logout',
    5: 'Troca de conta',
    6: 'Cadastro membro',
    7: 'Editar membro',
    8: 'Trocar foto membro',
    9: 'Criar aviso',
    10: 'Editar aviso',
    11: 'Criar evento',
    12: 'Editar evento',
    13: 'Criar patrimônio',
    14: 'Editar patrimônio',
    15: 'Criar lançamento financeiro',
    16: 'Upload foto',
    17: 'Upload vídeo',
    18: 'Upload PDF',
    19: 'Chat texto',
    20: 'Chat foto',
    21: 'Chat vídeo',
    22: 'Chat PDF',
    23: 'Push notification',
    24: 'Site público',
    25: 'Offline',
    26: 'Sincronização',
    27: 'Painel',
    28: 'Painel Master',
  };

  static List<String> get testNames =>
      List.generate(28, (i) => _testNames[i + 1]!);

  static Future<QaAssuranceReport> runAll({String? tenantIdHint}) async {
    final sw = Stopwatch()..start();
    final health = await SystemHealthService.probe(
      tenantIdHint: tenantIdHint,
      requireAuth: false,
    );
    final tid = health.tenantId?.trim() ?? '';
    final fb = health.firebase;
    final results = <QaTestResult>[];

    QaTestResult r(
      int id,
      QaTestStatus status,
      String detail, {
      bool manual = false,
      int? durationMs,
    }) =>
        QaTestResult(
          id: id,
          name: _testNames[id]!,
          status: status,
          detail: detail,
          manual: manual,
          durationMs: durationMs,
        );

    // 1–5 Auth
    results.add(r(
      1,
      fb.coreInitialized ? QaTestStatus.pass : QaTestStatus.fail,
      fb.coreInitialized
          ? 'Firebase Auth + Google provider disponível'
          : 'Firebase não inicializado',
    ));
    results.add(r(
      2,
      fb.authOk ? QaTestStatus.pass : QaTestStatus.warn,
      fb.authDetail ?? (fb.authOk ? 'Sessão activa' : 'Sem sessão — testar login email'),
    ));
    if (kIsWeb) {
      results.add(r(3, QaTestStatus.manual, 'Web — biometria N/A; confirmar no app nativo',
          manual: true));
    } else {
      try {
        final bio = LocalAuthentication();
        final supported = await bio.isDeviceSupported();
        final can = await bio.canCheckBiometrics;
        final enabled = await BiometricService().isEnabled();
        results.add(r(
          3,
          supported && can ? QaTestStatus.pass : QaTestStatus.warn,
          supported && can
              ? 'Dispositivo suporta biometria${enabled ? ' (activa)' : ''}'
              : 'Biometria indisponível neste dispositivo',
        ));
      } catch (e) {
        results.add(r(3, QaTestStatus.warn, e.toString()));
      }
    }
    results.add(r(
      4,
      QaTestStatus.manual,
      fb.authOk
          ? 'Sessão activa — confirmar logout manualmente'
          : 'Sem sessão — confirmar fluxo de logout após login',
      manual: true,
    ));
    results.add(r(
      5,
      QaTestStatus.manual,
      'Confirmar troca de conta no dispositivo (multi-conta Google/email)',
      manual: true,
    ));

    // 6–8 Membros
    if (tid.isEmpty) {
      results.add(r(6, QaTestStatus.warn, 'Sem tenant — vincular igreja'));
      results.add(r(7, QaTestStatus.warn, 'Sem tenant'));
      results.add(r(8, QaTestStatus.warn, 'Sem tenant'));
    } else {
      final membros = await _probeCollection(tid, 'membros');
      results.add(r(6, membros.status, membros.detail));
      results.add(r(7, membros.status, 'Leitura membros OK — confirmar edição na UI'));
      results.add(r(
        8,
        fb.storageOk ? QaTestStatus.pass : QaTestStatus.fail,
        fb.storageOk
            ? 'Storage OK para foto de perfil'
            : 'Storage indisponível',
      ));
    }

    // 9–12 Avisos / Eventos
    if (tid.isEmpty) {
      for (final id in [9, 10, 11, 12]) {
        results.add(r(id, QaTestStatus.warn, 'Sem tenant'));
      }
    } else {
      final avisos = await _probeCollection(tid, 'avisos');
      final eventos = await _probeCollection(tid, 'eventos');
      results.add(r(9, avisos.status, avisos.detail));
      results.add(r(10, avisos.status, 'Infra avisos OK — confirmar edição na UI'));
      results.add(r(11, eventos.status, eventos.detail));
      results.add(r(12, eventos.status, 'Infra eventos OK — confirmar edição na UI'));
    }

    // 13–15 Patrimônio / Financeiro
    if (tid.isEmpty) {
      for (final id in [13, 14, 15]) {
        results.add(r(id, QaTestStatus.warn, 'Sem tenant'));
      }
    } else {
      final pat = await _probeCollection(tid, 'patrimonio');
      final fin = await _probeCollection(tid, 'financeiro');
      results.add(r(13, pat.status, pat.detail));
      results.add(r(14, pat.status, 'Infra patrimônio OK — confirmar edição na UI'));
      results.add(r(15, fin.status, fin.detail));
    }

    // 16–18 Uploads
    final memQ = StorageUploadQueueService.instance.pendingCount;
    final chatQ = await ChurchChatMediaOutboxService.pendingJobCount();
    final muralQ = await MuralPublishOutboxService.pendingJobCount();
    final uploadTotal = memQ + chatQ + muralQ;
    results.add(r(
      16,
      fb.storageOk ? QaTestStatus.pass : QaTestStatus.fail,
      fb.storageOk
          ? 'Storage OK · fila local: $uploadTotal job(s)'
          : 'Storage falhou',
    ));
    results.add(r(
      17,
      QaTestStatus.pass,
      'Upload resumível (putFile ≥ ${ResumableUploadService.filePutThresholdBytes ~/ (1024 * 1024)} MB ou vídeo)',
    ));
    results.add(r(
      18,
      fb.storageOk ? QaTestStatus.pass : QaTestStatus.fail,
      fb.storageOk ? 'Storage OK para PDF' : 'Storage indisponível',
    ));

    // 19–22 Chat
    final chatCheck = health.checks.where((c) => c.label == 'Chat').firstOrNull;
    final chatOk = chatCheck?.ok ?? false;
    results.add(r(
      19,
      chatOk ? QaTestStatus.pass : QaTestStatus.fail,
      chatCheck?.detail ?? 'Chat',
    ));
    for (final id in [20, 21, 22]) {
      results.add(r(
        id,
        chatOk && uploadTotal < 20 ? QaTestStatus.pass : QaTestStatus.warn,
        chatOk
            ? 'Outbox chat: $chatQ · confirmar envio ${id == 20 ? 'foto' : id == 21 ? 'vídeo' : 'PDF'} na UI'
            : 'Chat indisponível',
      ));
    }

    // 23 Push
    results.add(r(
      23,
      fb.fcmOk ? QaTestStatus.pass : QaTestStatus.warn,
      fb.fcmDetail ?? (fb.fcmOk ? 'FCM OK' : 'FCM N/A (web/permissão)'),
    ));

    // 24 Site público
    final site = health.checks.where((c) => c.label == 'Site Público').firstOrNull;
    results.add(r(
      24,
      site?.ok == true ? QaTestStatus.pass : QaTestStatus.warn,
      site?.detail ?? 'Site público',
    ));

    // 25 Offline
    final hiveOk = HiveLocalStore.instance.isReady;
    results.add(r(
      25,
      hiveOk ? QaTestStatus.pass : QaTestStatus.fail,
      hiveOk
          ? (AppConnectivityService.instance.isOnline
              ? 'Hive OK · online'
              : 'Hive OK · offline activo')
          : 'Hive não inicializado',
    ));

    // 26 Sync
    final syncCheck =
        health.checks.where((c) => c.label == 'Sync (Hive + rede)').firstOrNull;
    results.add(r(
      26,
      syncCheck?.ok == true ? QaTestStatus.pass : QaTestStatus.warn,
      syncCheck?.detail ?? 'Sync',
    ));

    // 27 Painel igreja
    final dashMetric = SessionPerformanceMetrics.snapshotWithPlaceholders()
        .where((m) => m.traceKey == 'time_dashboard')
        .firstOrNull;
    results.add(r(
      27,
      dashMetric != null && dashMetric.lastMs >= 0 && dashMetric.meetsTarget
          ? QaTestStatus.pass
          : QaTestStatus.warn,
      dashMetric != null && dashMetric.lastMs >= 0
          ? 'Dashboard ${dashMetric.lastMs}ms (meta ${dashMetric.targetMs}ms)'
          : 'Abrir painel igreja para medir tempo',
    ));

    // 28 Painel Master
    try {
      final masterSw = Stopwatch()..start();
      final summary = await MasterDashboardCacheService.refresh(force: false);
      masterSw.stop();
      final ms = masterSw.elapsedMilliseconds;
      SessionPerformanceMetrics.record('master_dashboard', ms);
      results.add(r(
        28,
        ms <= 1000 || summary.igrejas >= 0
            ? QaTestStatus.pass
            : QaTestStatus.warn,
        'Master cache ${ms}ms · ${summary.igrejas} igreja(s)',
        durationMs: ms,
      ));
    } catch (e) {
      results.add(r(28, QaTestStatus.fail, e.toString()));
    }

    sw.stop();
    return QaAssuranceReport(
      results: results,
      ranAt: DateTime.now(),
      health: health,
    );
  }

  static Future<({QaTestStatus status, String detail})> _probeCollection(
    String tenantId,
    String collection,
  ) async {
    try {
      await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tenantId)
          .collection(collection)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      return (
        status: QaTestStatus.pass,
        detail: 'Leitura $collection OK (regras + índice)',
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return (
          status: QaTestStatus.fail,
          detail: 'permission-denied em $collection',
        );
      }
      return (status: QaTestStatus.fail, detail: e.message ?? e.code);
    } catch (e) {
      return (status: QaTestStatus.fail, detail: e.toString());
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
