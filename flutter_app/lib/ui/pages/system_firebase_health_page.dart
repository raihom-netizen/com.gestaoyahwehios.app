import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';
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
  String? _error;
  bool _busy = false;
  String? _tenantId;
  int _chatOutbox = 0;
  int _muralOutbox = 0;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _refresh();
    _loadLocalQueues();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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
      if (!mounted) return;
      setState(() {
        _report = h;
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
          tabs: const [
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
                _firebaseTab(r),
                _uploadsTab(),
                _localQueuesTab(memQueue),
              ],
            ),
    );
  }

  Widget _firebaseTab(FirebaseHealthReport? r) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Versão ${appVersionLabel}',
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
