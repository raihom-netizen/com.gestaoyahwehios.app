import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Botão clicável para abrir um link social (Instagram/YouTube) — usado no
/// card de Avisos/Eventos (painel inicial, visualizador e site público).
class AvisoEventoSocialLinkButton extends StatelessWidget {
  const AvisoEventoSocialLinkButton({
    super.key,
    required this.url,
    required this.icon,
    required this.label,
    required this.color,
  });

  final String url;
  final IconData icon;
  final String label;
  final Color color;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir $label.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha com os botões Instagram/YouTube disponíveis (só os preenchidos).
/// Reaproveitar em Avisos e Eventos — painel inicial, card e site público.
Widget avisoEventoSocialLinksRow({
  required String? instagramUrl,
  required String? youtubeUrl,
}) {
  final ig = (instagramUrl ?? '').trim();
  final yt = (youtubeUrl ?? '').trim();
  if (ig.isEmpty && yt.isEmpty) return const SizedBox.shrink();
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (ig.isNotEmpty)
        AvisoEventoSocialLinkButton(
          url: ig,
          icon: Icons.camera_alt_rounded,
          label: 'Instagram',
          color: const Color(0xFFE1306C),
        ),
      if (yt.isNotEmpty)
        AvisoEventoSocialLinkButton(
          url: yt,
          icon: Icons.play_circle_fill_rounded,
          label: 'YouTube',
          color: const Color(0xFFFF0000),
        ),
    ],
  );
}
