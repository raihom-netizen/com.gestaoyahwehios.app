import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:url_launcher/url_launcher.dart';

/// Destaque público: igrejas que usam o Gestão YAHWEH (`app_public/marketing_clientes`).
class MarketingClientesShowcaseSection extends StatefulWidget {
  const MarketingClientesShowcaseSection({super.key});

  /// Quantas igrejas mostrar antes de «Veja mais».
  static const int publicPreviewCount = 3;

  @override
  State<MarketingClientesShowcaseSection> createState() =>
      _MarketingClientesShowcaseSectionState();

  static DocumentReference<Map<String, dynamic>> get _docRef =>
      FirebaseFirestore.instance
          .collection(MarketingStorageLayout.firestoreCollection)
          .doc(MarketingStorageLayout.firestoreMarketingClientesDocId);

  static List<Map<String, dynamic>> _parseItems(Map<String, dynamic>? data) {
    final raw = data?['items'];
    if (raw is! List) return [];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) => m['ativo'] != false)
        .toList()
      ..sort((a, b) {
        final oa = (a['ordem'] is num) ? (a['ordem'] as num).toInt() : 0;
        final ob = (b['ordem'] is num) ? (b['ordem'] as num).toInt() : 0;
        return oa.compareTo(ob);
      });
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String? _waUrl(String whatsappRaw) {
    var d = _digits(whatsappRaw);
    if (d.isEmpty) return null;
    if (d.length <= 11 && !d.startsWith('55')) d = '55$d';
    return 'https://wa.me/$d';
  }

  static String? _httpUrl(String site) {
    final t = site.trim();
    if (t.isEmpty) return null;
    if (t.startsWith('http://') || t.startsWith('https://')) return t;
    return 'https://$t';
  }

  static String? _plausibleImageUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final low = t.toLowerCase();
    if (low.startsWith('mailto:') || low.startsWith('tel:')) return null;
    if (low.contains('maps.google') ||
        low.contains('google.com/maps') ||
        low.contains('maps.app.goo.gl') ||
        low.contains('goo.gl/maps')) {
      return null;
    }
    if (low.contains('wa.me') || low.contains('whatsapp.com')) return null;
    return t;
  }

  static String? _locationLaunchUrl(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final low = t.toLowerCase();
    if (low.startsWith('http://') || low.startsWith('https://')) {
      return t;
    }
    if ((low.contains('google.') && low.contains('maps')) ||
        low.contains('maps.app.goo.gl') ||
        low.startsWith('goo.gl/')) {
      return 'https://$t';
    }
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(t)}';
  }

  static String? _locationDisplayHint(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    final low = t.toLowerCase();
    final isUrl = low.startsWith('http://') ||
        low.startsWith('https://') ||
        (low.contains('google.') && low.contains('maps')) ||
        low.contains('maps.app.goo.gl') ||
        low.startsWith('goo.gl/');
    if (isUrl) {
      try {
        final u = Uri.parse(t.startsWith('http') ? t : 'https://$t');
        final q = u.queryParameters['query'] ?? u.queryParameters['q'];
        if (q != null && q.isNotEmpty) {
          return Uri.decodeComponent(q.replaceAll('+', ' '));
        }
      } catch (_) {}
      return null;
    }
    if (t.length > 120) return '${t.substring(0, 117)}…';
    return t;
  }
}

class _MarketingClientesShowcaseSectionState
    extends State<MarketingClientesShowcaseSection> {
  bool _showAllClientes = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: MarketingClientesShowcaseSection._docRef.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(ThemeCleanPremium.spaceXl),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final data = snap.data?.data();
        final items = MarketingClientesShowcaseSection._parseItems(data);
        if (items.isEmpty) return const SizedBox.shrink();

        final title = (data?['sectionTitle'] as String?)?.trim();
        final w = MediaQuery.sizeOf(context).width;
        final crossAxisCount = w >= 1100
            ? 3
            : w >= 700
                ? 2
                : 1;

        final cap = MarketingClientesShowcaseSection.publicPreviewCount;
        final expanded = _showAllClientes;
        final shown = (!expanded && items.length > cap)
            ? items.take(cap).toList()
            : items;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeading(
              title: title?.isNotEmpty == true
                  ? title!
                  : 'Igrejas que confiam no Gestão YAHWEH',
              subtitle:
                  'Conheça algumas igrejas que já utilizam o sistema no dia a dia.',
            ),
            const SizedBox(height: ThemeCleanPremium.spaceMd),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: ThemeCleanPremium.spaceMd,
                crossAxisSpacing: ThemeCleanPremium.spaceMd,
                childAspectRatio: crossAxisCount == 1 ? 0.95 : 0.72,
              ),
              itemCount: shown.length,
              itemBuilder: (context, i) => _ClienteCard(item: shown[i]),
            ),
            if (items.length > cap) ...[
              const SizedBox(height: ThemeCleanPremium.spaceMd),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      setState(() => _showAllClientes = !_showAllClientes),
                  icon: Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 22,
                  ),
                  label: Text(expanded ? 'Ver menos' : 'Veja mais'),
                  style: FilledButton.styleFrom(
                    foregroundColor: const Color(0xFF0A3D91),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.onSurface,
                letterSpacing: -0.4,
                height: 1.15,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: ThemeCleanPremium.onSurfaceVariant,
                height: 1.4,
                fontSize: 15,
              ),
        ),
      ],
    );
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({required this.item});

  final Map<String, dynamic> item;

  String _str(String key) => (item[key] ?? '').toString().trim();

  Future<void> _openExternal(String url) async {
    final u = Uri.parse(url);
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome = _str('nomeIgreja');
    final pastor = _str('pastor');
    final gestor = _str('gestor');
    final loc = _str('localizacao');
    final whatsapp = _str('whatsapp');
    final site = _str('sitePublico');
    final fotoUrlRaw = _str('fotoUrl');
    final fotoUrl =
        MarketingClientesShowcaseSection._plausibleImageUrl(fotoUrlRaw);
    final resolvedPath = MarketingStorageLayout.resolveClienteCapaStoragePath(item);

    final wa = MarketingClientesShowcaseSection._waUrl(whatsapp);
    final siteUri = site.isNotEmpty
        ? MarketingClientesShowcaseSection._httpUrl(site)
        : null;
    final locUri =
        loc.isNotEmpty ? MarketingClientesShowcaseSection._locationLaunchUrl(loc) : null;
    final locHint = MarketingClientesShowcaseSection._locationDisplayHint(loc);

    const radius = 20.0;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0A3D91).withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            ...ThemeCleanPremium.softUiCardShadow,
          ],
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StableStorageImage(
                    storagePath: resolvedPath,
                    imageUrl: fotoUrl,
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.zero,
                    placeholder: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFE8EEF9),
                            Color(0xFFF1F5F9),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.church_rounded,
                            size: 52, color: Color(0xFF94A3B8)),
                      ),
                    ),
                    errorWidget: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFFE8EEF9),
                            Color(0xFFF1F5F9),
                          ],
                        ),
                      ),
                      child: const Center(
                        child: Icon(Icons.image_not_supported_outlined,
                            size: 44, color: Color(0xFF94A3B8)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                          ],
                        ),
                      ),
                      child: const SizedBox(height: 48),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isEmpty ? 'Igreja' : nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -0.2,
                          ),
                    ),
                    if (pastor.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _InfoRow(
                        icon: Icons.person_outline_rounded,
                        label: 'Pastor',
                        value: pastor,
                      ),
                    ],
                    if (gestor.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _InfoRow(
                        icon: Icons.manage_accounts_outlined,
                        label: 'Gestor',
                        value: gestor,
                      ),
                    ],
                    if (locHint != null && locHint.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.place_outlined,
                              size: 17, color: ThemeCleanPremium.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              locHint,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: ThemeCleanPremium.onSurfaceVariant,
                                    height: 1.3,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    _ClienteActionRow(
                      wa: wa,
                      siteUri: siteUri,
                      locUri: locUri,
                      onOpen: _openExternal,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClienteActionRow extends StatelessWidget {
  const _ClienteActionRow({
    required this.wa,
    required this.siteUri,
    required this.locUri,
    required this.onOpen,
  });

  final String? wa;
  final String? siteUri;
  final String? locUri;
  final Future<void> Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final actions = <({String url, String label, IconData icon, Color color})>[];
    if (wa != null) {
      actions.add((
        url: wa!,
        label: 'WhatsApp',
        icon: Icons.chat_rounded,
        color: const Color(0xFF25D366),
      ));
    }
    if (siteUri != null) {
      actions.add((
        url: siteUri!,
        label: 'Site',
        icon: Icons.language_rounded,
        color: ThemeCleanPremium.primary,
      ));
    }
    if (locUri != null) {
      actions.add((
        url: locUri!,
        label: 'Localização',
        icon: Icons.map_outlined,
        color: const Color(0xFFEA580C),
      ));
    }
    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        final useRow = c.maxWidth >= 280 && actions.length <= 3;
        if (useRow) {
          return Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _ClienteActionButton(
                    label: actions[i].label,
                    icon: actions[i].icon,
                    color: actions[i].color,
                    onTap: () => onOpen(actions[i].url),
                  ),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _ClienteActionButton(
                label: actions[i].label,
                icon: actions[i].icon,
                color: actions[i].color,
                onTap: () => onOpen(actions[i].url),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ClienteActionButton extends StatelessWidget {
  const _ClienteActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color.withValues(alpha: 0.95),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: ThemeCleanPremium.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: $value',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: ThemeCleanPremium.onSurfaceVariant,
                  height: 1.25,
                ),
          ),
        ),
      ],
    );
  }
}
