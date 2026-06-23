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

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final color = recording
        ? ThemeCleanPremium.error
        : const Color(0xFF54656F);

    return Transform.translate(
      offset:
          recording ? Offset(slideOffsetDx.clamp(-96.0, 0.0), 0) : Offset.zero,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: kIsWeb ? null : onLongPressStart,
          onLongPressMoveUpdate: kIsWeb ? null : onLongPressMoveUpdate,
          onLongPressEnd: kIsWeb ? null : onLongPressEnd,
          onLongPressCancel: kIsWeb ? null : onLongPressCancel,
          onTap: () {
            if (kIsWeb) {
              onWebTap();
              return;
            }
            if (recording) {
              onTapWhileRecording();
              return;
            }
            // Fallback mobile: alguns aparelhos não disparam long-press de forma estável.
            onWebTap();
          },
          child: SizedBox(
            width: _size,
            height: _size,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: recording
                    ? ThemeCleanPremium.error.withValues(alpha: 0.12)
                    : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Icon(
                recording ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: color,
                size: 26,
              ),
            ),
          ),
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
        gradient: LinearGradient(
          colors: [
            slideCancelArmed
                ? ThemeCleanPremium.error.withValues(alpha: 0.18)
                : const Color(0xFF128C7E).withValues(alpha: 0.10),
            Colors.white,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF128C7E).withValues(alpha: 0.15),
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
