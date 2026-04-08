import "dart:async";

import "package:flutter/foundation.dart" show debugPrint, kIsWeb;
import "package:flutter/material.dart";
import "package:gestao_yahweh/core/public_site_media_auth.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:url_launcher/url_launcher.dart";
import "package:gestao_yahweh/ui/widgets/version_footer.dart";
import "package:gestao_yahweh/ui/theme_clean_premium.dart";
import "package:gestao_yahweh/ui/login_page.dart";
import "package:gestao_yahweh/data/planos_oficiais.dart";
import "package:gestao_yahweh/services/plan_price_service.dart";
import "package:gestao_yahweh/ui/widgets/premium_storage_video/premium_institutional_video.dart";
import "package:gestao_yahweh/ui/widgets/marketing_gestao_yahweh_gallery.dart";
import "package:gestao_yahweh/ui/widgets/marketing_clientes_showcase_section.dart";
import "package:gestao_yahweh/services/public_site_analytics.dart";
import "package:gestao_yahweh/services/auth_cpf_service.dart";
import "package:gestao_yahweh/ui/widgets/safe_network_image.dart";

String money(double v) => "R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}";

QuerySnapshot<Map<String, dynamic>>? _cachedPublicEmptySnap;

/// Evita que uma query Firestore falhada derrube o lote paralelo (índice, permissão anónima em collectionGroup, etc.).
Future<QuerySnapshot<Map<String, dynamic>>> _safeFsQuery(
  Future<QuerySnapshot<Map<String, dynamic>>> future,
) async {
  try {
    return await future;
  } catch (_) {
    try {
      _cachedPublicEmptySnap ??=
          await FirebaseFirestore.instance.collection('igrejas').limit(0).get();
      return _cachedPublicEmptySnap!;
    } catch (_) {
      try {
        return await FirebaseFirestore.instance.collection('config').limit(0).get();
      } catch (_) {
        if (_cachedPublicEmptySnap != null) return _cachedPublicEmptySnap!;
        rethrow;
      }
    }
  }
}

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
  final _churchEmailCtrl = TextEditingController();
  bool _loading = false;
  Map<String, ({double? monthly, double? annual})>? _effectivePrices;

  /// Callable deployada em `us-central1` — `FirebaseFunctions.instance` usa outra região e falha no site.
  HttpsCallable get _resolveEmailToChurchCallable =>
      FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('resolveEmailToChurchPublic');

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

  String? _statusMsg; // msg amigável (não mostra internal/not_found)
  Map<String, dynamic>? _church; // {tenantId, name, logoUrl, slug...}

  Timer? _autoTimer;

  @override
  void dispose() {
    _autoTimer?.cancel();
    _churchEmailCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _callableResolveEmailToChurch(String raw) async {
    try {
      final fn = _resolveEmailToChurchCallable;
      final res = await fn
          .call({'email': raw.trim()})
          .timeout(const Duration(seconds: 18));
      final payload = res.data;
      if (payload is! Map) return null;
      final data = Map<String, dynamic>.from(payload);
      final tid = (data['tenantId'] ?? '').toString().trim();
      return tid.isEmpty ? null : data;
    } catch (e, st) {
      assert(() {
        debugPrint('[SitePublic] resolveEmailToChurchPublic: $e\n$st');
        return true;
      }());
      return null;
    }
  }

  Future<void> _loadChurch() async {
    final raw = _churchEmailCtrl.text.trim();
    if (!AuthCpfService.looksLikeEmail(raw)) {
      setState(() {
        _statusMsg = 'Informe um e-mail válido (ex.: nome@email.com).';
        _church = null;
      });
      return;
    }
    final emailLower = raw.toLowerCase();
    setState(() {
      _loading = true;
      _statusMsg = null;
      _church = null;
    });

    void applyChurchNoNavigate(String tid, Map<String, dynamic> data) {
      if (!mounted) return;
      setState(() {
        _church = {
          'tenantId': tid,
          'name': (data['nome'] ?? data['name'] ?? data['nomeFantasia'] ?? tid).toString(),
          'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
          'logoUrl': (data['logoUrl'] ?? data['logoProcessedUrl'] ?? data['logoProcessed'] ?? '').toString(),
        };
        _loading = false;
        _statusMsg = null;
      });
    }

    void applyFromCallable(Map<String, dynamic> data) {
      if (!mounted) return;
      final tid = (data['tenantId'] ?? '').toString().trim();
      if (tid.isEmpty) return;
      setState(() {
        _church = {
          'tenantId': tid,
          'name': (data['name'] ?? tid).toString(),
          'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
          'logoUrl': (data['logoUrl'] ??
                  data['logoProcessedUrl'] ??
                  data['logoProcessed'] ??
                  '')
              .toString(),
        };
        _loading = false;
        _statusMsg = null;
      });
    }

    try {
      final refIgrejas = FirebaseFirestore.instance.collection('igrejas');
      // 1) Cloud Function (lê usersIndex + membros sem depender de regras públicas).
      Map<String, dynamic>? cfData;
      try {
        cfData = await _callableResolveEmailToChurch(raw);
      } catch (e, st) {
        assert(() {
          debugPrint('[SitePublic] _loadChurch callable outer: $e\n$st');
          return true;
        }());
        cfData = null;
      }
      if (!mounted) return;
      if (cfData != null) {
        applyFromCallable(cfData);
        return;
      }

      // 2) Queries diretas em `igrejas/` + usersIndex (paralelo isolado — falha não derruba o fluxo).
      List<QuerySnapshot<Map<String, dynamic>>> igSnaps;
      try {
        igSnaps = await Future.wait([
          _safeFsQuery(
              refIgrejas.where('email', isEqualTo: emailLower).limit(1).get()),
          _safeFsQuery(refIgrejas.where('email', isEqualTo: raw).limit(1).get()),
          _safeFsQuery(refIgrejas
              .where('gestorEmail', isEqualTo: emailLower)
              .limit(1)
              .get()),
          _safeFsQuery(
              refIgrejas.where('gestorEmail', isEqualTo: raw).limit(1).get()),
          // Legado / exportações: snake_case no Firestore
          _safeFsQuery(refIgrejas
              .where('gestor_email', isEqualTo: emailLower)
              .limit(1)
              .get()),
          _safeFsQuery(
              refIgrejas.where('gestor_email', isEqualTo: raw).limit(1).get()),
          _safeFsQuery(refIgrejas
              .where('emailGestor', isEqualTo: emailLower)
              .limit(1)
              .get()),
          _safeFsQuery(
              refIgrejas.where('emailGestor', isEqualTo: raw).limit(1).get()),
          _safeFsQuery(refIgrejas
              .where('emailContato', isEqualTo: emailLower)
              .limit(1)
              .get()),
          _safeFsQuery(refIgrejas
              .where('responsavelEmail', isEqualTo: emailLower)
              .limit(1)
              .get()),
          _safeFsQuery(FirebaseFirestore.instance
              .collectionGroup('usersIndex')
              .where('email', isEqualTo: emailLower)
              .limit(1)
              .get()),
          _safeFsQuery(FirebaseFirestore.instance
              .collectionGroup('usersIndex')
              .where('email', isEqualTo: raw)
              .limit(1)
              .get()),
        ]);
      } catch (e, st) {
        assert(() {
          debugPrint('[SitePublic] _loadChurch igrejas batch: $e\n$st');
          return true;
        }());
        igSnaps = <QuerySnapshot<Map<String, dynamic>>>[];
      }

      /// Índices 0–3: e-mail da igreja + gestorEmail (só cartão). 4–5: gestor_email. 6–9: demais campos. 10–11: usersIndex.
      const navAfter = <bool>[
        false,
        false,
        false,
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
      ];
      bool snapOk(int i) =>
          i < igSnaps.length && igSnaps[i].docs.isNotEmpty;
      for (var i = 0; i < 10; i++) {
        if (snapOk(i)) {
          final doc = igSnaps[i].docs.first;
          applyChurchNoNavigate(doc.id, doc.data());
          if (navAfter[i]) _navigateToChurchLogin();
          return;
        }
      }
      for (var i = 10; i < 12; i++) {
        if (snapOk(i)) {
          final userDoc = igSnaps[i].docs.first;
          final pathSegments = userDoc.reference.path.split('/');
          var tenantId = pathSegments.length >= 2 ? pathSegments[1] : '';
          if (tenantId.isEmpty) {
            final ud = userDoc.data();
            tenantId = (ud['tenantId'] ?? ud['igrejaId'] ?? '').toString().trim();
          }
          if (tenantId.isNotEmpty) {
            final tenantSnap =
                await refIgrejas.doc(tenantId).get();
            if (!mounted) return;
            if (tenantSnap.exists) {
              final td = tenantSnap.data();
              if (td != null) {
                applyChurchNoNavigate(tenantId, td);
                _navigateToChurchLogin();
                return;
              }
            }
          }
        }
      }

      final memberFutures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
      for (final coll in ['membros', 'members']) {
        for (final field in ['email', 'EMAIL', 'mail', 'e_mail']) {
          for (final val in [emailLower, raw]) {
            memberFutures.add(_safeFsQuery(FirebaseFirestore.instance
                .collectionGroup(coll)
                .where(field, isEqualTo: val)
                .limit(1)
                .get()));
          }
        }
      }
      List<QuerySnapshot<Map<String, dynamic>>> memberSnaps;
      try {
        memberSnaps = await Future.wait(memberFutures);
      } catch (e, st) {
        assert(() {
          debugPrint('[SitePublic] _loadChurch membros batch: $e\n$st');
          return true;
        }());
        memberSnaps = <QuerySnapshot<Map<String, dynamic>>>[];
      }
      if (!mounted) return;
      for (final snapMembers in memberSnaps) {
        if (snapMembers.docs.isEmpty) continue;
        final memberDoc = snapMembers.docs.first;
        final pathSegments = memberDoc.reference.path.split('/');
        var tenantId = '';
        if (pathSegments.length >= 4 &&
            pathSegments[0] == 'igrejas' &&
            (pathSegments[2] == 'membros' || pathSegments[2] == 'members')) {
          tenantId = pathSegments[1];
        }
        if (tenantId.isEmpty) {
          final d = memberDoc.data();
          tenantId = (d['tenantId'] ??
                  d['tenant_id'] ??
                  d['igrejaId'] ??
                  d['igreja_id'] ??
                  '')
              .toString()
              .trim();
        }
        if (tenantId.isEmpty) continue;
        final tenantSnap = await refIgrejas.doc(tenantId).get();
        if (!mounted) return;
        if (tenantSnap.exists) {
          final td = tenantSnap.data();
          if (td != null) {
            applyChurchNoNavigate(tenantId, td);
            _navigateToChurchLogin();
            return;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMsg =
            'Nenhuma igreja encontrada para este e-mail. Se você é gestor, confira no Painel Master se o e-mail está em gestorEmail, emailGestor ou gestor_email no cadastro da igreja.';
      });
    } catch (e, st) {
      assert(() {
        debugPrint('[SitePublic] _loadChurch: $e\n$st');
        return true;
      }());
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final isPermission = msg.contains('permission_denied') ||
          msg.contains('permission-denied');
      final isConnection = msg.contains('unavailable') ||
          msg.contains('failed to fetch') ||
          msg.contains('network') ||
          msg.contains('socket') ||
          msg.contains('could not reach');
      final isFailedPrecondition = msg.contains('failed-precondition') ||
          msg.contains('failed_precondition') ||
          msg.contains('requires an index');

      if (isPermission) {
        try {
          final fn = _resolveEmailToChurchCallable;
          final res = await fn.call({'email': raw}).timeout(const Duration(seconds: 18));
          final payload = res.data;
          if (payload is Map) {
            final data = Map<String, dynamic>.from(payload);
            final tid = (data['tenantId'] ?? '').toString().trim();
            if (tid.isNotEmpty && mounted) {
              setState(() {
                _church = {
                  'tenantId': tid,
                  'name': (data['name'] ?? tid).toString(),
                  'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
                  'logoUrl': (data['logoUrl'] ??
                          data['logoProcessedUrl'] ??
                          data['logoProcessed'] ??
                          '')
                      .toString(),
                };
                _loading = false;
                _statusMsg = null;
              });
              _navigateToChurchLogin();
              return;
            }
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMsg = isConnection
            ? 'Não foi possível conectar ao servidor. Verifique sua internet e tente novamente.'
            : isPermission
                ? 'Sem permissão para consultar. Verifique as regras do Firestore e se o domínio está autorizado no Firebase (Authentication > Authorized domains).'
                : isFailedPrecondition
                    ? 'Consulta temporariamente indisponível. Tente de novo em instantes ou use Entrar no menu com e-mail e senha.'
                    : 'Erro ao buscar. Verifique o e-mail e tente novamente.';
        _church = null;
      });
    }
  }

  /// Abre o Painel Master (login admin).
  void _goAdmin() {
    unawaited(PublicSiteAnalytics.logMarketingAction('marketing_master_login'));
    Navigator.of(context).pushNamedAndRemoveUntil('/login_admin', (route) => false);
  }
  void _onChurchEmailChanged(String value) {
    setState(() {});
    _autoTimer?.cancel();
    final t = value.trim();
    if (!AuthCpfService.looksLikeEmail(t)) return;
    _autoTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_churchEmailCtrl.text.trim() != t) return;
      if (_loading) return;
      _loadChurch();
    });
  }

  /// Após carregar a igreja, navega direto para a página de login da igreja.
  void _navigateToChurchLogin() {
    final church = _church;
    if (church == null || !mounted) return;
    unawaited(PublicSiteAnalytics.logMarketingAction(
        'marketing_prefill_church_login'));
    final name = church['name']?.toString();
    final emailForLogin = _churchEmailCtrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LoginPage(
            title: 'Entrar — Painel da Igreja',
            afterLoginRoute: '/painel',
            showFleetBranding: false,
            churchLabel: name,
            churchLogoUrl: (church['logoUrl'] ?? '').toString().trim().isEmpty
                ? null
                : (church['logoUrl'] ?? '').toString().trim(),
            prefillEmail:
                emailForLogin.isNotEmpty ? emailForLogin.toLowerCase() : null,
            backRoute: '/',
          ),
        ),
      );
    });
  }

  void _goChurch() {
    if (_church == null || _loading) return;
    final slug = _church!['slug'] as String?;
    if (slug != null && slug.isNotEmpty) {
      unawaited(
          PublicSiteAnalytics.logMarketingAction('marketing_open_church_slug'));
      Navigator.of(context).pushNamed('/igreja_$slug');
    }
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
              case 'cadastro':
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_menu_cadastro'));
                Navigator.pushNamed(context, '/cadastro');
                break;
              case 'entrar':
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_menu_entrar'));
                Navigator.pushNamed(context, '/igreja/login');
                break;
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'planos', child: Text('Planos')),
            PopupMenuItem(value: 'cadastro', child: Text('Cadastro')),
            PopupMenuItem(value: 'entrar', child: Text('Entrar')),
          ],
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () {
          unawaited(
              PublicSiteAnalytics.logMarketingAction('marketing_bar_planos'));
          Navigator.pushNamed(context, '/planos');
        },
        child: const Text(
          'Planos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      TextButton(
        onPressed: () {
          unawaited(PublicSiteAnalytics.logMarketingAction(
              'marketing_bar_cadastro'));
          Navigator.pushNamed(context, '/cadastro');
        },
        child: const Text(
          'Cadastro',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton(
          onPressed: () {
            unawaited(PublicSiteAnalytics.logMarketingAction(
                'marketing_bar_entrar'));
            Navigator.pushNamed(context, '/igreja/login');
          },
          child: const Text(
            'Entrar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ];
  }

  Widget _sitePublicAppBarTitle(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < _kAppBarCompactWidth;
    return Row(
      children: [
        _PublicSiteGestaoYahwehLogo(size: narrow ? 28 : 32),
        SizedBox(width: narrow ? 8 : 10),
        Expanded(
          child: Text(
            'Gestão YAHWEH',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: narrow ? 16 : 18,
              letterSpacing: 0.2,
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
                leading: widget.isConviteRoute
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
                        onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
                        tooltip: 'Voltar ao início',
                      )
                    : null,
                title: _sitePublicAppBarTitle(context),
                backgroundColor: topBar,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
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
        final left = _LeftHero(onGoAdmin: _goAdmin);
        final right = _ChurchLookupCard(
          emailCtrl: _churchEmailCtrl,
          loading: _loading,
          statusMsg: _statusMsg,
          church: _church,
          onLoad: _loadChurch,
          onEmailChanged: _onChurchEmailChanged,
          onEnter: (_church != null && !_loading) ? _goChurch : null,
        );
        final topRow = isMobile
            ? Column(
                children: [left, const SizedBox(height: 16), right],
              )
            : Row(
                children: [Expanded(child: left), const SizedBox(width: 16), SizedBox(width: 420, child: right)],
              );
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final hPad =
            isMobile ? ThemeCleanPremium.spaceMd : ThemeCleanPremium.spaceLg;
        return SingleChildScrollView(
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                              title: 'Conheça em vídeo',
                              subtitle:
                                  'Pitch rápido do ecossistema: app, painel da igreja e site público.',
                            ),
                            const SizedBox(height: 10),
                            PremiumMarketingHeroVideo(
                              height: isMobile ? 200 : 280,
                              defaultStoragePath: 'public/videos/institucional.mp4',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    topRow,
                    const SizedBox(height: 24),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 960),
                        child: const MarketingClientesShowcaseSection(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 960),
                        child: const MarketingGestaoYahwehGallerySection(
                          excludePdfFromPublicGallery: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle(
                      title: "Planos oficiais",
                      subtitle: "Todos os modulos inclusos. O que muda e a escala de uso.",
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
                    const _SectionTitle(
                      title: "Tudo o que está incluído",
                      subtitle:
                          "Nenhum plano é capado: o sistema completo já vem ativo, com estes módulos.",
                    ),
                    const SizedBox(height: 16),
                    const _PremiumIncludedFeaturesGrid(),
                    const SizedBox(height: 28),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 720),
                        child: const _YahwehPublicFaqSection(),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _DownloadsSection(),
                    const SizedBox(height: 22),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 720),
                        child: const _YahwehAudienceFooterBar(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const VersionFooter(showVersion: true),
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
    return Container(
      decoration: ThemeCleanPremium.premiumSurfaceCard,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? ThemeCleanPremium.spaceLg : 32,
            vertical: isMobile ? ThemeCleanPremium.spaceLg : ThemeCleanPremium.spaceXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final logoSize = isMobile
                      ? (constraints.maxWidth < 400 ? 200.0 : 280.0)
                      : 480.0;
                  return _PublicSiteGestaoYahwehLogo(size: logoSize);
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Gestão YAHWEH",
              style: TextStyle(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.w900,
                color: ThemeCleanPremium.primary,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Um sistema de excelência feito para sua igreja",
              style: TextStyle(
                fontSize: isMobile ? 15 : 20,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    unawaited(PublicSiteAnalytics.logMarketingAction(
                        'marketing_hero_login'));
                    Navigator.pushNamed(context, '/igreja/login');
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Login'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeCleanPremium.primary,
                    side: const BorderSide(color: ThemeCleanPremium.primary),
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd)),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    unawaited(PublicSiteAnalytics.logMarketingAction(
                        'marketing_hero_planos'));
                    Navigator.pushNamed(context, '/planos');
                  },
                  icon: const Icon(Icons.star),
                  label: const Text('Ver planos'),
                ),
                TextButton.icon(
                  onPressed: onGoAdmin,
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Painel Master'),
                ),
              ],
            ),
          ],
        ),
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
            "App + Painel Web + Site publico\nEventos, escalas e financeiro\nBackups automaticos e seguranca",
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
    (icon: Icons.public_rounded, label: 'Site público integrado ao sistema'),
    (icon: Icons.inventory_2_rounded, label: 'Controle de patrimônio'),
    (icon: Icons.account_balance_wallet_rounded, label: 'Controle financeiro'),
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
              'Android e iOS no mesmo pacote. Use o link abaixo para baixar.',
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
                final androidUrl = (data['androidUrl'] ?? '').toString();
                final iosUrl = (data['iosUrl'] ?? '').toString();
                final downloadUrl = androidUrl.isNotEmpty
                    ? androidUrl
                    : (iosUrl.isNotEmpty ? iosUrl : folderUrl);

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: downloadUrl.isEmpty
                          ? null
                          : () => _open(downloadUrl),
                      icon: const Icon(Icons.android),
                      label: const Text('Android'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: downloadUrl.isEmpty
                          ? null
                          : () => _open(downloadUrl),
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

class _ChurchLookupCard extends StatelessWidget {
  final TextEditingController emailCtrl;
  final bool loading;
  final String? statusMsg;
  final Map<String, dynamic>? church;
  final VoidCallback onLoad;
  final VoidCallback? onEnter;
  final ValueChanged<String>? onEmailChanged;

  const _ChurchLookupCard({
    required this.emailCtrl,
    required this.loading,
    required this.statusMsg,
    required this.church,
    required this.onLoad,
    required this.onEnter,
    this.onEmailChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E7EF)),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Acessar minha igreja", style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: onEmailChanged,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                hintText: 'seu@email.com',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : () => onLoad(),
                    icon: loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: const Text("Carregar igreja"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEnter,
                    child: const Text("Abrir igreja"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (statusMsg != null)
              Text(
                statusMsg!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            if (church != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE4E7EF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (context) {
                        final logoRaw =
                            (church?['logoUrl'] ?? '').toString().trim();
                        final logo = sanitizeImageUrl(logoRaw);
                        final showLogo = logoRaw.isNotEmpty &&
                            isValidImageUrl(logo);
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (showLogo) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SafeNetworkImage(
                                  imageUrl: logo,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 112,
                                  memCacheHeight: 112,
                                  skipFreshDisplayUrl: false,
                                  placeholder: Container(
                                    width: 56,
                                    height: 56,
                                    alignment: Alignment.center,
                                    color: const Color(0xFFE8EEF5),
                                    child: const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  errorWidget: const SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Icon(Icons.church_rounded,
                                        color: Colors.black26, size: 32),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (church?["name"] ??
                                            church?["tenantName"] ??
                                            "Igreja encontrada")
                                        .toString(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Tenant: ${(church?["tenantId"] ?? "").toString()}",
                                    style:
                                        const TextStyle(color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              'Digite o e-mail do gestor ou o da sua ficha de membro: a busca começa sozinha após você parar de digitar, ou use "Carregar igreja". Depois "Abrir igreja" ou Entrar no menu (login com e-mail e senha).',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

