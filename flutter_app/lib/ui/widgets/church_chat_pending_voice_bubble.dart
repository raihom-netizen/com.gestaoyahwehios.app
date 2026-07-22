import 'dart:async' show unawaited;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Bolha local de voz (enviando) — preview local com [audioplayers].
/// Estilo WhatsApp: sem «A enviar áudio… X%» — só duração + relógio discreto.
class ChurchChatPendingVoiceBubble extends StatefulWidget {
  const ChurchChatPendingVoiceBubble({
    super.key,
    required this.progressListenable,
    required this.failed,
    this.offlineQueued = false,
    this.localPath,
    this.errorMessage,
    this.durationMs,
    this.fileName,
  });

  final ValueListenable<double> progressListenable;
  final bool failed;
  final bool offlineQueued;
  final String? localPath;
  final String? errorMessage;
  final int? durationMs;
  final String? fileName;

  @override
  State<ChurchChatPendingVoiceBubble> createState() =>
      _ChurchChatPendingVoiceBubbleState();
}

class _ChurchChatPendingVoiceBubbleState
    extends State<ChurchChatPendingVoiceBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '0:00';
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _toggleLocalPreview() async {
    if (kIsWeb) return;
    final path = widget.localPath?.trim() ?? '';
    if (path.isEmpty || widget.failed) return;
    try {
      if (_playing) {
        await _player.stop();
        if (mounted) setState(() => _playing = false);
        return;
      }
      await _player.play(DeviceFileSource(path));
      if (mounted) setState(() => _playing = true);
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPreview =
        (widget.localPath?.trim().isNotEmpty ?? false) && !widget.failed;
    return ValueListenableBuilder<double>(
      valueListenable: widget.progressListenable,
      builder: (context, progress, _) {
        final sending =
            !widget.failed && !widget.offlineQueued && progress < 1;
        final title = (widget.fileName ?? '').trim().isNotEmpty
            ? widget.fileName!.trim()
            : 'Áudio';
        final statusText = widget.failed
            ? (widget.errorMessage ?? 'Falha no envio')
            : (widget.offlineQueued
                ? 'Na fila — envia ao voltar online'
                : _formatDuration(widget.durationMs));
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: canPreview ? _toggleLocalPreview : null,
                borderRadius: BorderRadius.circular(20),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: widget.failed
                      ? ThemeCleanPremium.error.withValues(alpha: 0.15)
                      : const Color(0xFF128C7E).withValues(alpha: 0.18),
                  child: Icon(
                    widget.failed
                        ? Icons.error_outline_rounded
                        : (_playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                    size: 22,
                    color: widget.failed
                        ? ThemeCleanPremium.error
                        : const Color(0xFF128C7E),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.failed
                            ? ThemeCleanPremium.error
                            : Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    if (sending) ...[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.access_time_rounded,
                        size: 12,
                        color: Colors.black.withValues(alpha: 0.4),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
