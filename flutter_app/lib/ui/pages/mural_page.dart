import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_theme.dart' show SaaSContentViewport;
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_avisos_insights_dashboard.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import '../widgets/instagram_mural.dart';

class MuralPage extends StatefulWidget {
  final String tenantId;
  final String role;
  final List<String>? permissions;
  /// Evita AppBar duplicada quando aberto dentro de [IgrejaCleanShell].
  final bool embeddedInShell;
  final VoidCallback? onShellBack;
  const MuralPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
    this.embeddedInShell = false,
    this.onShellBack,
  });

  @override
  State<MuralPage> createState() => _MuralPageState();
}

class _MuralPageState extends State<MuralPage>
    with SingleTickerProviderStateMixin {
  int _slugRetryKey = 0;
  late TabController _tab;
  bool _insightsTabActivated = false;
  final GlobalKey<InstagramMuralState> _muralFeedKey =
      GlobalKey<InstagramMuralState>();

  bool get _canWriteAvisos => AppPermissions.canManageChurchMuralEventsAgenda(
        widget.role,
        permissions: widget.permissions,
      );

  bool get _canModerateAvisosComments => _canWriteAvisos;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 1) _insightsTabActivated = true;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// Resolve o tenant com o mesmo ID que as regras Firestore usam para [sameChurch],
  /// depois lê slug / fallback com rede ou cache.
  Future<({
    String firestoreTenantId,
    String churchSlug,
    Map<String, dynamic> tenantData,
  })> _loadTenantAndSlug() async {
    await ensureFirebaseReadyForPublishUpload();
    final uid = firebaseDefaultAuth.currentUser?.uid;
    final tid =
        await TenantResolverService.resolveEffectiveTenantIdPreferringUserBinding(
      widget.tenantId,
      userUid: uid,
    );
    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tid)
          .get(const GetOptions(source: Source.serverAndCache));
    } catch (_) {
      snap = await firebaseDefaultFirestore
          .collection('igrejas')
          .doc(tid)
          .get(const GetOptions(source: Source.cache));
    }
    final data = snap.data() ?? {};
    final slug = (data['slug'] ?? '').toString().trim();
    final churchSlug = slug.isEmpty ? tid : slug;
    return (
      firestoreTenantId: tid,
      churchSlug: churchSlug,
      tenantData: data,
    );
  }

  Future<void> _onRefresh() async {
    await _muralFeedKey.currentState?.refreshFeed();
    setState(() => _slugRetryKey++);
  }

  String? _muralModuleBarSubtitle() {
    final user = firebaseDefaultAuth.currentUser;
    final dn = (user?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final email = (user?.email ?? '').trim();
    return email.isNotEmpty ? email : null;
  }

  static const _muralTabs = [
    Tab(text: 'Feed'),
    Tab(text: 'Painel'),
  ];

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final showAppBar =
        !widget.embeddedInShell && (!isMobile || Navigator.canPop(context));
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      floatingActionButton: _tab.index == 0 && _canWriteAvisos
          ? Container(
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg),
                gradient: LinearGradient(
                  colors: [
                    ThemeCleanPremium.primary,
                    ThemeCleanPremium.primaryLight,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.38),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  ...ThemeCleanPremium.softUiCardShadow,
                ],
              ),
              child: FloatingActionButton.extended(
                onPressed: () =>
                    _muralFeedKey.currentState?.openNewAvisoEditor(),
                icon: const Icon(Icons.add_a_photo_rounded, size: 24),
                label: const Text(
                  'Novo aviso',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                hoverElevation: 0,
                focusElevation: 0,
                highlightElevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusLg),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      appBar: !showAppBar
          ? null
          : AppBar(
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar',
                      style: IconButton.styleFrom(
                          minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget)),
                    )
                  : null,
              backgroundColor: ThemeCleanPremium.primary,
              foregroundColor: Colors.white,
              title: const Text('Mural de Avisos'),
              bottom: TabBar(
                controller: _tab,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: _muralTabs,
              ),
            ),
      body: SafeArea(
        top: widget.onShellBack == null,
        child: FutureBuilder<
            ({
              String firestoreTenantId,
              String churchSlug,
              Map<String, dynamic> tenantData,
            })>(
          key: ValueKey(_slugRetryKey),
          future: _loadTenantAndSlug(),
          builder: (context, snap) {
            if (snap.hasError) {
              return ChurchPanelErrorBody(
                title: 'Não foi possível carregar o mural',
                error: snap.error,
                onRetry: () => setState(() => _slugRetryKey++),
              );
            }
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const ChurchPanelLoadingBody();
            }
            final data = snap.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.onShellBack != null)
                  ChurchEmbeddedModuleBar(
                    title: 'Mural de Avisos',
                    icon: kChurchShellNavEntries[7].icon,
                    accent: kChurchShellNavEntries[7].accent,
                    onBack: widget.onShellBack!,
                    subtitle: _muralModuleBarSubtitle(),
                  ),
                if (!showAppBar)
                  Material(
                    color: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shape: Border(
                      bottom:
                          BorderSide(color: Colors.grey.shade200, width: 1),
                    ),
                    child: ChurchPanelPillTabBar(
                      controller: _tab,
                      dense: true,
                      style: ChurchPanelPillTabBarStyle.onLight,
                      tabs: _muralTabs,
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      RefreshIndicator(
                        onRefresh: _onRefresh,
                        child: SaaSContentViewport(
                          child: InstagramMural(
                            key: _muralFeedKey,
                            tenantId: data.firestoreTenantId,
                            role: widget.role,
                            churchSlug: data.churchSlug,
                            initialTenantData: data.tenantData,
                            permissions: widget.permissions,
                          ),
                        ),
                      ),
                      if (_insightsTabActivated)
                        ChurchAvisosInsightsDashboard(
                          tenantId: data.firestoreTenantId,
                          canModerateComments: _canModerateAvisosComments,
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
