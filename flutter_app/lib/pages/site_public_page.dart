import "dart:async";

import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:gestao_yahweh/core/public_site_media_auth.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:url_launcher/url_launcher.dart";
import "package:gestao_yahweh/ui/widgets/version_footer.dart";
import "package:gestao_yahweh/ui/theme_clean_premium.dart";
import "package:gestao_yahweh/data/planos_oficiais.dart";
import "package:gestao_yahweh/services/plan_price_service.dart";
import "package:gestao_yahweh/ui/widgets/premium_storage_video/premium_institutional_video.dart";
import "package:gestao_yahweh/ui/widgets/marketing_gestao_yahweh_gallery.dart";
import "package:gestao_yahweh/ui/widgets/marketing_clientes_showcase_section.dart";
import "package:gestao_yahweh/ui/widgets/yahweh_official_social_bar.dart";
import "package:gestao_yahweh/services/public_site_analytics.dart";
import "package:gestao_yahweh/core/app_constants.dart";

String money(double v) => "R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}";

/// Cores de destaque por índice (mesma ordem de planosOficiais).
const _planAccents = [
  Color(0xFF1E5AA8),
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFFF97316),
  Color(0xFFDC2626),
  Color(0xFFF59E0B),
  Color(0xFF6B4E16),
  Color(0xFF64748B),
];
Color _accentForPlan(int index) =>
    index < _planAccents.length ? _planAccents[index] : const Color(0xFF2563EB);

/// Planos exibidos no site de divulgação = planosOficiais (mesma fonte do painel igreja e cadastro).

class SitePublicPage extends StatefulWidget {
  final String? slug;
  final bool isConviteRoute;

  const SitePublicPage({super.key, this.slug, this.isConviteRoute = false});

  @override
  State<SitePublicPage> createState() => _SitePublicPageState();
}

class _SitePublicPageState extends State<SitePublicPage> {
  Map<String, ({double? monthly, double? annual})>? _effectivePrices;

  final ScrollController _scrollController = ScrollController();

  final GlobalKey _keyVideo = GlobalKey();
  final GlobalKey _keyClientes = GlobalKey();
  final GlobalKey _keyGaleria = GlobalKey();
  final GlobalKey _keyPlanos = GlobalKey();
  final GlobalKey _keyIncluido = GlobalKey();
  final GlobalKey _keyDownload = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      });
    }
    // Preços = mesma fonte do Master: Firestore `config/plans/items` (+ fallback [planosOficiais]).
    PlanPriceService.getEffectivePrices().then((p) {
      if (mounted) setState(() => _effectivePrices = p);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
  }

  /// Abre o Painel Master (login admin).
  void _goAdmin() {
    unawaited(PublicSiteAnalytics.logMarketingAction('marketing_master_login'));
    Navigator.of(context).pushNamedAndRemoveUntil('/login_admin', (route) => false);
  }

  /// AppBar curta (Android/iPhone): logo + título; ações em menu para não truncar.
  static const double _kAppBarCompactWidth = 520;

  List<Widget> _sitePublicAppBarActions(BuildContext context) {
    if (widget.isConviteRoute) return const [];
    final narrow = MediaQuery.sizeOf(context).width < _kAppBarCompactWidth;
    if (narrow) {
      return [
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          color: Colors.white,
          onSelected: (value) {
            switch (value) {
              case 'planos':
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_menu_planos'));
                Navigator.pushNamed(context, '/planos');
                break;
              case 'login':
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_menu_entrar'));
                Navigator.pushNamed(context, '/igreja/login');
                break;
              case 'master':
                _goAdmin();
                break;
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(
              value: 'planos',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.workspace_premium_rounded, size: 22),
                title: Text('Ver planos'),
              ),
            ),
            PopupMenuItem(
              value: 'login',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.login_rounded, size: 22),
                title: Text('Login'),
              ),
            ),
            PopupMenuItem(
              value: 'master',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.admin_panel_settings_rounded, size: 22),
                title: Text('Acesso Painel Master'),
              ),
            ),
          ],
        ),
      ];
    }
    Widget navChip({
      required String label,
      required IconData icon,
      required VoidCallback onTap,
      bool emphasize = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Ink(
              decoration: BoxDecoration(
                gradient: emphasize
                    ? LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.22),
                          Colors.white.withValues(alpha: 0.1),
                        ],
                      )
                    : null,
                color: emphasize
                    ? null
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28),
                  width: 1,
                ),
                boxShadow: emphasize
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        letterSpacing: 0.25,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [
      navChip(
        label: 'VER PLANOS',
        icon: Icons.auto_awesome_rounded,
        emphasize: true,
        onTap: () {
          unawaited(
              PublicSiteAnalytics.logMarketingAction('marketing_bar_planos'));
          Navigator.pushNamed(context, '/planos');
        },
      ),
      navChip(
        label: 'LOGIN',
        icon: Icons.login_rounded,
        onTap: () {
          unawaited(PublicSiteAnalytics.logMarketingAction(
              'marketing_bar_entrar'));
          Navigator.pushNamed(context, '/igreja/login');
        },
      ),
      Padding(
        padding: const EdgeInsets.only(right: 6, left: 2),
        child: navChip(
          label: 'ACESSO PAINEL MASTER',
          icon: Icons.shield_rounded,
          onTap: () {
            unawaited(PublicSiteAnalytics.logMarketingAction(
                'marketing_master_login'));
            _goAdmin();
          },
        ),
      ),
    ];
  }

  Widget _sitePublicAppBarTitle(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < _kAppBarCompactWidth;
    return Row(
      children: [
        _PublicSiteGestaoYahwehLogo(size: narrow ? 22 : 26),
        SizedBox(width: narrow ? 6 : 8),
        Expanded(
          child: Text(
            'Gestão YAHWEH',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: narrow ? 14.5 : 16,
              letterSpacing: 0.15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topBar = ThemeCleanPremium.navSidebar;
    final scaffold = Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              topBar,
              ThemeCleanPremium.primaryLight,
              const Color(0xFFF0F4FF),
              ThemeCleanPremium.surfaceVariant,
            ],
            stops: const [0.0, 0.12, 0.22, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                toolbarHeight: 48,
                leading: widget.isConviteRoute
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                        onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
                        tooltip: 'Voltar ao início',
                      )
                    : null,
                title: _sitePublicAppBarTitle(context),
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                shadowColor: Colors.transparent,
                iconTheme: const IconThemeData(color: Colors.white),
                flexibleSpace: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        topBar,
                        Color.lerp(topBar, ThemeCleanPremium.primary, 0.12)!,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                actions: _sitePublicAppBarActions(context),
              ),
              Expanded(
                child: _buildBody(context),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.isConviteRoute) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
          }
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isMobile = c.maxWidth < 900;
        final hero = Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 920),
            child: _LeftHero(onGoAdmin: _goAdmin),
          ),
        );
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final hPad =
            isMobile ? ThemeCleanPremium.spaceMd : ThemeCleanPremium.spaceLg;
        return SingleChildScrollView(
          controller: _scrollController,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              hPad,
              hPad,
              hPad,
              hPad + bottomInset + 8,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 920),
                        child: KeyedSubtree(
                          key: _keyVideo,
                          child: PremiumMarketingHeroVideo(
                            height: isMobile ? 200 : 280,
                            defaultStoragePath: 'public/videos/institucional.mp4',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    hero,
                    const SizedBox(height: 18),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: isMobile ? double.infinity : 560),
                        child: YahwehOfficialSocialChannelsBar(
                          compact: isMobile,
                          onChannelTap: (ch) => unawaited(
                            PublicSiteAnalytics.logMarketingAction(
                                'marketing_social_$ch'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _MarketingQuickAccessBar(
                      onScrollTo: _scrollToSection,
                      keyClientes: _keyClientes,
                      keyGaleria: _keyGaleria,
                      keyPlanos: _keyPlanos,
                      keyIncluido: _keyIncluido,
                      keyDownload: _keyDownload,
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 960),
                        child: KeyedSubtree(
                          key: _keyClientes,
                          child: const MarketingClientesShowcaseSection(
                            showSectionHeading: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 960),
                        child: KeyedSubtree(
                          key: _keyGaleria,
                          child: const MarketingGestaoYahwehGallerySection(
                            excludePdfFromPublicGallery: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    KeyedSubtree(
                      key: _keyPlanos,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(
                            title: "Planos oficiais",
                            subtitle:
                                "Todos os modulos inclusos. O que muda e a escala de uso.",
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 14,
                            runSpacing: 14,
                            children: planosOficiais.asMap().entries.map((e) {
                              final i = e.key;
                              final p = e.value;
                              final ep = _effectivePrices?[p.id];
                              return SizedBox(
                                width: isMobile ? double.infinity : 280,
                                child: _PlanCard(
                                  plan: p,
                                  accent: _accentForPlan(i),
                                  priceMonthly: ep?.monthly ?? p.monthlyPrice,
                                  priceAnnual: ep?.annual ?? p.annualPrice,
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/cadastro'),
                        icon: const Icon(Icons.person_add_rounded),
                        label: const Text('Escolhi meu plano — Ir para cadastro'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: ThemeCleanPremium.spaceXl,
                              vertical: ThemeCleanPremium.spaceMd),
                          minimumSize: const Size(48, 48),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    KeyedSubtree(
                      key: _keyIncluido,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle(
                            title: "Tudo o que está incluído",
                            subtitle:
                                "Nenhum plano é capado: o sistema completo já vem ativo, com estes módulos.",
                          ),
                          const SizedBox(height: 16),
                          const _PremiumIncludedFeaturesGrid(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 720),
                        child: const _YahwehPublicFaqSection(),
                      ),
                    ),
                    const SizedBox(height: 26),
                    KeyedSubtree(
                      key: _keyDownload,
                      child: _DownloadsSection(),
                    ),
                    const SizedBox(height: 22),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 720),
                        child: const _YahwehAudienceFooterBar(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const VersionFooter(
                      showVersion: true,
                      useLegalPreviewModal: true,
                      openLegalLinksInNewTab: false,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _YahwehPublicFaqSection extends StatelessWidget {
  const _YahwehPublicFaqSection();

  @override
  Widget build(BuildContext context) {
    Widget tile(String q, String a) {
      return ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(a, style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey.shade800)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Perguntas frequentes',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              tile(
                'Posso usar meu próprio domínio no site da igreja?',
                'Sim. O site público pode ser divulgado com o endereço da igreja (slug) e integrações de contato; domínio personalizado depende da sua configuração de DNS e hospedagem — nossa equipe orienta na contratação.',
              ),
              const Divider(height: 1),
              tile(
                'Preciso instalar algo para os membros?',
                'Há aplicativo para celular e acesso web. Membros podem usar o que for mais conveniente; o painel da igreja funciona em navegador e em app.',
              ),
              const Divider(height: 1),
              tile(
                'Onde ficam armazenados dados e mídias?',
                'Em infraestrutura cloud com regras de acesso por perfil (igreja, gestor e membro). Você controla o que é público no site e o que permanece interno.',
              ),
              const Divider(height: 1),
              tile(
                'LGPD e responsabilidade pelos dados',
                'A igreja é titular dos dados dos membros cadastrados. O Gestão YAHWEH fornece ferramentas de gestão e boas práticas de acesso; recomendamos política interna de privacidade alinhada à LGPD.',
              ),
              const Divider(height: 1),
              tile(
                'Como falo com o suporte?',
                'Use os canais indicados após o cadastro ou no painel. Priorizamos estabilidade, segurança e resposta em horário comercial.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _YahwehAudienceFooterBar extends StatelessWidget {
  const _YahwehAudienceFooterBar();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Três entradas claras',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Escolha o caminho que combina com você: visitante, membro ou liderança.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ActionChip(
              avatar: const Icon(Icons.waving_hand_rounded, size: 18),
              label: const Text('Visitantes — cadastro da igreja'),
              onPressed: () {
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_footer_chip_cadastro'));
                Navigator.pushNamed(context, '/cadastro');
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Membros — entrar no sistema'),
              onPressed: () {
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_footer_chip_entrar'));
                Navigator.pushNamed(context, '/igreja/login');
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Líderes — planos e limites'),
              onPressed: () {
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_footer_chip_planos'));
                Navigator.pushNamed(context, '/planos');
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Membros: use seu e-mail cadastrado na igreja para localizar o painel na página inicial. Líderes: após o cadastro da igreja, liberamos o painel completo conforme o plano.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
        ),
      ],
    );
  }
}

/// Logo da marca no site público: PNG → ícone do app → identidade tipográfica (nunca área vazia).
class _PublicSiteGestaoYahwehLogo extends StatelessWidget {
  final double size;

  const _PublicSiteGestaoYahwehLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return Image.asset(
      'assets/LOGO_GESTAO_YAHWEH.png',
      height: size,
      width: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/icon/app_icon.png',
        height: size * 0.88,
        width: size * 0.88,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            _PublicSiteGestaoYahwehTextMark(maxSide: size, color: primary),
      ),
    );
  }
}

class _PublicSiteGestaoYahwehTextMark extends StatelessWidget {
  final double maxSide;
  final Color color;

  const _PublicSiteGestaoYahwehTextMark({
    required this.maxSide,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxSide,
        maxWidth: maxSide * 1.35,
        minHeight: 72,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.church_rounded, size: maxSide * 0.22, color: color),
            const SizedBox(height: 8),
            Text(
              'Gestão',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 1.05,
              ),
            ),
            Text(
              'YAHWEH',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 26,
                height: 1.05,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeftHero extends StatelessWidget {
  final VoidCallback onGoAdmin;
  const _LeftHero({required this.onGoAdmin});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    Widget heroBtn({
      required String label,
      required IconData icon,
      required VoidCallback onPressed,
      required bool filled,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: filled
                  ? LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary,
                        ThemeCleanPremium.primaryLight,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: filled ? null : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: filled
                    ? Colors.transparent
                    : ThemeCleanPremium.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: ThemeCleanPremium.primary.withValues(alpha: filled ? 0.35 : 0.12),
                  blurRadius: filled ? 20 : 10,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: filled ? Colors.white : ThemeCleanPremium.primary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      letterSpacing: 0.25,
                      color: filled ? Colors.white : ThemeCleanPremium.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: ThemeCleanPremium.premiumSurfaceCard,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? ThemeCleanPremium.spaceMd : 24,
            vertical: isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final logoSize = isMobile
                      ? (constraints.maxWidth < 400 ? 104.0 : 132.0)
                      : 228.0;
                  return _PublicSiteGestaoYahwehLogo(size: logoSize);
                },
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Gestão YAHWEH",
              style: TextStyle(
                fontSize: isMobile ? 16 : 19,
                fontWeight: FontWeight.w900,
                color: ThemeCleanPremium.primary,
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              "Um sistema de excelência feito para sua igreja",
              style: TextStyle(
                fontSize: isMobile ? 13 : 15,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                heroBtn(
                  filled: true,
                  label: 'VER PLANOS',
                  icon: Icons.workspace_premium_rounded,
                  onPressed: () {
                    unawaited(PublicSiteAnalytics.logMarketingAction(
                        'marketing_hero_planos'));
                    Navigator.pushNamed(context, '/planos');
                  },
                ),
                heroBtn(
                  filled: false,
                  label: 'LOGIN',
                  icon: Icons.login_rounded,
                  onPressed: () {
                    unawaited(PublicSiteAnalytics.logMarketingAction(
                        'marketing_hero_login'));
                    Navigator.pushNamed(context, '/igreja/login');
                  },
                ),
                heroBtn(
                  filled: false,
                  label: 'ACESSO PAINEL MASTER',
                  icon: Icons.shield_rounded,
                  onPressed: () {
                    unawaited(PublicSiteAnalytics.logMarketingAction(
                        'marketing_hero_master'));
                    onGoAdmin();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Atalhos para secções da landing (scroll suave).
class _MarketingQuickAccessBar extends StatelessWidget {
  final void Function(GlobalKey key) onScrollTo;
  final GlobalKey keyClientes;
  final GlobalKey keyGaleria;
  final GlobalKey keyPlanos;
  final GlobalKey keyIncluido;
  final GlobalKey keyDownload;

  const _MarketingQuickAccessBar({
    required this.onScrollTo,
    required this.keyClientes,
    required this.keyGaleria,
    required this.keyPlanos,
    required this.keyIncluido,
    required this.keyDownload,
  });

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final items = <({String label, String analyticsId, IconData icon, GlobalKey key})>[
      (label: 'CLIENTES GESTÃO YAHWEH', analyticsId: 'marketing_quick_clientes', icon: Icons.church_rounded, key: keyClientes),
      (label: 'GALERIA', analyticsId: 'marketing_quick_galeria', icon: Icons.collections_rounded, key: keyGaleria),
      (label: 'PLANOS OFICIAIS', analyticsId: 'marketing_quick_planos', icon: Icons.workspace_premium_rounded, key: keyPlanos),
      (label: 'TUDO QUE ESTÁ INCLUÍDO NO SISTEMA', analyticsId: 'marketing_quick_incluido', icon: Icons.dashboard_customize_rounded, key: keyIncluido),
      (label: 'BAIXAR APLICATIVO', analyticsId: 'marketing_quick_download', icon: Icons.download_rounded, key: keyDownload),
    ];

    Widget chip(({String label, String analyticsId, IconData icon, GlobalKey key}) it) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            unawaited(PublicSiteAnalytics.logMarketingAction(it.analyticsId));
            onScrollTo(it.key);
          },
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(it.icon,
                      size: narrow ? 16 : 18, color: ThemeCleanPremium.primary),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      it.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        letterSpacing: 0.2,
                        height: 1.15,
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.06),
            Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ThemeCleanPremium.primary.withValues(alpha: 0.12)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: ThemeCleanPremium.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Acesso rápido',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: narrow ? 16 : 17,
                  color: ThemeCleanPremium.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (narrow)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  chip(items[i]),
                  if (i < items.length - 1) const SizedBox(height: 8),
                ],
              ],
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: items.map(chip).toList(),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 4,
              height: 26,
              decoration: BoxDecoration(
                color: ThemeCleanPremium.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: ThemeCleanPremium.onSurface,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: ThemeCleanPremium.onSurfaceVariant,
            height: 1.45,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanoOficial plan;
  final Color accent;
  final double? priceMonthly;
  final double? priceAnnual;
  const _PlanCard({required this.plan, required this.accent, this.priceMonthly, this.priceAnnual});

  @override
  Widget build(BuildContext context) {
    final monthly = priceMonthly ?? plan.monthlyPrice;
    final annual = priceAnnual ?? plan.annualPrice;
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(
            color: plan.featured
                ? accent.withValues(alpha: 0.55)
                : const Color(0xFFE5EAF3)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              if (plan.featured)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text("Recomendado", style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.members, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 10),
          Text(
            monthly == null ? (plan.note ?? "Sob consulta") : "${money(monthly)} / mes",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: accent),
          ),
          const SizedBox(height: 6),
          if (annual != null)
            Text("Anual: ${money(annual)} (12 por 10)", style: const TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 12),
          const Text(
            "App + Painel Web + Site publico\nEventos, escalas e financeiro (MP/PIX automatico)\nBackups automaticos e seguranca",
            style: TextStyle(color: Colors.black54, height: 1.35, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Módulos incluídos no plano — ícones Material 3, cartões com sombra suave.
class _PremiumIncludedFeaturesGrid extends StatelessWidget {
  const _PremiumIncludedFeaturesGrid();

  static const List<({IconData icon, String label})> _features = [
    (icon: Icons.groups_rounded, label: 'Controle de membros'),
    (icon: Icons.cake_rounded, label: 'Aniversariantes'),
    (icon: Icons.campaign_rounded, label: 'Avisos'),
    (icon: Icons.event_available_rounded, label: 'Eventos'),
    // calendar_view_week_rounded pode não vir no MaterialIcons tree-shaken (web) → ícone vazio.
    (icon: Icons.event_note_rounded, label: 'Escalas'),
    (icon: Icons.calendar_month_rounded, label: 'Agendas'),
    (icon: Icons.volunteer_activism_rounded, label: 'Pedidos de orações'),
    (icon: Icons.forum_rounded, label: 'Pastoral & Comunicação'),
    (icon: Icons.public_rounded, label: 'Site público integrado ao sistema'),
    (icon: Icons.inventory_2_rounded, label: 'Controle de patrimônio'),
    (
      icon: Icons.account_balance_wallet_rounded,
      label:
          'Controle financeiro — Mercado Pago e PIX com lançamentos automáticos',
    ),
    (icon: Icons.business_center_rounded, label: 'Cadastro de Fornecedores e Prestadores de Serviços'),
    (icon: Icons.workspace_premium_rounded, label: 'Emissão de certificados'),
    (icon: Icons.badge_rounded, label: 'Cartão membro moderno'),
    (icon: Icons.devices_rounded, label: 'Acesso via web, Android e iOS (Apple)'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final cols = maxW > 920 ? 3 : (maxW > 560 ? 2 : 1);
        const gap = 14.0;
        final tileW = cols <= 1
            ? maxW
            : (maxW - gap * (cols - 1)) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _features.map((f) {
            return SizedBox(
              width: tileW,
              child: _PremiumFeatureTile(
                icon: f.icon,
                label: f.label,
                accent: primary,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _PremiumFeatureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _PremiumFeatureTile({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent,
                  Color.lerp(accent, const Color(0xFF312E81), 0.35)!,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                height: 1.28,
                color: Color(0xFF0F172A),
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadsSection extends StatelessWidget {
  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Baixar aplicativo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Android: app Gestão YAHWEH na Play Store (link direto abaixo). '
              'iOS e pasta: configuráveis pelo painel master em config/appDownloads.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .doc('config/appDownloads')
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final folderUrl = (data['driveFolderUrl'] ?? '').toString();
                final androidEffective =
                    AppConstants.effectiveAppDownloadsAndroidUrl(data);
                final iosEffective =
                    AppConstants.effectiveAppDownloadsIosUrl(data);

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _open(androidEffective),
                      icon: const Icon(Icons.android),
                      label: const Text('Android'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: iosEffective.isEmpty
                          ? null
                          : () => _open(iosEffective),
                      icon: const Icon(Icons.apple),
                      label: const Text('iOS'),
                    ),
                    OutlinedButton.icon(
                      onPressed: folderUrl.isEmpty
                          ? null
                          : () => _open(folderUrl),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Pasta de downloads'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
