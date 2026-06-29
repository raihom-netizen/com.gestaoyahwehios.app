import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/global_upload_progress.dart';

/// Faixa flutuante estilo WhatsApp — «A enviar imagem… 82%» em qualquer ecrã.
class WhatsAppUploadProgressOverlay extends StatelessWidget {
  const WhatsAppUploadProgressOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        ValueListenableBuilder<GlobalUploadProgressState?>(
          valueListenable: GlobalUploadProgress.instance.state,
          builder: (context, state, _) {
            if (state == null) return const SizedBox.shrink();
            final pct = (state.progress * 100).round().clamp(0, 100);
            final isAudio = state.label.toLowerCase().contains('áudio') ||
                state.label.toLowerCase().contains('audio');
            final isImage = state.label.toLowerCase().contains('foto') ||
                state.label.toLowerCase().contains('imagem') ||
                state.label.toLowerCase().contains('capa');
            final icon = isAudio
                ? Icons.mic_rounded
                : isImage
                    ? Icons.image_rounded
                    : Icons.cloud_upload_rounded;
            return Positioned(
              left: 12,
              right: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 72,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFFD9FDD3),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366).withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, color: const Color(0xFF128C7E), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.displayLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF111B21),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: state.progress > 0
                                    ? state.progress.clamp(0.05, 1.0)
                                    : null,
                                minHeight: 5,
                                backgroundColor:
                                    const Color(0xFF128C7E).withValues(alpha: 0.15),
                                color: const Color(0xFF25D366),
                              ),
                            ),
                            if (pct > 0 && pct < 100) ...[
                              const SizedBox(height: 4),
                              Text(
                                '$pct%',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
