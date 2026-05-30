import 'package:flutter/material.dart';
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
  });

  final String tenantId;
  final bool compact;

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

  Future<void> _retryAll() async {
    await PendingUploadsFirestoreService.resumeAllForTenant(widget.tenantId);
    YahwehMediaUploadPipeline.bindOnAppStart();
    ChurchChatMediaOutboxService.resumePendingOnAppStart();
    MuralPublishOutboxService.resumePendingOnAppStart();
    await _refreshLocalCounts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reenvio de uploads pendente iniciado.')),
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
        if (total <= 0) return const SizedBox.shrink();

        final label = widget.compact
            ? '$total envio(s) pendente(s)'
            : 'Há $total upload(s) por concluir (Firestore: $firestoreCount · '
                'chat: $_chatOutbox · mural: $_muralOutbox · fila: $_memoryQueue)';

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
