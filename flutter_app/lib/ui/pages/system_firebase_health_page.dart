import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
import 'package:gestao_yahweh/core/resilience/emergency_mode_service.dart';
import 'package:gestao_yahweh/core/system_health/system_last_error_registry.dart';
import 'package:gestao_yahweh/core/qa/multiplatform_qa_matrix.dart';
import 'package:gestao_yahweh/core/qa/qa_assurance_runner.dart';
import 'package:gestao_yahweh/core/system_health/session_performance_metrics.dart';
import 'package:gestao_yahweh/services/admin_diagnostic_service.dart';
import 'package:gestao_yahweh/services/system_health_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/feed_media_publish_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Painel Master / ADM — Firebase, uploads pendentes (global) e filas locais.
class SystemFirebaseHealthPage extends StatefulWidget {
  const SystemFirebaseHealthPage({super.key});

  @override
  State<SystemFirebaseHealthPage> createState() =>
      _SystemFirebaseHealthPageState();
}

class _SystemFirebaseHealthPageState extends State<SystemFirebaseHealthPage>
    with SingleTickerProviderStateMixin {
  FirebaseHealthReport? _report;
  SystemHealthSnapshot? _health;
  AdminDiagnosticSnapshot? _diagnostic;
  QaAssuranceReport? _qaReport;
  bool _qaRunning = false;
  String? _error;
  bool _busy = false;
  String? _tenantId;
  int _chatOutbox = 0;
  int _muralOutbox = 0;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    _tabs.addListener(_onTabChanged);
    _refresh();
    _loadLocalQueues();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging && _tabs.index == 2 && !_qaRunning) {
      unawaited(_runQaSuite());
    }
  }

  Future<void> _runQaSuite() async {
    if (_qaRunning) return;
    setState(() => _qaRunning = true);
    try {
      final report = await QaAssuranceRunner.runAll(tenantIdHint: _tenantId);
      if (!mounted) return;
      setState(() => _qaReport = report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _qaRunning = false);
    }
  }

  Future<void> _loadLocalQueues() async {
    final chat = await ChurchChatMediaOutboxService.pendingJobCount();
    final mural = await MuralPublishOutboxService.pendingJobCount();
    if (!mounted) return;
    setState(() {
      _chatOutbox = chat;
      _muralOutbox = mural;
    });
  }

  Future<void> _resolveTenant() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final t = await PendingUploadsFirestoreService.resolveTenantForCurrentUser();
    if (mounted) setState(() => _tenantId = t);
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _resolveTenant();
    try {
      if (!FirebaseBootstrapService.isReady()) {
        await FirebaseBootstrapService.initialize();
      }
      final h = await FirebaseBootstrapService.healthCheck(
        requireAuthSession: false,
        logLabel: 'admin_health',
      );
      final central = await SystemHealthService.probe(
        tenantIdHint: _tenantId,
        requireAuth: false,
      );
      final diag = await AdminDiagnosticService.load(tenantIdHint: _tenantId);
      if (!mounted) return;
      setState(() {
        _report = h;
        _health = central;
        _diagnostic = diag;
        _busy = false;
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = formatFirebaseErrorForUser(e, stackTrace: st);
        _busy = false;
      });
    }
    await _loadLocalQueues();
  }

  Future<void> _reconnect() async {
    setState(() => _busy = true);
    try {
      await FirebaseBootstrapService.reconnect();
      YahwehMediaUploadPipeline.bindOnAppStart();
      await _refresh();
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _error = formatFirebaseErrorForUser(e, stackTrace: st);
        _busy = false;
      });
    }
  }

  Future<void> _resumeTenantUploads() async {
    final tid = _tenantId?.trim() ?? '';
    if (tid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tenant não identificado para reenvio.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await FeedMediaPublishService.resumePendingUploadsForTenant(tid);
      ChurchChatMediaOutboxService.resumePendingOnAppStart();
      MuralPublishOutboxService.resumePendingOnAppStart();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reenvio de uploads pendente iniciado.')),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _loadLocalQueues();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final memQueue = StorageUploadQueueService.instance.pendingCount;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saúde do Sistema'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Central'),
            Tab(text: 'Diagnóstico'),
            Tab(text: 'Modo QA'),
            Tab(text: 'Métricas'),
            Tab(text: 'Firebase'),
            Tab(text: 'Uploads'),
            Tab(text: 'Filas locais'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Atualizar',
          ),
        ],
      ),
      body: _busy && r == null
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _centralTab(),
                _diagnosticTab(),
                _qaTab(),
                _metricsTab(),
                _firebaseTab(r),
                _uploadsTab(),
                _localQueuesTab(memQueue),
              ],
            ),
    );
  }

  Widget _centralTab() {
    final h = _health;
    final latest = SystemLastErrorRegistry.latest;
    final ready = h?.productionReady ?? false;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: ready ? Colors.green.shade50 : Colors.red.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? 'Modo Produção: LIBERADO' : 'Modo Produção: BLOQUEADO',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: ready ? Colors.green.shade900 : Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  ready
                      ? 'Firebase, Firestore, Storage e filas críticas OK.'
                      : 'Corrija os itens abaixo antes de deploy ou release.',
                  style: TextStyle(color: Colors.grey.shade800),
                ),
                if (h != null && h.blockingReasons.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...h.blockingReasons.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $r', style: TextStyle(color: Colors.red.shade800)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (h != null)
          ...h.checks.map(
            (c) => _StatusTile(
              label: c.label,
              ok: c.ok,
              detail: c.detail,
            ),
          ),
        const SizedBox(height: 16),
        const Text('Último erro', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: latest == null
                ? const Text('Nenhum erro registado nesta sessão.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '[${latest.module}] ${latest.message}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (latest.context != null) ...[
                        const SizedBox(height: 4),
                        Text(latest.context!, style: TextStyle(color: Colors.grey.shade700)),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        latest.at.toLocal().toString(),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Monitoramento', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Crashlytics + Analytics + Performance (traces: dashboard, chat, avisos, '
          'eventos, patrimônio, financeiro, upload, sync).',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 8),
        Text(
          EmergencyModeService.userMessage,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _diagnosticTab() {
    final d = _diagnostic;
    final h = _health;
    final r = _report;
    if (d == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Estado do sistema',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _StatusTile(
          label: 'Firebase OK',
          ok: r?.coreInitialized ?? false,
          detail: r?.coreInitialized == true ? 'Núcleo inicializado' : 'Falha',
        ),
        _StatusTile(
          label: 'Auth OK',
          ok: r?.authOk ?? false,
          detail: r?.authDetail ?? (r?.authOk == true ? 'Sessão OK' : 'Sem sessão'),
        ),
        _StatusTile(
          label: 'Firestore OK',
          ok: r?.firestoreOk ?? false,
          detail: r?.firestoreDetail ?? '',
        ),
        _StatusTile(
          label: 'Storage OK',
          ok: r?.storageOk ?? false,
          detail: r?.storageDetail ?? '',
        ),
        _StatusTile(
          label: 'Sync OK',
          ok: d.pendingSyncCount < 50,
          detail: '${d.pendingSyncCount} tarefa(s) Hive',
        ),
        _StatusTile(
          label: 'Chat OK',
          ok: _checkOk(h, 'Chat'),
          detail: _checkDetail(h, 'Chat'),
        ),
        _StatusTile(
          label: 'Push OK',
          ok: r?.fcmOk ?? false,
          detail: r?.fcmDetail ?? (r?.fcmOk == true ? 'FCM OK' : 'N/A'),
        ),
        _StatusTile(
          label: 'Site Público OK',
          ok: _checkOk(h, 'Site Público'),
          detail: _checkDetail(h, 'Site Público'),
        ),
        const Divider(height: 28),
        const Text(
          'Pendências e histórico',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _StatusTile(
          label: 'Utilizadores online (chat)',
          ok: true,
          detail: '${d.chatOnlineCount} presença(s) activa(s)',
        ),
        _StatusTile(
          label: 'Uploads pendentes',
          ok: d.pendingUploadCount < 15,
          detail: '${d.pendingUploadCount} job(s) local(is)',
        ),
        _StatusTile(
          label: 'Última sincronização',
          ok: true,
          detail: d.lastSyncAt == null
              ? 'Ainda sem cache Hive'
              : d.lastSyncAt!.toLocal().toString(),
        ),
        _StatusTile(
          label: 'Mensagens pendentes (chat)',
          ok: d.pendingChatMessages < 10,
          detail: '${d.pendingChatMessages} (outbox + fila Hive)',
        ),
        _StatusTile(
          label: 'Avisos pendentes',
          ok: d.pendingAvisos < 10,
          detail: '${d.pendingAvisos}',
        ),
        _StatusTile(
          label: 'Eventos pendentes',
          ok: d.pendingEventos < 10,
          detail: '${d.pendingEventos}',
        ),
        _StatusTile(
          label: 'Último backup',
          ok: true,
          detail: d.lastBackupHint,
        ),
        _StatusTile(
          label: 'Health check (5 min)',
          ok: SystemHealthService.lastPeriodicError == null,
          detail: SystemHealthService.lastPeriodicAt == null
              ? 'A aguardar primeiro ciclo…'
              : '${SystemHealthService.lastPeriodicAt!.toLocal()} · '
                  '${SystemHealthService.lastPeriodicSnapshot?.productionReady == true ? 'OK' : 'atenção'}',
        ),
        _StatusTile(
          label: 'Modo emergência',
          ok: !d.emergencyMode,
          detail: EmergencyModeService.userMessage,
        ),
        if (d.degradedServices.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Serviços degradados (app continua)',
              style: TextStyle(fontWeight: FontWeight.w800)),
          ...d.degradedServices.map(
            (e) => _StatusTile(
              label: e.$1.name,
              ok: false,
              detail: e.$2.detail ?? 'Indisponível',
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text('Último erro', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: d.lastError == null
                ? const Text('Nenhum erro nesta sessão.')
                : Text('[${d.lastError!.module}] ${d.lastError!.message}'),
          ),
        ),
      ],
    );
  }

  bool _checkOk(SystemHealthSnapshot? h, String label) {
    if (h == null) return false;
    for (final c in h.checks) {
      if (c.label == label) return c.ok;
    }
    return false;
  }

  String _checkDetail(SystemHealthSnapshot? h, String label) {
    if (h == null) return '—';
    for (final c in h.checks) {
      if (c.label == label) return c.detail;
    }
    return '—';
  }

  Widget _qaTab() {
    final q = _qaReport;
    final platform = MultiplatformQaMatrix.currentPlatform();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Plataforma actual: ${MultiplatformQaMatrix.currentPlatformSummary()}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Release bloqueada se falhar em Android, iOS ou Web. '
                  'Execute os 28 testes QA nas três plataformas antes de cada release.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Padronização multiplataforma',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        const SizedBox(height: 8),
        ...MultiplatformQaMatrix.unifiedModules.map((m) {
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: m.note.isEmpty ? null : Text(m.note, style: const TextStyle(fontSize: 11)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PlatformDot(active: m.sameExperienceOnAndroid, label: 'A'),
                  const SizedBox(width: 4),
                  _PlatformDot(active: m.sameExperienceOnIos, label: 'i'),
                  const SizedBox(width: 4),
                  _PlatformDot(active: m.sameExperienceOnWeb, label: 'W'),
                  const SizedBox(width: 8),
                  Icon(
                    m.requiredOn(platform)
                        ? Icons.edit_note_rounded
                        : Icons.check_rounded,
                    size: 18,
                    color: m.requiredOn(platform)
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Text(
          'Isolamento permitido só: ${MultiplatformQaMatrix.platformIsolatedCapabilities.join(', ')}.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        const Divider(height: 28),
        Card(
          color: q?.productionReady == true
              ? Colors.green.shade50
              : Colors.orange.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo QA — Fase Final de Qualidade',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: q?.productionReady == true
                        ? Colors.green.shade900
                        : Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  q == null
                      ? 'A executar 28 verificações…'
                      : '${q.passCount} OK · ${q.failCount} falha(s) · '
                          '${q.warnCount} aviso(s) · ${q.manualCount} manual(is)',
                  style: TextStyle(color: Colors.grey.shade800),
                ),
                if (q != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Executado: ${q.ranAt.toLocal()}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _qaRunning ? null : _runQaSuite,
          icon: _qaRunning
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded),
          label: Text(_qaRunning ? 'A executar…' : 'Executar 28 testes QA'),
        ),
        const SizedBox(height: 16),
        if (_qaRunning && q == null)
          const Center(child: CircularProgressIndicator())
        else if (q != null)
          ...q.results.map((t) {
            final ok = t.status == QaTestStatus.pass;
            final warn = t.status == QaTestStatus.warn;
            final manual = t.status == QaTestStatus.manual;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  ok
                      ? Icons.check_circle_rounded
                      : manual
                          ? Icons.touch_app_rounded
                          : warn
                              ? Icons.warning_rounded
                              : Icons.cancel_rounded,
                  color: ok
                      ? Colors.green.shade700
                      : manual
                          ? Colors.blue.shade700
                          : warn
                              ? Colors.orange.shade700
                              : Colors.red.shade700,
                ),
                title: Text('${t.id}. ${t.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(t.detail, maxLines: 3, overflow: TextOverflow.ellipsis),
                trailing: t.durationMs != null
                    ? Text('${t.durationMs}ms',
                        style: const TextStyle(fontSize: 11))
                    : null,
              ),
            );
          }),
        const SizedBox(height: 12),
        const Text(
          'Testes marcados como «manual» exigem confirmação no dispositivo '
          '(logout, troca de conta, publicação real). Infraestrutura é verificada automaticamente.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _metricsTab() {
    final metrics = SessionPerformanceMetrics.snapshotWithPlaceholders();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Metas de performance (sessão actual)',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...metrics.map((m) {
          final measured = m.lastMs >= 0;
          final ok = measured && m.meetsTarget;
          return _StatusTile(
            label: m.label,
            ok: !measured || ok,
            detail: measured
                ? '${m.lastMs}ms · meta ${m.targetLabel}'
                : 'Ainda não medido nesta sessão',
          );
        }),
        const SizedBox(height: 16),
        const Text(
          'Metas finais: Dashboard e Painel Master < 1s · Chat/Avisos/Eventos instantâneos · '
          'Upload foto < 3s · sem travamentos · sem perda de dados.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _firebaseTab(FirebaseHealthReport? r) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Versão $appVersionLabel',
            style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        if (_error != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_error!),
            ),
          ),
        if (r != null) ...[
          _StatusTile(
            label: 'Núcleo Firebase',
            ok: r.coreInitialized,
            detail: r.coreInitialized ? 'OK' : 'Não inicializado',
          ),
          _StatusTile(
            label: 'Firebase Auth',
            ok: r.authOk,
            detail: r.authDetail ?? (r.authOk ? 'Sessão OK' : 'Sem sessão'),
          ),
          _StatusTile(
            label: 'Firestore',
            ok: r.firestoreOk,
            detail: r.firestoreDetail ?? (r.firestoreOk ? 'Rede OK' : 'Falha'),
          ),
          _StatusTile(
            label: 'Storage',
            ok: r.storageOk,
            detail: r.storageDetail ?? (r.storageOk ? 'Bucket OK' : 'Falha'),
          ),
          _StatusTile(
            label: 'Cloud Functions',
            ok: r.functionsOk,
            detail:
                r.functionsDetail ?? (r.functionsOk ? 'us-central1' : 'Indisponível'),
          ),
          _StatusTile(
            label: 'FCM (push)',
            ok: r.fcmOk,
            detail: r.fcmDetail ?? (r.fcmOk ? 'OK' : 'N/A ou sem permissão'),
          ),
          const SizedBox(height: 8),
          Text(
            r.canPublishMedia
                ? 'Pronto para publicar mídia (com sessão válida).'
                : r.summaryForUser,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _busy ? null : _reconnect,
          icon: const Icon(Icons.cloud_sync_rounded),
          label: const Text('Reconectar Firebase'),
        ),
      ],
    );
  }

  Widget _uploadsTab() {
    final tid = _tenantId?.trim() ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (tid.isNotEmpty)
          Text(
            'Igreja (tenant): $tid',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 8),
        Text(
          'Coleção global: ${PendingUploadsFirestoreService.globalCollectionId}',
          style: TextStyle(color: ThemeCleanPremium.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _resumeTenantUploads,
          icon: const Icon(Icons.upload_rounded),
          label: const Text('Reenviar uploads pendentes (tenant)'),
        ),
        const SizedBox(height: 16),
        const Text('Índice global', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: PendingUploadsFirestoreService.watchGlobalIndex(
            masterSeeAll: true,
            limit: 30,
          ),
          builder: (context, snap) {
            if (snap.hasError) {
              return Text('Erro: ${snap.error}');
            }
            final docs = snap.data?.docs ?? const [];
            if (docs.isEmpty) {
              return const Text('Nenhum upload pendente no índice global.');
            }
            return Column(
              children: docs.map((d) {
                final data = d.data();
                final st = (data['status'] ?? '').toString();
                final mod = (data['module'] ?? data['type'] ?? '').toString();
                final path = (data['storagePath'] ?? '').toString();
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    title: Text('$mod · $st', maxLines: 1),
                    subtitle: Text(
                      path.isEmpty ? d.id : path,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      (data['tenantId'] ?? '').toString(),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        if (tid.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Por igreja (subcoleção)',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: PendingUploadsFirestoreService.watchOpenForTenant(tid),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? const [];
              if (docs.isEmpty) {
                return const Text('Nenhum job aberto nesta igreja.');
              }
              return Column(
                children: docs.map((d) {
                  final data = d.data();
                  return ListTile(
                    title: Text((data['status'] ?? '').toString()),
                    subtitle: Text((data['storagePath'] ?? '').toString()),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _localQueuesTab(int memQueue) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _QueueCard(
          label: 'Fila em memória (Storage)',
          count: memQueue,
          detail: 'Reprocessa ao voltar online.',
        ),
        _QueueCard(
          label: 'Outbox chat (prefs)',
          count: _chatOutbox,
          detail: 'Mídia do chat interrompida.',
        ),
        _QueueCard(
          label: 'Outbox mural (prefs)',
          count: _muralOutbox,
          detail: 'Avisos/eventos com fotos locais.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _resumeTenantUploads,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Disparar reenvio de todas as filas'),
        ),
      ],
    );
  }
}

class _PlatformDot extends StatelessWidget {
  const _PlatformDot({required this.active, required this.label});

  final bool active;
  final String label;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 11,
      backgroundColor: active ? Colors.green.shade100 : Colors.grey.shade200,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: active ? Colors.green.shade900 : Colors.grey.shade600,
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.label,
    required this.count,
    required this.detail,
  });

  final String label;
  final int count;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: count > 0
              ? Colors.orange.shade100
              : Colors.green.shade100,
          child: Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: count > 0 ? Colors.orange.shade900 : Colors.green.shade800,
            ),
          ),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(detail),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.ok,
    required this.detail,
  });

  final String label;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle_rounded : Icons.error_rounded,
          color: ok ? Colors.green.shade700 : Colors.red.shade700,
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(detail, maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: Text(
          ok ? '🟢 Online' : '🔴 Offline',
          style: TextStyle(
            color: ok ? ThemeCleanPremium.primary : Colors.red.shade700,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
