import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show FreshFirebaseStorageImage;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show YahwehPremiumFeedShimmer;

/// Detalhe de culto/evento — mesmo padrão visual do site público (bottom sheet).
class ChurchPublicEventDetailSheet extends StatelessWidget {
  final String title;
  /// Texto livre (ex. legado) quando não há [weekdayLabel]/[dateLabel]/[timeLabel].
  final String subtitle;
  final String body;
  final String imageUrl;
  final String videoUrl;
  /// Path no Storage (quando disponível) para carregar com o pipeline do painel.
  final String? photoStoragePath;
  final Color accentColor;
  /// Dia da semana (ex. Dom ou Domingo).
  final String? weekdayLabel;
  /// Data (ex. 12/04/2026).
  final String? dateLabel;
  /// Horário (ex. 09:00), sem prefixo "às".
  final String? timeLabel;
  /// Endereço / local (linha própria com ícone).
  final String? locationLine;

  const ChurchPublicEventDetailSheet({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.body,
    required this.imageUrl,
    required this.videoUrl,
    this.photoStoragePath,
    this.accentColor = const Color(0xFF2563EB),
    this.weekdayLabel,
    this.dateLabel,
    this.timeLabel,
    this.locationLine,
  });

  bool get _hasStructuredSchedule {
    final w = weekdayLabel?.trim() ?? '';
    final d = dateLabel?.trim() ?? '';
    final t = timeLabel?.trim() ?? '';
    final l = locationLine?.trim() ?? '';
    return w.isNotEmpty || d.isNotEmpty || t.isNotEmpty || l.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final img = imageUrl.trim();
    final vid = videoUrl.trim();
    final mediaUrl = img.isNotEmpty ? img : vid;
    final path = photoStoragePath?.trim() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(ThemeCleanPremium.radiusLg),
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_back_rounded, size: 20, color: accentColor),
                    label: Text(
                      'Voltar',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: accentColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      foregroundColor: accentColor,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor.withValues(alpha: 0.14),
                        Colors.white,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.28),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'CULTO / EVENTO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.event_available_rounded,
                            color: accentColor,
                            size: 22,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_hasStructuredSchedule) ...[
                        if ((weekdayLabel ?? '').trim().isNotEmpty ||
                            (dateLabel ?? '').trim().isNotEmpty)
                          _ScheduleLine(
                            icon: Icons.calendar_today_rounded,
                            accent: accentColor,
                            text: [
                              if ((weekdayLabel ?? '').trim().isNotEmpty)
                                weekdayLabel!.trim(),
                              if ((dateLabel ?? '').trim().isNotEmpty)
                                dateLabel!.trim(),
                            ].join(' · '),
                          ),
                        if ((timeLabel ?? '').trim().isNotEmpty) ...[
                          if ((weekdayLabel ?? '').trim().isNotEmpty ||
                              (dateLabel ?? '').trim().isNotEmpty)
                            const SizedBox(height: 6),
                          _ScheduleLine(
                            icon: Icons.schedule_rounded,
                            accent: accentColor,
                            text: 'às ${timeLabel!.trim()}',
                          ),
                        ],
                        if ((locationLine ?? '').trim().isNotEmpty) ...[
                          if ((weekdayLabel ?? '').trim().isNotEmpty ||
                              (dateLabel ?? '').trim().isNotEmpty ||
                              (timeLabel ?? '').trim().isNotEmpty)
                            const SizedBox(height: 6),
                          _ScheduleLine(
                            icon: Icons.place_outlined,
                            accent: accentColor,
                            text: locationLine!.trim(),
                          ),
                        ],
                      ] else if (subtitle.trim().isNotEmpty)
                        Text(
                          subtitle.trim(),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
                if (path.isNotEmpty || mediaUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(
                        maxWidth: 248,
                        maxHeight: 156,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.22),
                        ),
                        boxShadow: ThemeCleanPremium.softUiCardShadow,
                      ),
                      padding: const EdgeInsets.all(10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          ThemeCleanPremium.radiusSm,
                        ),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: path.isNotEmpty
                              ? StableStorageImage(
                                  storagePath: path,
                                  imageUrl: img.isNotEmpty ? img : null,
                                  width: 480,
                                  height: 360,
                                  fit: BoxFit.contain,
                                  memCacheWidth: 480,
                                  memCacheHeight: 360,
                                  skipFreshDisplayUrl: false,
                                  placeholder:
                                      YahwehPremiumFeedShimmer.mediaCover(),
                                  errorWidget: Container(
                                    color: const Color(0xFFF3F4F6),
                                  ),
                                )
                              : FreshFirebaseStorageImage(
                                  imageUrl: mediaUrl,
                                  fit: BoxFit.contain,
                                  placeholder:
                                      YahwehPremiumFeedShimmer.mediaCover(),
                                  errorWidget: Container(
                                    color: const Color(0xFFF3F4F6),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(body, style: const TextStyle(height: 1.4)),
                ],
                if (vid.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(vid),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: const Text('Assistir vídeo'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScheduleLine extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String text;

  const _ScheduleLine({
    required this.icon,
    required this.accent,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Colors.grey.shade800,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}
