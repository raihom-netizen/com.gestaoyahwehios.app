import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/marketing_official_config.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/whatsapp_channel_icon.dart';
import 'package:url_launcher/url_launcher.dart';

/// Barra de canais oficiais Gestão YAHWEH (site de divulgação, login app).
/// Lê `config/marketing_official` em tempo real; se ausente ou campo vazio, usa [AppConstants].
class YahwehOfficialSocialChannelsBar extends StatelessWidget {
  /// Layout mais baixo (ex.: login nativo).
  final bool compact;

  /// Opcional: analytics / telemetria ao tocar (ex.: `youtube`, `instagram`, `whatsapp`).
  final void Function(String channel)? onChannelTap;

  const YahwehOfficialSocialChannelsBar({
    super.key,
    this.compact = false,
    this.onChannelTap,
  });

  static Future<void> _open(Uri? uri) async {
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) await launchUrl(uri, mode: LaunchMode.platformDefault);
  }

  static Uri? _youtubeUriFrom(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final s = t.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? t
        : 'https://$t';
    return Uri.tryParse(s);
  }

  static Uri? _instagramUriFrom(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final s = t.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? t
        : 'https://$t';
    return Uri.tryParse(s);
  }

  static Uri? _whatsappUriFrom(String raw) {
    if (raw.isEmpty) return null;
    if (raw.contains('wa.me') ||
        raw.contains('api.whatsapp.com') ||
        raw.startsWith('http')) {
      final u = raw.startsWith('http') ? raw : 'https://$raw';
      return Uri.tryParse(u);
    }
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    return Uri.parse('https://wa.me/$digits');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .doc(MarketingOfficialConfig.firestoreDocPath)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final instagram =
            MarketingOfficialConfig.effectiveInstagramUrl(data);
        final youtube = MarketingOfficialConfig.effectiveYoutubeUrl(data);
        final whatsappRaw =
            MarketingOfficialConfig.effectiveWhatsAppRaw(data);
        final contactName =
            MarketingOfficialConfig.effectiveContactName(data);

        final pad = compact ? 12.0 : 16.0;
        final iconBox = compact ? 36.0 : 42.0;
        final faSize = compact ? 16.0 : 18.0;

        // YouTube/Instagram/WhatsApp: sem FA Brands na web (glifos em falta).
        final items = <({
          String id,
          String label,
          String hint,
          Widget icon,
          List<Color> gradient,
          Uri? uri,
        })>[];

        final y = _youtubeUriFrom(youtube);
        if (y != null) {
          items.add((
            id: 'youtube',
            label: 'YouTube',
            hint: 'Canal oficial',
            icon: Icon(
              Icons.play_circle_filled_rounded,
              color: Colors.white,
              size: faSize,
            ),
            gradient: const [Color(0xFFFF0000), Color(0xFFB20710)],
            uri: y,
          ));
        }
        final i = _instagramUriFrom(instagram);
        if (i != null) {
          items.add((
            id: 'instagram',
            label: 'Instagram',
            hint: 'Novidades',
            icon: Icon(
              Icons.photo_camera_rounded,
              color: Colors.white,
              size: faSize,
            ),
            gradient: const [Color(0xFFE4405F), Color(0xFF833AB4)],
            uri: i,
          ));
        }
        final w = _whatsappUriFrom(whatsappRaw);
        if (w != null) {
          items.add((
            id: 'whatsapp',
            label: 'WhatsApp',
            hint: 'Fale conosco',
            icon: WhatsappChannelIcon(size: faSize),
            gradient: const [Color(0xFF25D366), Color(0xFF128C7E)],
            uri: w,
          ));
        }

        if (items.isEmpty) return const SizedBox.shrink();

        final titleText = contactName.isEmpty
            ? 'Canais oficiais Gestão YAHWEH'
            : 'Canais oficiais — $contactName';

        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  ThemeCleanPremium.primary.withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: compact ? 18 : 20,
                      color: ThemeCleanPremium.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titleText,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 13.5 : 14.5,
                          letterSpacing: -0.35,
                          color: ThemeCleanPremium.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 10 : 12),
                LayoutBuilder(
                  builder: (context, c) {
                    final narrow = c.maxWidth < 380;
                    return Wrap(
                      spacing: narrow ? 8 : 10,
                      runSpacing: narrow ? 8 : 10,
                      alignment: WrapAlignment.start,
                      children: items.map((it) {
                        return _ChannelPill(
                          label: it.label,
                          hint: it.hint,
                          icon: it.icon,
                          gradient: it.gradient,
                          iconBox: iconBox,
                          compact: compact,
                          onTap: () {
                            onChannelTap?.call(it.id);
                            _open(it.uri);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ChannelPill extends StatelessWidget {
  final String label;
  final String hint;
  final Widget icon;
  final List<Color> gradient;
  final double iconBox;
  final bool compact;
  final VoidCallback onTap;

  const _ChannelPill({
    required this.label,
    required this.hint,
    required this.icon,
    required this.gradient,
    required this.iconBox,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 12,
              vertical: compact ? 8 : 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: iconBox,
                  height: iconBox,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: gradient.last.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: icon,
                ),
                SizedBox(width: compact ? 8 : 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 12.5 : 13.5,
                        letterSpacing: -0.2,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: compact ? 10.5 : 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.open_in_new_rounded,
                  size: compact ? 14 : 15,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
