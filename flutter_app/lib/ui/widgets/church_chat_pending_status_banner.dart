import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_stuck_cleanup_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/services/yahweh_media_upload_pipeline.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Faixa no hub/thread do chat: uploads pendentes, outbox local e fila em memória.
class ChurchChatPendingStatusBanner extends StatefulWidget {
  const ChurchChatPendingStatusBanner({
    super.key,
    required this.tenantId,
    this.compact = false,
    this.alwaysOfferClear = false,
    this.role = '',
    this.permissions,
  });

  final String tenantId;
  final bool compact;
  final String role;
  final List<String>? permissions;

  /// Mostra «Limpar» mesmo sem fila visível (mensagens presas só no Firestore).
  final bool alwaysOfferClear;

  @override
  State<ChurchChatPendingStatusBanner> createState() =>
      _ChurchChatPendingStatusBannerState();
}

class _ChurchChatPendingStatusBannerState
    extends State<ChurchChatPendingStatusBanner> {
  int _chatOutbox = 0;
  int _muralOutbox = 0;
  int _memoryQueue = 0;

  @override
  void initState() {
    super.initState();
    _refreshLocalCounts();
  }

  Future<void> _refreshLocalCounts() async {
    final chat = await ChurchChatMediaOutboxService.pendingJobCount();
    final mural = await MuralPublishOutboxService.pendingJobCount();
    final mem = StorageUploadQueueService.instance.pendingCount;
    if (!mounted) return;
    setState(() {
      _chatOutbox = chat;
      _muralOutbox = mural;
      _memoryQueue = mem;
    });
  }

  Future<void> _clearStuckQueue() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      StorageUploadQueueService.instance.clearPending();
      await _refreshLocalCounts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nada pendente para limpar.')),
      );
      return;
    }

    final canWipeAll = AppPermissions.canManageChurchMuralEventsAgenda(
      widget.role,
      permissions: widget.permissions,
    );
    var wipeAllDb = false;
    if (canWipeAll) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Limpar chat'),
          content: const Text(
            'Escolha o que apagar no banco de dados:\n\n'
            '• Envios presos — só mensagens em upload/fila antigas (suas e stubs).\n\n'
            '• Todo o histórico — apaga todas as mensagens do chat da igreja '
            '(conversas ficam vazias; irreversível).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'stuck'),
              child: const Text('Só envios presos'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error,
              ),
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: const Text('Todo o histórico'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      wipeAllDb = choice == 'all';
      if (wipeAllDb) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Apagar todo o chat?'),
            content: const Text(
              'Esta ação remove todas as mensagens de todas as conversas '
              'da igreja no Firestore. Não há como recuperar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Apagar tudo'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
    }

    final result = await ChurchChatStuckCleanupService.purgeAllForTenant(
      tid,
      includeEntireDatabase: wipeAllDb,
      role: widget.role,
      permissions: widget.permissions,
    );
    await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
    await _refreshLocalCounts();
    if (!mounted) return;
    final total = result.messages + result.queueDocs;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          total > 0
              ? 'Limpeza concluída: ${result.messages} mensagem(ns) removida(s) do Firestore '
                  '· ${result.queueDocs} fila(s)/upload(s) apagado(s).'
              : 'Nada pendente para limpar no banco.',
        ),
      ),
    );
  }

  Future<void> _retryAll() async {
    final tid = widget.tenantId.trim();
    var pruned = await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
    if (tid.isNotEmpty) {
      pruned += await PendingUploadsFirestoreService.pruneUnrecoverableOpenForTenant(
        tid,
      );
    }
    if (tid.isNotEmpty) {
      await PendingUploadsFirestoreService.resumeAllForTenant(tid);
    }
    YahwehMediaUploadPipeline.bindOnAppStart();
    ChurchChatMediaOutboxService.resumePendingOnAppStart();
    MuralPublishOutboxService.resumePendingOnAppStart();
    await _refreshLocalCounts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          pruned > 0
              ? 'Reenvio iniciado ($pruned inválidos removidos da fila).'
              : 'Reenvio de uploads pendente iniciado.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: PendingUploadsFirestoreService.watchOpenForTenant(widget.tenantId),
      builder: (context, snap) {
        final firestoreCount = snap.data?.docs.length ?? 0;
        final localExtra = _chatOutbox + _muralOutbox + _memoryQueue;
        final total = firestoreCount + localExtra;
        if (total <= 0 && !widget.alwaysOfferClear) {
          return const SizedBox.shrink();
        }

        final label = total <= 0
            ? (widget.compact
                ? 'Limpar envios antigos presos no banco'
                : 'Remover mensagens de upload antigas (stubs) e filas no Firestore')
            : (widget.compact
                ? '$total envio(s) pendente(s)'
                : 'Há $total upload(s) por concluir (Firestore: $firestoreCount · '
                    'chat: $_chatOutbox · mural: $_muralOutbox · fila: $_memoryQueue)');

        return Material(
          color: const Color(0xFFFFF7ED),
          child: InkWell(
            onTap: _retryAll,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: widget.compact ? 6 : 10,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_upload_rounded,
                    size: widget.compact ? 18 : 22,
                    color: const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: widget.compact ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearStuckQueue,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: Colors.grey.shade700,
                    ),
                    child: const Text('Limpar'),
                  ),
                  TextButton(
                    onPressed: _retryAll,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFFD97706),
                    ),
                    child: const Text('Reenviar'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
