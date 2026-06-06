import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_upload_policy.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_chat_stuck_cleanup_service.dart';
import 'package:gestao_yahweh/services/church_chat_media_outbox_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/storage_upload_queue_service.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Faixa no hub/thread: só envios **recuperáveis** (com ficheiro/bytes no aparelho).
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
  final bool alwaysOfferClear;

  @override
  State<ChurchChatPendingStatusBanner> createState() =>
      _ChurchChatPendingStatusBannerState();
}

class _ChurchChatPendingStatusBannerState
    extends State<ChurchChatPendingStatusBanner> {
  int _recoverableChat = 0;
  int _memoryQueue = 0;
  bool _purgedLegacy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        unawaited(_refreshCounts());
        unawaited(_purgeLegacyOnce());
      });
    });
  }

  Future<void> _purgeLegacyOnce() async {
    if (_purgedLegacy) return;
    _purgedLegacy = true;
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) return;
    try {
      await PendingUploadsFirestoreService.purgeAllLegacyOpenForTenant(tid);
      await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
      await _refreshCounts();
    } catch (_) {}
  }

  Future<void> _refreshCounts() async {
    final tid = widget.tenantId.trim();
    final chat = await ChurchChatMediaOutboxService.recoverablePendingJobCount(
      tenantId: tid.isEmpty ? null : tid,
    );
    final mem = StorageUploadQueueService.instance.pendingCount;
    if (!mounted) return;
    setState(() {
      _recoverableChat = chat;
      _memoryQueue = mem;
    });
  }

  int get _displayTotal => _recoverableChat + _memoryQueue;

  Future<void> _clearStuckQueue() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      await ChurchChatMediaOutboxService.wipeAllLocalJobs();
      StorageUploadQueueService.instance.clearPending();
      await _refreshCounts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fila local limpa.')),
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

    await ChurchChatMediaOutboxService.wipeAllLocalJobs(tenantId: tid);
    StorageUploadQueueService.instance.clearPending();

    final result = await ChurchChatStuckCleanupService.purgeAllForTenant(
      tid,
      includeEntireDatabase: wipeAllDb,
      role: widget.role,
      permissions: widget.permissions,
    );
    await ChurchChatMediaOutboxService.pruneUnrecoverableJobs();
    await _refreshCounts();
    if (!mounted) return;
    final total = result.messages + result.queueDocs;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          total > 0
              ? 'Limpeza concluída: ${result.messages} mensagem(ns) removida(s) · '
                  '${result.queueDocs} registo(s) de fila apagado(s). O contador deve ficar em zero.'
              : 'Nada pendente — fila e envios presos removidos.',
        ),
      ),
    );
  }

  Future<void> _retryAll() async {
    final tid = widget.tenantId.trim();
    if (_recoverableChat <= 0 && _memoryQueue <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não há envios com ficheiro no aparelho para reenviar. '
            'Use Limpar para remover mensagens presas antigas.',
          ),
        ),
      );
      return;
    }
    try {
      await runFirebaseBackgroundTask<void>(
        ChurchChatMediaOutboxService.resumeRecoverableNow,
        debugLabel: 'chat_retry_all',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(formatUploadErrorForUser(e))),
      );
      return;
    }
    var pruned = 0;
    if (tid.isNotEmpty &&
        FirebaseUploadPolicy.firestorePendingQueueEnabled) {
      pruned += await PendingUploadsFirestoreService
          .pruneUnrecoverableOpenForTenant(tid);
      await PendingUploadsFirestoreService.resumeAllForTenant(tid);
    }
    await _refreshCounts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _recoverableChat > 0
              ? 'A reenviar $_recoverableChat ficheiro(s)…'
              : pruned > 0
                  ? 'Fila ajustada ($pruned inválidos removidos).'
                  : 'Reenvio iniciado.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useFirestoreStream =
        FirebaseUploadPolicy.firestorePendingQueueEnabled;

    Widget buildBar(int extraFirestore) {
      final total = _displayTotal + extraFirestore;
      if (total <= 0 && !widget.alwaysOfferClear) {
        return const SizedBox.shrink();
      }

      final label = total <= 0
          ? (widget.compact
              ? 'Limpar envios antigos presos no banco'
              : 'Remover mensagens de upload antigas (stubs) e filas')
          : (widget.compact
              ? '$total envio(s) pendente(s)'
              : '$total envio(s) com ficheiro no aparelho (reenviar agora)');

      return Material(
        color: const Color(0xFFFFF7ED),
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
              if (total > 0)
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
      );
    }

    if (!useFirestoreStream) {
      return buildBar(0);
    }

    return StreamBuilder(
      stream: PendingUploadsFirestoreService.watchOpenForTenant(widget.tenantId),
      builder: (context, snap) {
        final firestoreCount = snap.data?.docs.length ?? 0;
        if (snap.hasData) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshCounts();
          });
        }
        return buildBar(firestoreCount);
      },
    );
  }
}
