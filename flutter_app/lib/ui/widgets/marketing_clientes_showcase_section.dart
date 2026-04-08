import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/ui_asset_layout_constants.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/marketing_web_lazy_logo_image.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
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

  /// Primeira URL de imagem plausível nos campos usados no CMS / legado.
  static String? primaryImageUrlFromItem(Map<String, dynamic> item) {
    const keys = <String>[
      'fotoUrl',
      'logoUrl',
      'urlLogo',
      'imagemLogo',
      'capaUrl',
      'urlImagem',
      'photoUrl',
      'imagem',
    ];
    for (final k in keys) {
      final u = _plausibleImageUrl((item[k] ?? '').toString());
      if (u != null) return u;
    }
    return null;
  }

  /// WebP opcional (CMS): usado no site web com `<picture>` + fallback JPEG/PNG.
  static String? webpUrlFromItem(Map<String, dynamic> item) {
    const keys = <String>[
      'logoWebpUrl',
      'urlLogoWebp',
      'fotoWebpUrl',
      'capaWebpUrl',
      'webpUrl',
    ];
    for (final k in keys) {
      final u = _plausibleImageUrl((item[k] ?? '').toString());
      if (u != null) return u;
    }
    return null;
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

  /// URL já resolvida para exibir (https / gs / path Storage).
  static bool resolvedUrlLooksUsable(String? u) {
    if (u == null || u.isEmpty) return false;
    final s = sanitizeImageUrl(u);
    return s.isNotEmpty &&
        (isValidImageUrl(s) ||
            s.toLowerCase().startsWith('gs://') ||
            firebaseStorageMediaUrlLooksLike(s));
  }

  /// Capa no site / painel: resolver **primeiro pelo path** no bucket (`fotoPath` / tenant / legado).
  /// Só depois usa `fotoUrl` — a URL no Firestore pode estar expirada enquanto o ficheiro em
  /// `igrejas/.../marketing_destaque/capa.jpg` é válido (evita spinner eterno no web).
  ///
  /// Quando há path **e** URL primária, resolve em **paralelo** (antes eram até ~40s sequenciais
  /// e o card ficava muito tempo só no loading).
  static Future<String?> resolveCapaImageUrl(Map<String, dynamic> item) async {
    final path = MarketingStorageLayout.resolveClienteCapaStoragePath(item);
    final primary = primaryImageUrlFromItem(item);
    final hasPath = path.isNotEmpty;
    final hasPrimary =
        primary != null && resolvedUrlLooksUsable(primary);

    if (hasPath && hasPrimary) {
      final both = await Future.wait<String?>([
        AppStorageImageService.instance.resolveImageUrl(
          storagePath: path,
          imageUrl: null,
        ),
        AppStorageImageService.instance.resolveImageUrl(
          imageUrl: primary,
        ),
      ]);
      final byPath = both[0];
      final byUrl = both[1];
      if (resolvedUrlLooksUsable(byPath)) {
        return sanitizeImageUrl(byPath!);
      }
      if (resolvedUrlLooksUsable(byUrl)) {
        return sanitizeImageUrl(byUrl!);
      }
      return null;
    }
    if (hasPath) {
      final byPath = await AppStorageImageService.instance.resolveImageUrl(
        storagePath: path,
        imageUrl: null,
      );
      if (resolvedUrlLooksUsable(byPath)) {
        return sanitizeImageUrl(byPath!);
      }
    }
    if (hasPrimary) {
      final byUrl = await AppStorageImageService.instance.resolveImageUrl(
        imageUrl: primary,
      );
      if (resolvedUrlLooksUsable(byUrl)) {
        return sanitizeImageUrl(byUrl!);
      }
    }
    return null;
  }
}

/// Miniatura da capa (painel Master) — mesma ordem de resolução que o site público.
class MarketingClienteCapaThumb extends StatefulWidget {
  const MarketingClienteCapaThumb({
    super.key,
    required this.item,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    required this.placeholder,
    required this.errorWidget,
  });

  final Map<String, dynamic> item;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget placeholder;
  final Widget errorWidget;

  @override
  State<MarketingClienteCapaThumb> createState() =>
      _MarketingClienteCapaThumbState();
}

class _MarketingClienteCapaThumbState extends State<MarketingClienteCapaThumb> {
  late Future<String?> _future;
  late String _itemSig;

  static String _itemSigOf(Map<String, dynamic> m) =>
      '${m['id']}_${m['fotoPath']}_${m['fotoUrl']}_${m['igrejaTenantId']}_${m['tenantId']}';

  @override
  void initState() {
    super.initState();
    _itemSig = _itemSigOf(widget.item);
    _future = MarketingClientesShowcaseSection.resolveCapaImageUrl(widget.item);
  }

  @override
  void didUpdateWidget(covariant MarketingClienteCapaThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _itemSigOf(widget.item);
    if (next != _itemSig) {
      _itemSig = next;
      _future =
          MarketingClientesShowcaseSection.resolveCapaImageUrl(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final maxDecode =
        UiAssetLayoutConstants.marketingClientLogoMemCacheWidth(context);
    final logicalW = math.min(
      widget.width,
      UiAssetLayoutConstants.marketingClientLogoLogicalPx,
    );
    final mc = (logicalW * dpr).round().clamp(96, maxDecode);
    Widget core = FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return widget.errorWidget;
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return widget.placeholder;
        }
        final u = snap.data;
        if (!MarketingClientesShowcaseSection.resolvedUrlLooksUsable(u)) {
          return widget.errorWidget;
        }
        return marketingClienteShowcaseImage(
          imageUrl: u!,
          webpUrl: MarketingClientesShowcaseSection.webpUrlFromItem(widget.item),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          memCacheWidth: mc,
          memCacheHeight: mc,
          placeholder: widget.placeholder,
          errorWidget: widget.errorWidget,
        );
      },
    );
    if (widget.borderRadius != null) {
      core = ClipRRect(borderRadius: widget.borderRadius!, child: core);
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: core,
    );
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SectionHeading(
              title: title?.isNotEmpty == true
                  ? title!
                  : 'Igrejas que confiam no Gestão YAHWEH',
              subtitle:
                  'Conheça algumas igrejas que já utilizam o sistema no dia a dia.',
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
            Align(
              alignment: Alignment.center,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: ThemeCleanPremium.spaceLg,
                  crossAxisSpacing: ThemeCleanPremium.spaceLg,
                  childAspectRatio: crossAxisCount == 1 ? 0.88 : 0.70,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final it = shown[i];
                  return _ClienteCard(
                    key: ValueKey<String>(
                      'cli_${it['id']}_${it['igrejaTenantId']}_${it['fotoUrl']}_${it['fotoPath']}',
                    ),
                    item: it,
                  );
                },
              ),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: ThemeCleanPremium.onSurface,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: ThemeCleanPremium.onSurfaceVariant,
              height: 1.45,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

/// Hero da capa: tenta Storage/URL do marketing; se falhar, logo canónica da igreja (`configuracoes/`, legados).
class _ClienteShowcaseHero extends StatefulWidget {
  const _ClienteShowcaseHero({required this.item});

  final Map<String, dynamic> item;

  @override
  State<_ClienteShowcaseHero> createState() => _ClienteShowcaseHeroState();
}

class _ClienteShowcaseHeroState extends State<_ClienteShowcaseHero> {
  late Future<({String url, bool logoContain})> _future;
  String _itemSig = '';

  static String _itemSigOf(Map<String, dynamic> m) =>
      '${m['id']}_${m['igrejaTenantId']}_${m['tenantId']}_${m['fotoPath']}_${m['fotoUrl']}_${m['logoUrl']}_${m['capaUrl']}';

  @override
  void initState() {
    super.initState();
    _itemSig = _itemSigOf(widget.item);
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant _ClienteShowcaseHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _itemSigOf(widget.item);
    if (next != _itemSig) {
      _itemSig = next;
      setState(() => _future = _resolve());
    }
  }

  /// Site divulgação: capa em Storage; se não houver, logo canónica da igreja (Firestore `igrejas/{id}`).
  Future<({String url, bool logoContain})> _resolve() async {
    try {
      // Capa (~20s) + logo tenant (vários resolveImageUrl + getChurchLogo até ~22s) — margem para não cortar URL válida.
      return await _resolveInner().timeout(
        const Duration(seconds: 52),
        onTimeout: () => (url: '', logoContain: false),
      );
    } catch (_) {
      return (url: '', logoContain: false);
    }
  }

  Future<({String url, bool logoContain})> _resolveInner() async {
    final tid = (widget.item['igrejaTenantId'] ?? widget.item['tenantId'] ?? '')
        .toString()
        .trim();

    Future<Map<String, dynamic>?> fetchTenantDoc() async {
      if (tid.isEmpty) return null;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(tid)
            .get()
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () =>
                  throw TimeoutException('igrejas/$tid', const Duration(seconds: 10)),
            );
        if (doc.exists && doc.data() != null) return doc.data();
      } catch (_) {}
      return null;
    }

    final capaAndTenant = await Future.wait<Object?>([
      MarketingClientesShowcaseSection.resolveCapaImageUrl(widget.item),
      fetchTenantDoc(),
    ]);
    final capa = capaAndTenant[0] as String?;
    final tenantData = capaAndTenant[1] as Map<String, dynamic>?;

    if (MarketingClientesShowcaseSection.resolvedUrlLooksUsable(capa)) {
      return (url: capa!, logoContain: false);
    }

    // Fallback logo: preferir campos explícitos de logo (evita `fotoUrl` errado bloquear a logo).
    String? preferForLogo;
    for (final k in <String>['logoUrl', 'urlLogo', 'imagemLogo']) {
      final u = MarketingClientesShowcaseSection._plausibleImageUrl(
        (widget.item[k] ?? '').toString(),
      );
      if (u != null) {
        preferForLogo = u;
        break;
      }
    }
    preferForLogo ??=
        MarketingClientesShowcaseSection.primaryImageUrlFromItem(widget.item);

    if (tid.isNotEmpty) {
      final logo = await AppStorageImageService.instance.resolveChurchTenantLogoUrl(
        tenantId: tid,
        tenantData: tenantData,
        preferImageUrl: preferForLogo,
        preferStoragePath: null,
        preferGsUrl: null,
      );
      if (MarketingClientesShowcaseSection.resolvedUrlLooksUsable(logo)) {
        return (url: sanitizeImageUrl(logo!), logoContain: true);
      }
    }
    return (url: '', logoContain: false);
  }

  @override
  Widget build(BuildContext context) {
    final ph = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8EEF9),
            Color(0xFFF8FAFC),
          ],
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
    final err = Container(
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
        child: Icon(Icons.church_rounded, size: 52, color: Color(0xFF94A3B8)),
      ),
    );

    return AspectRatio(
      aspectRatio: 16 / 10,
      child: FutureBuilder<({String url, bool logoContain})>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return err;
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return ph;
          }
          final data = snap.data;
          if (data == null || data.url.isEmpty) {
            return err;
          }
          final u = data.url;
          final logoMode = data.logoContain;
          final webp = MarketingClientesShowcaseSection.webpUrlFromItem(widget.item);
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: logoMode ? const Color(0xFFF8FAFC) : Colors.black12,
                child: logoMode
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: marketingClienteShowcaseImage(
                          imageUrl: u,
                          webpUrl: webp,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          placeholder: ph,
                          errorWidget: err,
                        ),
                      )
                    : marketingClienteShowcaseImage(
                        imageUrl: u,
                        webpUrl: webp,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: ph,
                        errorWidget: err,
                      ),
              ),
              if (!logoMode)
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
                          Colors.black.withValues(alpha: 0.42),
                        ],
                      ),
                    ),
                    child: const SizedBox(height: 48),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({super.key, required this.item});

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

    final wa = MarketingClientesShowcaseSection._waUrl(whatsapp);
    final siteUri = site.isNotEmpty
        ? MarketingClientesShowcaseSection._httpUrl(site)
        : null;
    final locUri =
        loc.isNotEmpty ? MarketingClientesShowcaseSection._locationLaunchUrl(loc) : null;
    final locHint = MarketingClientesShowcaseSection._locationDisplayHint(loc);

    const radius = ThemeCleanPremium.radiusLg;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.navSidebar.withValues(alpha: 0.10),
              blurRadius: 28,
              offset: const Offset(0, 14),
              spreadRadius: -2,
            ),
            ...YahwehDesignSystem.softCardShadow,
          ],
          border: Border(
            top: BorderSide(
              color: YahwehDesignSystem.brandGold.withValues(alpha: 0.55),
              width: 3,
            ),
            left: const BorderSide(color: Color(0xFFE2E8F0)),
            right: const BorderSide(color: Color(0xFFE2E8F0)),
            bottom: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ClienteShowcaseHero(item: item),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isEmpty ? 'Igreja' : nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.22,
                        letterSpacing: -0.25,
                        color: ThemeCleanPremium.onSurface,
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
