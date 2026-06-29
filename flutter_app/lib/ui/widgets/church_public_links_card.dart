import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:share_plus/share_plus.dart';

/// Card moderno (padrão WISDOMAPP) — links públicos da igreja.
class ChurchPublicLinksCard extends StatelessWidget {
  const ChurchPublicLinksCard({
    super.key,
    required this.slug,
    this.compact = false,
    this.onOpenSite,
    this.onOpenCadastro,
    this.onCopied,
  });

  final String slug;
  final bool compact;
  final VoidCallback? onOpenSite;
  final VoidCallback? onOpenCadastro;
  final VoidCallback? onCopied;

  static String siteUrlForSlug(String slug) {
    final s = slug.trim();
    if (s.isEmpty) return AppConstants.publicWebBaseUrl;
    return '${AppConstants.publicWebBaseUrl}/igreja/${Uri.encodeComponent(s)}';
  }

  static String signupUrlForSlug(String slug) {
    final s = slug.trim();
    if (s.isEmpty) return AppConstants.publicWebBaseUrl;
    return AppConstants.publicChurchMemberSignupUrl(s);
  }

  void _copy(BuildContext context, String url) {
    Clipboard.setData(ClipboardData(text: url));
    onCopied?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar('Link copiado!'),
    );
  }

  void _share(String url, String label) {
    Share.share('$label\n$url', subject: label);
  }

  @override
  Widget build(BuildContext context) {
    final siteUrl = siteUrlForSlug(slug);
    final cadUrl = signupUrlForSlug(slug);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B4B).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFF0B1B4B).withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 16,
              compact ? 12 : 16,
              compact ? 12 : 16,
              compact ? 12 : 14,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B1B4B), Color(0xFF134074), Color(0xFF0D9488)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.public_rounded,
                    color: Colors.amber.shade200,
                    size: compact ? 22 : 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Seus links públicos',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 15 : 17,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Divulgue o site e o cadastro de membros',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                          fontSize: compact ? 11 : 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 12,
              compact ? 10 : 12,
              compact ? 10 : 12,
              compact ? 12 : 14,
            ),
            child: Column(
              children: [
                _LinkTile(
                  title: 'Site público',
                  subtitle: 'Eventos e informações da igreja',
                  url: siteUrl,
                  icon: Icons.language_rounded,
                  colors: const [Color(0xFF0EA5E9), Color(0xFF2563EB)],
                  compact: compact,
                  onTap: onOpenSite,
                  onCopy: () => _copy(context, siteUrl),
                  onShare: () => _share(siteUrl, 'Site da igreja'),
                ),
                SizedBox(height: compact ? 8 : 10),
                _LinkTile(
                  title: 'Cadastro de membros',
                  subtitle: 'Link público para novos membros',
                  url: cadUrl,
                  icon: Icons.person_add_alt_1_rounded,
                  colors: const [Color(0xFF10B981), Color(0xFF059669)],
                  compact: compact,
                  onTap: onOpenCadastro,
                  onCopy: () => _copy(context, cadUrl),
                  onShare: () => _share(cadUrl, 'Cadastro de membro'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.icon,
    required this.colors,
    required this.compact,
    this.onTap,
    required this.onCopy,
    required this.onShare,
  });

  final String title;
  final String subtitle;
  final String url;
  final IconData icon;
  final List<Color> colors;
  final bool compact;
  final VoidCallback? onTap;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          padding: EdgeInsets.all(compact ? 10 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: compact ? 40 : 46,
                height: compact ? 40 : 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: compact ? 20 : 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 13 : 15,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      url,
                      maxLines: 2,
                      style: TextStyle(
                        fontSize: compact ? 10 : 11,
                        color: const Color(0xFF475569),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  _MiniAction(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'Abrir',
                    color: colors.last,
                    onTap: onTap,
                  ),
                  const SizedBox(height: 4),
                  _MiniAction(
                    icon: Icons.copy_rounded,
                    tooltip: 'Copiar',
                    color: const Color(0xFF64748B),
                    onTap: onCopy,
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 4),
                    _MiniAction(
                      icon: Icons.share_rounded,
                      tooltip: 'Compartilhar',
                      color: const Color(0xFF64748B),
                      onTap: onShare,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// Skeleton leve enquanto o slug carrega.
class ChurchPublicLinksSkeleton extends StatelessWidget {
  const ChurchPublicLinksSkeleton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 140 : 168,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 18 : 20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Carregando links públicos…',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
