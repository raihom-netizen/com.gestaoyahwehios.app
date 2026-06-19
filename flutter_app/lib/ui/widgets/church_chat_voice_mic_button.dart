import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Botão microfone estilo WhatsApp — segure para gravar, deslize ← para cancelar.
class ChurchChatVoiceMicButton extends StatelessWidget {
  const ChurchChatVoiceMicButton({
    super.key,
    required this.recording,
    required this.slideCancelArmed,
    required this.slideOffsetDx,
    required this.onWebTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
    required this.onLongPressEnd,
    required this.onLongPressCancel,
    required this.onTapWhileRecording,
  });

  final bool recording;
  final bool slideCancelArmed;
  final double slideOffsetDx;
  final VoidCallback onWebTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;
  final VoidCallback onTapWhileRecording;

  @override
  Widget build(BuildContext context) {
    final color = recording
        ? ThemeCleanPremium.error
        : ThemeCleanPremium.onSurfaceVariant;

    return Transform.translate(
      offset:
          recording ? Offset(slideOffsetDx.clamp(-96.0, 0.0), 0) : Offset.zero,
      child: GestureDetector(
        onLongPressStart: onLongPressStart,
        onLongPressMoveUpdate: onLongPressMoveUpdate,
        onLongPressEnd: onLongPressEnd,
        onLongPressCancel: onLongPressCancel,
        child: IconButton(
          onPressed: () {
            if (kIsWeb) {
              onWebTap();
              return;
            }
            if (recording) {
              onTapWhileRecording();
            }
          },
          icon: Icon(Icons.mic_rounded, color: color),
          tooltip: recording
              ? (kIsWeb
                  ? 'Toque para enviar'
                  : 'Solte para enviar · deslize ← p/ cancelar')
              : (kIsWeb
                  ? 'Toque para gravar voz'
                  : 'Segure para gravar · deslize ← p/ cancelar'),
        ),
      ),
    );
  }
}

/// Faixa superior durante gravação — timer + hint deslize p/ cancelar.
class ChurchChatVoiceRecordingBar extends StatelessWidget {
  const ChurchChatVoiceRecordingBar({
    super.key,
    required this.elapsedLabel,
    required this.slideCancelArmed,
    required this.onCancel,
    required this.onSend,
  });

  final String elapsedLabel;
  final bool slideCancelArmed;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: slideCancelArmed
            ? ThemeCleanPremium.error.withValues(alpha: 0.14)
            : ThemeCleanPremium.error.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text(
              'Cancelar',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: ThemeCleanPremium.error,
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: onSend,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Enviar'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF128C7E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  slideCancelArmed
                      ? Icons.cancel_rounded
                      : Icons.fiber_manual_record_rounded,
                  size: 14,
                  color: ThemeCleanPremium.error,
                ),
                const SizedBox(width: 8),
                Text(
                  elapsedLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Text(
              slideCancelArmed
                  ? 'Solte para cancelar'
                  : (kIsWeb
                      ? 'Toque em Enviar'
                      : 'Solte p/ enviar · deslize ← p/ cancelar'),
              maxLines: 2,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 10,
                fontWeight: slideCancelArmed ? FontWeight.w800 : FontWeight.w500,
                color: slideCancelArmed
                    ? ThemeCleanPremium.error
                    : ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
