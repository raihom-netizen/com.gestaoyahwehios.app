import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/core/marketing_storage_layout.dart';
import 'package:gestao_yahweh/core/church_panel_tenant_gateway.dart';
import 'package:gestao_yahweh/core/ui_asset_layout_constants.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/yahweh_media_cache_bust.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/marketing_web_lazy_logo_image.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/services/marketing_clientes_load_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';

/// Markdown mínimo (sem dependência): `**negrito**`, `*itálico*` ou `_itálico_`.
List<InlineSpan> lightMarkdownInlineSpans(String input, TextStyle base) {
  final italicMerge = base.merge(const TextStyle(fontStyle: FontStyle.italic));
  final boldMerge = base.merge(const TextStyle(fontWeight: FontWeight.w700));
  final boldItalicMerge = base.merge(
    const TextStyle(fontWeight: FontWeight.w700, fontStyle: FontStyle.italic),
  );

  List<InlineSpan> italicSpans(String t, TextStyle normal, TextStyle italic) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*([^*]+)\*|_([^_]+)_');
    var start = 0;
    for (final m in re.allMatches(t)) {
      if (m.start > start) {
        spans.add(TextSpan(text: t.substring(start, m.start), style: normal));
      }
      final content = m.group(1) ?? m.group(2) ?? '';
      spans.add(TextSpan(text: content, style: italic));
      start = m.end;
    }
    if (start < t.length) {
      spans.add(TextSpan(text: t.substring(start), style: normal));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: t, style: normal));
    }
    return spans;
  }

  final out = <InlineSpan>[];
  final reBold = RegExp(r'\*\*([\s\S]+?)\*\*');
  var start = 0;
  for (final m in reBold.allMatches(input)) {
    if (m.start > start) {
      out.addAll(
        italicSpans(input.substring(start, m.start), base, italicMerge),
      );
    }
    final inner = m.group(1)!;
    out.addAll(italicSpans(inner, boldMerge, boldItalicMerge));
    start = m.end;
  }
  if (start < input.length) {
    out.addAll(italicSpans(input.substring(start), base, italicMerge));
  }
  if (out.isEmpty) {
    out.addAll(italicSpans(input, base, italicMerge));
  }
  return out;
}

/// Texto padrão do subtítulo da galeria de igrejas (site divulgação).
const String kMarketingGaleriaIgrejasSubtitle =
    'Galeria das Igrejas que já utilizam o sistema Gestão YAHWEH.';

/// Mesma mensagem com negritos para o bloco “hero” acima dos cards.
const String kMarketingGaleriaIgrejasSubtitleMd =
    'Galeria das Igrejas que **já utilizam** o sistema **Gestão YAHWEH**.';

/// Destaque público: igrejas que usam o Gestão YAHWEH (`app_public/marketing_clientes`).
class MarketingClientesShowcaseSection extends StatefulWidget {
  /// Quando false, oculta o título/subtítulo (ex.: landing com «acesso rápido» acima).
  final bool showSectionHeading;

  /// Com [showSectionHeading] false, ainda exibe o bloco de subtítulo premium da galeria (recomendado no site).
  final bool showPremiumGaleriaLead;

  const MarketingClientesShowcaseSection({
    super.key,
    this.showSectionHeading = true,
    this.showPremiumGaleriaLead = true,
  });

  /// Quantas igrejas mostrar antes de «Veja mais».
  static const int publicPreviewCount = 3;

  @override
  State<MarketingClientesShowcaseSection> createState() =>
      _MarketingClientesShowcaseSectionState();

  static List<Map<String, dynamic>> _parseItems(Map<String, dynamic>? data) =>
      MarketingClientesLoadService.parseItems(data);

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
    final isUrl =
        low.startsWith('http://') ||
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

  /// Resolução já feita (ou em curso) por assinatura de item.
  ///
  /// A cadeia capa→logo→`igrejas/{id}` custa até 3 idas à rede POR CARD. Sem
  /// esta memória, cada rebuild do grid (scroll, «Veja mais», troca de
  /// breakpoint) refazia tudo — era a maior causa de lentidão da galeria.
  static final Map<String, Future<({String url, bool logoContain})>>
  _showcaseImageMemo = {};

  static String showcaseImageMemoKey(Map<String, dynamic> item) =>
      '${item['id']}|${item['igrejaTenantId']}|${item['tenantId']}|'
      '${item['fotoPath']}|${item['fotoUrl']}|${item['logoUrl']}|'
      '${item['capaUrl']}|${item['logoStoragePath']}';

  /// Igual a [resolveShowcaseImage], mas partilhando a resolução entre cards
  /// e rebuilds. Chamadas concorrentes para o mesmo item viram uma só.
  static Future<({String url, bool logoContain})> resolveShowcaseImageCached(
    Map<String, dynamic> item,
  ) {
    final key = showcaseImageMemoKey(item);
    final hit = _showcaseImageMemo[key];
    if (hit != null) return hit;
    final f = resolveShowcaseImage(item);
    _showcaseImageMemo[key] = f;
    // Resolução falhada não fica presa na memória: permite nova tentativa.
    unawaited(
      f
          .then((r) {
            if (r.url.isEmpty) _showcaseImageMemo.remove(key);
          })
          .catchError((_) {
            _showcaseImageMemo.remove(key);
          }),
    );
    return f;
  }

  /// Doc `igrejas/{id}` já lido nesta sessão — a galeria inteira costuma
  /// precisar do mesmo punhado de igrejas.
  static final Map<String, Future<Map<String, dynamic>?>> _churchDocMemo = {};

  /// Resolve a imagem do card (capa → logo do item → logo canónica da igreja).
  /// `logoContain=true` quando a imagem é logo (exibir com BoxFit.contain).
  /// Blindagem: capa apagada/URL morta no Storage **nunca** deixa o card sem imagem
  /// enquanto a igreja tiver logo canónica (`configuracoes/logo_igreja.*`).
  static Future<({String url, bool logoContain})> resolveShowcaseImage(
    Map<String, dynamic> item,
  ) async {
    // 1) Capa de marketing (path/URL do item).
    final capa = await resolveCapaImageUrl(
      item,
    ).timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (resolvedUrlLooksUsable(capa)) {
      return (url: capa!, logoContain: false);
    }

    // 2) Logo gravada no próprio item (`logoStoragePath` / `logoUrl` etc.).
    final logoPath = (item['logoStoragePath'] ?? '').toString().trim();
    if (logoPath.isNotEmpty) {
      final byPath = await AppStorageImageService.instance
          .resolveImageUrl(storagePath: logoPath)
          .timeout(const Duration(seconds: 6), onTimeout: () => null);
      if (resolvedUrlLooksUsable(byPath)) {
        return (url: sanitizeImageUrl(byPath!), logoContain: true);
      }
    }
    String? preferForLogo;
    for (final k in <String>['logoUrl', 'urlLogo', 'imagemLogo']) {
      final u = _plausibleImageUrl((item[k] ?? '').toString());
      if (u != null) {
        preferForLogo = u;
        break;
      }
    }
    preferForLogo ??= primaryImageUrlFromItem(item);
    if (preferForLogo != null && resolvedUrlLooksUsable(preferForLogo)) {
      return (url: sanitizeImageUrl(preferForLogo), logoContain: true);
    }

    // 3) Logo canónica da igreja (`igrejas/{tid}` + Storage `configuracoes/`).
    final tid = (item['igrejaTenantId'] ?? item['tenantId'] ?? '')
        .toString()
        .trim();
    if (tid.isEmpty) return (url: '', logoContain: false);

    // Uma leitura por igreja em toda a sessão (várias fatias/cards partilham).
    final tenantData = await _churchDocMemo.putIfAbsent(tid, () async {
      try {
        final op = ChurchPanelTenantGateway.churchId(tid);
        final doc = await ChurchRepository.churchDoc(op).get().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'igrejas/$tid',
            const Duration(seconds: 5),
          ),
        );
        if (doc.exists && doc.data() != null) return doc.data();
      } catch (_) {}
      return null;
    });

    final logo = await AppStorageImageService.instance
        .resolveChurchTenantLogoUrl(
          tenantId: tid,
          tenantData: tenantData,
          preferImageUrl: preferForLogo,
          preferStoragePath: null,
          preferGsUrl: null,
        )
        .timeout(const Duration(seconds: 6), onTimeout: () => null);
    if (resolvedUrlLooksUsable(logo)) {
      return (url: sanitizeImageUrl(logo!), logoContain: true);
    }
    return (url: '', logoContain: false);
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
    final hasPrimary = primary != null && resolvedUrlLooksUsable(primary);

    String? bust(String? url) {
      if (url == null || url.isEmpty) return url;
      return YahwehMediaCacheBust.applyFromDocRevision(url, item);
    }

    if (hasPath && hasPrimary) {
      final both = await Future.wait<String?>([
        AppStorageImageService.instance.resolveImageUrl(
          storagePath: path,
          imageUrl: null,
        ),
        AppStorageImageService.instance.resolveImageUrl(imageUrl: primary),
      ]);
      final byPath = both[0];
      final byUrl = both[1];
      if (resolvedUrlLooksUsable(byPath)) {
        return bust(sanitizeImageUrl(byPath!));
      }
      if (resolvedUrlLooksUsable(byUrl)) {
        return bust(sanitizeImageUrl(byUrl!));
      }
      return null;
    }
    if (hasPath) {
      final byPath = await AppStorageImageService.instance.resolveImageUrl(
        storagePath: path,
        imageUrl: null,
      );
      if (resolvedUrlLooksUsable(byPath)) {
        return bust(sanitizeImageUrl(byPath!));
      }
    }
    if (hasPrimary) {
      final byUrl = await AppStorageImageService.instance.resolveImageUrl(
        imageUrl: primary,
      );
      if (resolvedUrlLooksUsable(byUrl)) {
        return bust(sanitizeImageUrl(byUrl!));
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
  late Future<({String url, bool logoContain})> _future;
  late String _itemSig;

  static String _itemSigOf(Map<String, dynamic> m) =>
      '${m['id']}_${m['fotoPath']}_${m['fotoUrl']}_${m['fotoUrlCacheRevision']}_${m['igrejaTenantId']}_${m['tenantId']}_${m['logoUrl']}_${m['logoStoragePath']}';

  @override
  void initState() {
    super.initState();
    _itemSig = _itemSigOf(widget.item);
    _future = MarketingClientesShowcaseSection.resolveShowcaseImageCached(
      widget.item,
    );
  }

  @override
  void didUpdateWidget(covariant MarketingClienteCapaThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _itemSigOf(widget.item);
    if (next != _itemSig) {
      _itemSig = next;
      _future = MarketingClientesShowcaseSection.resolveShowcaseImage(
        widget.item,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final maxDecode = UiAssetLayoutConstants.marketingClientLogoMemCacheWidth(
      context,
    );
    final logicalW = math.min(
      widget.width,
      UiAssetLayoutConstants.marketingClientLogoLogicalPx,
    );
    final mc = (logicalW * dpr).round().clamp(96, maxDecode);
    Widget core = FutureBuilder<({String url, bool logoContain})>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return widget.errorWidget;
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return widget.placeholder;
        }
        final r = snap.data;
        final u = r?.url;
        if (!MarketingClientesShowcaseSection.resolvedUrlLooksUsable(u)) {
          return widget.errorWidget;
        }
        final img = marketingClienteShowcaseImage(
          imageUrl: u!,
          webpUrl: MarketingClientesShowcaseSection.webpUrlFromItem(
            widget.item,
          ),
          width: widget.width,
          height: widget.height,
          fit: r!.logoContain ? BoxFit.contain : widget.fit,
          memCacheWidth: mc,
          memCacheHeight: mc,
          placeholder: widget.placeholder,
          errorWidget: widget.errorWidget,
        );
        if (r.logoContain) {
          return ColoredBox(
            color: const Color(0xFFF8FAFC),
            child: Padding(padding: const EdgeInsets.all(6), child: img),
          );
        }
        return img;
      },
    );
    if (widget.borderRadius != null) {
      core = ClipRRect(borderRadius: widget.borderRadius!, child: core);
    }
    return SizedBox(width: widget.width, height: widget.height, child: core);
  }
}

class _MarketingClientesShowcaseSectionState
    extends State<MarketingClientesShowcaseSection> {
  bool _showAllClientes = false;
  List<Map<String, dynamic>> _fallbackItems = const [];
  bool _fallbackLoading = false;
  bool _fallbackTried = false;
  String? _fallbackWarning;

  /// Dados vivos de `igrejas/{id}` por tenant — o que o gestor preenche no
  /// cadastro entra na vitrine sem o Master republicar a igreja.
  final Map<String, Map<String, dynamic>> _liveByTenant = {};
  String _hydratedSignature = '';
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureFallbackItems());
  }

  static String _tenantIdOf(Map<String, dynamic> item) =>
      (item['tenantId'] ?? item['igrejaTenantId'] ?? item['id'] ?? '')
          .toString()
          .trim();

  void _hydrateLiveChurchData(List<Map<String, dynamic>> items) {
    final ids = items.map(_tenantIdOf).where((e) => e.isNotEmpty).toList()
      ..sort();
    final signature = ids.join('|');
    if (signature.isEmpty || signature == _hydratedSignature || _hydrating) {
      return;
    }
    _hydrating = true;
    unawaited(
      MarketingClientesLoadService.hydrateFromChurchDocs(items)
          .then((hydrated) {
            if (!mounted) return;
            setState(() {
              _hydratedSignature = signature;
              _hydrating = false;
              for (final h in hydrated) {
                final id = _tenantIdOf(h);
                if (id.isNotEmpty) _liveByTenant[id] = h;
              }
            });
          })
          .catchError((Object e) {
            debugPrint('MarketingClientes hydrate: $e');
            if (mounted) setState(() => _hydrating = false);
          }),
    );
  }

  List<Map<String, dynamic>> _applyLiveData(List<Map<String, dynamic>> items) {
    if (_liveByTenant.isEmpty) return items;
    return [
      for (final item in items)
        _liveByTenant[_tenantIdOf(item)] ?? item,
    ];
  }

  Future<void> _ensureFallbackItems() async {
    if (_fallbackTried || _fallbackLoading) return;
    setState(() => _fallbackLoading = true);
    try {
      final r = await MarketingClientesLoadService.loadResolved();
      if (!mounted) return;
      setState(() {
        _fallbackItems = r.items;
        _fallbackWarning = r.warning;
        _fallbackTried = true;
        _fallbackLoading = false;
      });
    } catch (e) {
      debugPrint('MarketingClientesShowcaseSection fallback: $e');
      if (mounted) {
        setState(() {
          _fallbackTried = true;
          _fallbackLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _mergeItems(
    List<Map<String, dynamic>> firestoreItems,
  ) {
    final base = firestoreItems.isNotEmpty ? firestoreItems : _fallbackItems;
    if (base.isEmpty) return const [];
    _hydrateLiveChurchData(base);
    return _orderForShowcase(_applyLiveData(base));
  }

  /// Igrejas fixadas no topo da vitrine, na ordem em que entraram como cliente.
  /// O resto segue exactamente a ordem de cadastro que veio da fonte.
  static const List<List<String>> _pinnedChurchMatchers = [
    ['brasil para cristo'],
    ['batista nacional', 'ibna'],
  ];

  static String _normalizeForMatch(String raw) {
    const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const to = 'aaaaaeeeeiiiiooooouuuucn';
    final lower = raw.toLowerCase().trim();
    final buf = StringBuffer();
    for (final ch in lower.split('')) {
      final i = from.indexOf(ch);
      buf.write(i >= 0 ? to[i] : ch);
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _pinRank(Map<String, dynamic> item) {
    final nome = _normalizeForMatch(
      '${item['nomeIgreja'] ?? ''} ${item['alias'] ?? ''} ${item['slug'] ?? ''}',
    );
    for (var i = 0; i < _pinnedChurchMatchers.length; i++) {
      for (final needle in _pinnedChurchMatchers[i]) {
        if (nome.contains(needle)) return i;
      }
    }
    return _pinnedChurchMatchers.length;
  }

  static List<Map<String, dynamic>> _orderForShowcase(
    List<Map<String, dynamic>> items,
  ) {
    if (items.length < 2) return items;
    // Índice original como desempate — mantém a ordem de cadastro estável.
    final indexed = items.asMap().entries.toList();
    indexed.sort((a, b) {
      final ra = _pinRank(a.value);
      final rb = _pinRank(b.value);
      if (ra != rb) return ra.compareTo(rb);
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList(growable: false);
  }

  /// Paleta da vitrine — cada card ganha o seu acento (galeria colorida).
  static const List<List<Color>> _cardAccents = [
    [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
    [Color(0xFF047857), Color(0xFF10B981)],
    [Color(0xFF7C3AED), Color(0xFFA78BFA)],
    [Color(0xFFB45309), Color(0xFFF59E0B)],
    [Color(0xFFBE123C), Color(0xFFFB7185)],
    [Color(0xFF0E7490), Color(0xFF22D3EE)],
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: MarketingClientesLoadService.watchDoc(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData &&
            !_fallbackTried) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(ThemeCleanPremium.spaceXl),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final data = snap.data?.data();
        final firestoreItems = MarketingClientesShowcaseSection._parseItems(
          data,
        );
        if (firestoreItems.isEmpty && !_fallbackTried && !_fallbackLoading) {
          unawaited(_ensureFallbackItems());
        }
        final items = _mergeItems(firestoreItems);
        if (items.isEmpty) {
          if (_fallbackLoading) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(ThemeCleanPremium.spaceXl),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return _EmptyClientesPlaceholder(
            showPremiumLead: widget.showPremiumGaleriaLead,
            message: _fallbackWarning,
          );
        }

        final title = (data?['sectionTitle'] as String?)?.trim();
        final sectionSubtitle = (data?['sectionSubtitle'] as String?)?.trim();
        final w = MediaQuery.sizeOf(context).width;
        // Cards menores: mais colunas em telas largas e altura enxuta.
        final crossAxisCount = w >= 1500
            ? 4
            : w >= 1080
            ? 3
            : w >= 680
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
            if (widget.showSectionHeading) ...[
              _SectionHeading(
                title: title?.isNotEmpty == true
                    ? title!
                    : 'Igrejas que confiam no Gestão YAHWEH',
                subtitle: sectionSubtitle?.isNotEmpty == true
                    ? sectionSubtitle!
                    : kMarketingGaleriaIgrejasSubtitle,
              ),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
            ] else if (widget.showPremiumGaleriaLead) ...[
              const _PremiumGaleriaIgrejasLead(),
              const SizedBox(height: ThemeCleanPremium.spaceLg),
            ],
            SizedBox(
              width: double.infinity,
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: ThemeCleanPremium.spaceMd,
                  crossAxisSpacing: ThemeCleanPremium.spaceMd,
                  mainAxisExtent: crossAxisCount == 1 ? 448 : 424,
                ),
                itemCount: shown.length,
                itemBuilder: (context, i) {
                  final it = shown[i];
                  return _ClienteCard(
                    key: ValueKey<String>(
                      'cli_${it['id']}_${it['igrejaTenantId']}_${it['fotoUrl']}_${it['fotoPath']}',
                    ),
                    item: it,
                    accent: _cardAccents[i % _cardAccents.length],
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
                      horizontal: 22,
                      vertical: 14,
                    ),
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

/// Placeholder quando não há clientes (Firestore + Storage vazios).
class _EmptyClientesPlaceholder extends StatelessWidget {
  const _EmptyClientesPlaceholder({
    required this.showPremiumLead,
    this.message,
  });

  final bool showPremiumLead;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showPremiumLead) ...[
          const _PremiumGaleriaIgrejasLead(),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Text(
            message ??
                'Nenhuma igreja em destaque no momento. '
                    'As logos aparecem aqui quando cadastradas em Divulgação → Clientes '
                    'ou em ${MarketingStorageLayout.clientesRootPrefix}/ no Storage.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
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
        Text.rich(
          TextSpan(
            children: lightMarkdownInlineSpans(
              title,
              GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.onSurface,
                letterSpacing: -0.5,
                height: 1.2,
              ),
            ),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        _PremiumGaleriaSubtitleText(text: subtitle),
      ],
    );
  }
}

/// Subtítulo “super premium” sob o título da seção (respeita texto do CMS / Firestore).
class _PremiumGaleriaSubtitleText extends StatelessWidget {
  const _PremiumGaleriaSubtitleText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              primary.withValues(alpha: 0.08),
              const Color(0xFFF8FAFC),
              const Color(0xFFEFF6FF).withValues(alpha: 0.85),
            ],
          ),
          border: Border.all(
            color: primary.withValues(alpha: 0.22),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.10),
              blurRadius: 22,
              offset: const Offset(0, 10),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Text.rich(
          TextSpan(
            children: lightMarkdownInlineSpans(
              text,
              GoogleFonts.inter(
                color: const Color(0xFF1E3A8A),
                height: 1.5,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Bloco de destaque acima da galeria quando o título principal está oculto (site divulgação).
class _PremiumGaleriaIgrejasLead extends StatelessWidget {
  const _PremiumGaleriaIgrejasLead();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final primary = ThemeCleanPremium.primary;
    final isNarrow = w < 560;
    final fs = isNarrow ? 16.0 : 18.0;

    final iconBox = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            Color.lerp(primary, const Color(0xFF1E3A8A), 0.35)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.collections_rounded,
        color: Colors.white,
        size: 26,
      ),
    );

    final richText = Text.rich(
      TextSpan(
        children: lightMarkdownInlineSpans(
          kMarketingGaleriaIgrejasSubtitleMd,
          GoogleFonts.inter(
            fontSize: fs,
            fontWeight: FontWeight.w600,
            height: 1.45,
            letterSpacing: -0.35,
            color: const Color(0xFF0F172A),
          ),
        ),
      ),
      textAlign: isNarrow ? TextAlign.center : TextAlign.start,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: w < 400 ? 14 : 26,
          vertical: 22,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              const Color(0xFFF0F9FF).withValues(alpha: 0.95),
              primary.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFBFDBFE).withValues(alpha: 0.9),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: primary.withValues(alpha: 0.14),
              blurRadius: 32,
              offset: const Offset(0, 14),
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: isNarrow
            ? Column(children: [iconBox, const SizedBox(height: 16), richText])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  iconBox,
                  const SizedBox(width: 20),
                  Expanded(child: richText),
                ],
              ),
      ),
    );
  }
}

/// Hero da capa: tenta Storage/URL do marketing; se falhar, logo canónica da igreja (`configuracoes/`, legados).
class _ClienteShowcaseHero extends StatefulWidget {
  const _ClienteShowcaseHero({
    required this.item,
    this.accent = const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
  });

  final Map<String, dynamic> item;
  final List<Color> accent;

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
      // Cadeia completa capa → logo item → logo canónica. Timeout largo o
      // suficiente para web fria (auth anónima + getDownloadURL) — antes 8s
      // totais cortavam o fallback e a logo «sumia» do card.
      return await MarketingClientesShowcaseSection.resolveShowcaseImageCached(
        widget.item,
      ).timeout(
        const Duration(seconds: 22),
        onTimeout: () => (url: '', logoContain: false),
      );
    } catch (_) {
      return (url: '', logoContain: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c1 = widget.accent.first;
    final c2 = widget.accent.length > 1 ? widget.accent[1] : c1;
    // Fundo tingido com o acento do card (galeria colorida) — bem claro para
    // não competir com a logo, que é o que interessa ver.
    final tint = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(c1, Colors.white, 0.90)!,
        Color.lerp(c2, Colors.white, 0.96)!,
      ],
    );
    final ph = DecoratedBox(
      decoration: BoxDecoration(gradient: tint),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2, color: c1),
        ),
      ),
    );
    final err = DecoratedBox(
      decoration: BoxDecoration(gradient: tint),
      child: Center(
        child: Icon(
          Icons.church_rounded,
          size: 46,
          color: c1.withValues(alpha: 0.45),
        ),
      ),
    );

    // Alta resolução: pede os bytes no tamanho FÍSICO do card (largura lógica ×
    // devicePixelRatio), com teto de 4K. Sem isto a logo era decodificada no
    // tamanho lógico e ficava macia em telas Retina/4K.
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, c) {
          final targetW = (c.maxWidth * dpr).round().clamp(320, 3840);
          return FutureBuilder<({String url, bool logoContain})>(
            future: _future,
            builder: (context, snap) {
              if (snap.hasError) return err;
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData) {
                return ph;
              }
              final data = snap.data;
              if (data == null || data.url.isEmpty) return err;
              final u = data.url;
              final logoMode = data.logoContain;
              final webp = MarketingClientesShowcaseSection.webpUrlFromItem(
                widget.item,
              );
              final img = marketingClienteShowcaseImage(
                imageUrl: u,
                webpUrl: webp,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                placeholder: ph,
                errorWidget: err,
                memCacheWidth: targetW,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(gradient: tint),
                    child: Padding(
                      padding: EdgeInsets.all(logoMode ? 12 : 6),
                      child: img,
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
                              Colors.black.withValues(alpha: 0.30),
                            ],
                          ),
                        ),
                        child: const SizedBox(height: 36),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({
    super.key,
    required this.item,
    this.accent = const [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
  });

  final Map<String, dynamic> item;

  /// Par de cores do card (galeria colorida) — topo, faixa e ícones.
  final List<Color> accent;

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
    final corpo = _str('corpo');
    final pastor = _str('pastor').isNotEmpty
        ? _str('pastor')
        : (_str('pastorNome').isNotEmpty
              ? _str('pastorNome')
              : _str('responsavel'));
    final gestor = _str('gestor').isNotEmpty
        ? _str('gestor')
        : (_str('gestorNome').isNotEmpty
              ? _str('gestorNome')
              : _str('responsavel'));
    final loc = _str('localizacao').isNotEmpty
        ? _str('localizacao')
        : (_str('enderecoCompleto').isNotEmpty
              ? _str('enderecoCompleto')
              : (_str('endereco').isNotEmpty
                    ? _str('endereco')
                    : _str('address')));
    final whatsapp = _str('whatsapp').isNotEmpty
        ? _str('whatsapp')
        : (_str('telefone').isNotEmpty ? _str('telefone') : _str('phone'));
    final site = _str('sitePublico').isNotEmpty
        ? _str('sitePublico')
        : (_str('site').isNotEmpty
              ? _str('site')
              : (_str('siteUrl').isNotEmpty
                    ? _str('siteUrl')
                    : _str('website')));

    final wa = MarketingClientesShowcaseSection._waUrl(whatsapp);
    final siteUri = site.isNotEmpty
        ? MarketingClientesShowcaseSection._httpUrl(site)
        : null;
    final locUri = loc.isNotEmpty
        ? MarketingClientesShowcaseSection._locationLaunchUrl(loc)
        : null;
    final locHint = MarketingClientesShowcaseSection._locationDisplayHint(loc);

    const radius = 20.0;
    final c1 = accent.first;
    final c2 = accent.length > 1 ? accent[1] : accent.first;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: ThemeCleanPremium.cardBackground,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: c1.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 12),
              spreadRadius: -4,
            ),
            ...YahwehDesignSystem.softCardShadow,
          ],
          border: Border.all(color: c1.withValues(alpha: 0.22), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Faixa de cor no topo — identidade visual por card.
            Container(
              height: 5,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c1, c2]),
              ),
            ),
            _ClienteShowcaseHero(item: item, accent: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome.isEmpty ? 'Igreja' : nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        letterSpacing: -0.25,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    if (corpo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: lightMarkdownInlineSpans(
                            corpo,
                            GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              height: 1.35,
                              color: ThemeCleanPremium.onSurfaceVariant,
                            ),
                          ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (pastor.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _InfoRow(
                        icon: Icons.person_outline_rounded,
                        label: 'Pastor',
                        value: pastor,
                        color: c1,
                      ),
                    ],
                    if (gestor.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      _InfoRow(
                        icon: Icons.manage_accounts_outlined,
                        label: 'Gestor',
                        value: gestor,
                        color: c1,
                      ),
                    ],
                    if (locHint != null && locHint.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.place_outlined, size: 16, color: c1),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              locHint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
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
    final actions =
        <({String url, String label, IconData icon, Color color})>[];
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
        // Card compacto: mantém os atalhos numa linha só até bem estreito.
        final useRow = c.maxWidth >= 220 && actions.length <= 3;
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
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
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color ?? ThemeCleanPremium.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: $value',
            maxLines: 1,
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
