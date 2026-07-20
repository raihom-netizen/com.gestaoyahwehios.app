import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/global_announcement_overlay.dart'
    show kGlobalAnnouncementLinkifiers, kGlobalAnnouncementLinkifyOptions;

/// Extrai e normaliza URLs no texto do chat (WhatsApp / Telegram).
abstract final class ChurchChatLinkUtils {
  ChurchChatLinkUtils._();

  static final RegExp _urlRe = RegExp(
    r'''((?:https?:\/\/|www\.)[^\s<>"')\]]+)''',
    caseSensitive: false,
  );

  /// Primeira URL encontrada no texto, ou null.
  static String? firstUrl(String text) {
    final m = _urlRe.firstMatch(text.trim());
    if (m == null) return null;
    return normalizeUrl(m.group(0) ?? '');
  }

  /// True se a mensagem é essencialmente um link (com ou sem espaços).
  static bool isPrimarilyLink(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    final url = firstUrl(t);
    if (url == null) return false;
    final stripped = t
        .replaceAll(_urlRe, '')
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    return stripped.isEmpty;
  }

  static String normalizeUrl(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return t;
    while (t.isNotEmpty && '.,;:!?)】」』"\''.contains(t[t.length - 1])) {
      t = t.substring(0, t.length - 1);
    }
    if (!t.contains('://')) {
      t = 'https://$t';
    }
    return t;
  }

  static String displayHost(String url) {
    final u = Uri.tryParse(normalizeUrl(url));
    if (u == null) return url;
    final host = u.host.replaceFirst(RegExp(r'^www\.'), '');
    return host.isEmpty ? url : host;
  }

  static String displayPath(String url) {
    final u = Uri.tryParse(normalizeUrl(url));
    if (u == null) return '';
    final path = u.path;
    if (path.isEmpty || path == '/') return '';
    final q = u.hasQuery ? '?…' : '';
    final full = '$path$q';
    return full.length > 48 ? '${full.substring(0, 45)}…' : full;
  }
}

/// Bolha de texto estilo Telegram/WhatsApp: links clicáveis + cartão de preview.
class ChurchChatTelegramMessageBody extends StatelessWidget {
  const ChurchChatTelegramMessageBody({
    super.key,
    required this.text,
    this.linkUrl,
    this.mine = false,
  });

  final String text;
  final String? linkUrl;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final body = text.trim();
    final explicit = (linkUrl ?? '').trim();
    final primary = explicit.isNotEmpty
        ? ChurchChatLinkUtils.normalizeUrl(explicit)
        : ChurchChatLinkUtils.firstUrl(body);
    final primarilyLink =
        primary != null && ChurchChatLinkUtils.isPrimarilyLink(body);
    final showCard = primary != null && (explicit.isNotEmpty || primarilyLink);

    final textStyle = TextStyle(
      fontSize: 15,
      height: 1.35,
      color: ThemeCleanPremium.onSurface,
    );
    final linkColor =
        mine ? ThemeCleanPremium.primary : const Color(0xFF2563EB);

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showCard && primary != null) ...[
          _TelegramLinkCard(
            url: primary,
            mine: mine,
            onOpen: () => openHttpsUrlInBrowser(context, primary),
          ),
          if (body.isNotEmpty && !primarilyLink) const SizedBox(height: 6),
        ],
        if (body.isNotEmpty && !(showCard && primarilyLink))
          Linkify(
            onOpen: (link) => openHttpsUrlInBrowser(context, link.url),
            text: body,
            style: textStyle,
            linkStyle: textStyle.copyWith(
              color: linkColor,
              decoration: TextDecoration.underline,
              decorationColor: linkColor.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
            options: kGlobalAnnouncementLinkifyOptions,
            linkifiers: kGlobalAnnouncementLinkifiers,
          ),
      ],
    );
  }
}

class _TelegramLinkCard extends StatelessWidget {
  const _TelegramLinkCard({
    required this.url,
    required this.mine,
    required this.onOpen,
  });

  final String url;
  final bool mine;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final host = ChurchChatLinkUtils.displayHost(url);
    final path = ChurchChatLinkUtils.displayPath(url);
    final accent = mine ? ThemeCleanPremium.primary : const Color(0xFF2563EB);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 260,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: accent.withValues(alpha: mine ? 0.10 : 0.07),
            border: Border.all(color: accent.withValues(alpha: 0.22)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(14),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.link_rounded, size: 16, color: accent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                host,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (path.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Abrir link',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: accent.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
