import 'dart:async';

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/app_theme.dart' show SaaSContentViewport;
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
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
  final String? initialOpenAvisoDocId;
  const MuralPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
    this.embeddedInShell = false,
    this.onShellBack,
    this.initialOpenAvisoDocId,
  });

  @override
  State<MuralPage> createState() => _MuralPageState();
}

class _MuralPageState extends State<MuralPage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _insightsTabActivated = false;
  final GlobalKey<InstagramMuralState> _muralFeedKey =
      GlobalKey<InstagramMuralState>();

  String _effectiveTenantId = '';
  String _churchSlug = '';
  Map<String, dynamic>? _tenantData;

  bool get _canWriteAvisos => AppPermissions.canManageChurchMuralEventsAgenda(
        widget.role,
        permissions: widget.permissions,
      );

  bool get _canModerateAvisosComments => _canWriteAvisos;

  @override
  void initState() {
    super.initState();
    _effectiveTenantId = widget.tenantId;
    _churchSlug = widget.tenantId;
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 1) _insightsTabActivated = true;
      if (mounted) setState(() {});
    });
    unawaited(_resolveTenantBundleBackground());
  }

  @override
  void didUpdateWidget(covariant MuralPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _effectiveTenantId = widget.tenantId;
      _churchSlug = widget.tenantId;
      _tenantData = null;
      unawaited(_resolveTenantBundleBackground());
    }
  }

  /// Slug/tenant operacional em background — feed arranca com [widget.tenantId].
  Future<void> _resolveTenantBundleBackground() async {
    try {
      final bundle = await ChurchTenantResilientReads.loadTenantBundle(
        widget.tenantId,
        userUid: firebaseDefaultAuth.currentUser?.uid,
      ).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _effectiveTenantId = bundle.firestoreTenantId;
        _churchSlug = bundle.churchSlug;
        _tenantData = bundle.tenantData;
      });
    } catch (_) {}
  }

  Future<void> _onRefresh() async {
    await _muralFeedKey.currentState?.refreshFeed();
    await _resolveTenantBundleBackground();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
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
        child: Column(
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
                  bottom: BorderSide(color: Colors.grey.shade200, width: 1),
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
                        tenantId: _effectiveTenantId,
                        role: widget.role,
                        churchSlug: _churchSlug,
                        initialTenantData: _tenantData,
                        permissions: widget.permissions,
                        initialOpenAvisoDocId: widget.initialOpenAvisoDocId,
                      ),
                    ),
                  ),
                  if (_insightsTabActivated)
                    ChurchAvisosInsightsDashboard(
                      tenantId: _effectiveTenantId,
                      canModerateComments: _canModerateAvisosComments,
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
