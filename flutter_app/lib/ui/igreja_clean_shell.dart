import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/core/theme_mode_provider.dart';
import 'package:gestao_yahweh/services/express_renew_bootstrap.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/services/payment_ui_feedback_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/services/church_sign_out_navigation.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';
import 'package:gestao_yahweh/services/tenant_intelligent_preload.dart';
import 'package:gestao_yahweh/services/app_resume_state_service.dart';
import 'package:gestao_yahweh/services/app_session_stability.dart';
import 'package:gestao_yahweh/services/church_tenant_dashboard_warmup_service.dart';
import 'package:gestao_yahweh/services/yahweh_performance_monitor.dart';
import 'package:gestao_yahweh/services/church_cluster_sync_service.dart';
import 'package:gestao_yahweh/services/church_tenant_consolidation_service.dart';
import 'package:gestao_yahweh/services/fcm_service.dart';
import 'package:gestao_yahweh/core/tenant/tenant_migration_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/church_panel_tenant_gateway.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
import 'package:gestao_yahweh/core/panel_scroll_bridge.dart';
import 'package:gestao_yahweh/services/church_client_session_reporter.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/avatar_gestor_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show imageUrlFromMap;
import 'pages/igreja_dashboard_moderno.dart';
import 'pages/igreja_cadastro_page.dart';
import 'pages/departments_page.dart';
import 'pages/events_manager_page.dart';
import 'pages/finance_page.dart';
import 'pages/patrimonio_page.dart';
import 'pages/fornecedores_page.dart';
import 'pages/member_card_page.dart';
import 'pages/members_page.dart';
import 'pages/mural_page.dart';
import 'pages/my_schedules_page.dart';
import 'pages/plans/renew_plan_page.dart';
import 'pages/subscription_expired_page.dart';
import 'pages/schedules_page.dart';
import 'pages/certificados_page.dart';
import 'pages/church_letters_page.dart';
import 'pages/prayer_requests_page.dart';
import 'pages/visitors_page.dart';
import 'pages/cargos_page.dart';
import 'pages/calendar_page.dart';
import 'pages/sistema_informacoes_page.dart';
import 'pages/configuracoes_page.dart';
import 'pages/church_chat_hub_page.dart';
import 'pages/relatorios_page.dart';
import 'pages/aprovar_membros_pendentes_page.dart';
import 'package:gestao_yahweh/ui/widgets/ios_donation_reader_view.dart';
import 'pages/church_donations_page.dart';
import '../services/app_permissions.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import '../services/migrate_members_to_membros_service.dart';
import 'widgets/church_panel_app_update_banner.dart';
import 'widgets/version_footer.dart';
import 'widgets/module_header_premium.dart';
import 'widgets/connectivity_offline_strip.dart';
import 'widgets/church_panel_ui_helpers.dart';
import 'widgets/gestor_welcome_dialog.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/church_shell_lazy_module_policy.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/ui/widgets/church_shell_nav_icon.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/license_access_policy.dart';
import 'package:gestao_yahweh/services/auth_gate_panel_role.dart';
import 'package:gestao_yahweh/app_theme.dart';
import 'package:gestao_yahweh/ui/widgets/church_global_search_dialog.dart';
import 'package:gestao_yahweh/ui/widgets/church_notification_bell.dart';
import 'package:gestao_yahweh/ui/widgets/instagram_mural.dart'
    show MuralAvisoEditorPage;
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_panel_local_cache.dart';
import 'package:gestao_yahweh/services/igreja_direct_firestore_reads.dart';
import 'package:gestao_yahweh/services/church_shell_tenant_load_service.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/auth_profile_cache_service.dart';

/// Breakpoints: >= 900 desktop (sidebar fixa), < 900 mobile (drawer), < 600 phone (layout compacto)
const double _breakpointDesktop = 900;

const double _breakpointPhone = 600;

/// Ãcone, label e cor do mÃ³dulo (menu lateral + drawer + rodapÃ©).
class _NavItem {
  final IconData icon;
  final String label;
  final Color accent;

  const _NavItem(this.icon, this.label, this.accent);
}

/// Shell Clean Premium â€” Sidebar vertical azul escuro (Desktop) / Drawer (Mobile).
/// Header com saudaÃ§Ã£o e card Plano/Vencimento.
class IgrejaCleanShell extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final String role;
  final bool trialExpired;
  final Map<String, dynamic>? subscription;

  /// Legado: campo no cadastro do membro; o painel Financeiro nÃ£o usa mais para liberar acesso.
  final bool? podeVerFinanceiro;

  /// Legado; patrimÃ³nio no painel sÃ³ para o nÃºcleo financeiro/pastoral.
  final bool? podeVerPatrimonio;

  /// Legado; fornecedores no painel sÃ³ para o mesmo nÃºcleo.
  final bool? podeVerFornecedores;

  /// Gestor libera PDFs de membros/aniversariantes etc. (senÃ£o sÃ³ RelatÃ³rio de Eventos).
  final bool? podeEmitirRelatoriosCompletos;

  /// PermissÃµes especÃ­ficas por mÃ³dulo (RBAC granular), ex.: ['financeiro','membros'].
  final List<String>? permissions;

  /// Abre Membros com a ficha deste id (ex.: leitura do QR da carteirinha por gestor).
  final String? initialOpenMemberDocId;

  /// Abre direto um mÃ³dulo do menu (ex.: [kChurchShellIndexMySchedules] apÃ³s push de escala).
  final int? initialShellIndex;

  const IgrejaCleanShell({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    required this.trialExpired,
    this.subscription,
    this.podeVerFinanceiro,
    this.podeVerPatrimonio,
    this.podeVerFornecedores,
    this.podeEmitirRelatoriosCompletos,
    this.permissions,
    this.initialOpenMemberDocId,
    this.initialShellIndex,
  });

  @override
  State<IgrejaCleanShell> createState() => _IgrejaCleanShellState();
}

class _IgrejaCleanShellState extends State<IgrejaCleanShell>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;

  /// Desktop web: menu lateral estreito sÃ³ com Ã­cones (+ tooltip).
  bool _sidebarCollapsed = false;

  /// Foto do usuÃ¡rio vinda do Firestore (quando Auth photoURL estÃ¡ vazio).
  String? _userPhotoUrlFromFirestore;

  /// Cache das pÃ¡ginas do menu para manter estado ao trocar de aba ou ao voltar ao app (evita recarregar e tela preta).
  final List<Widget?> _pageCache = List.filled(25, null);
  bool _showPaymentConfirmedBanner = false;
  int _lastPaymentTick = 0;
  int _paymentBannerAnimSeed = 0;
  int _lastSubscriptionSyncMs = 0;

  /// Recria a subscriÃ§Ã£o ao doc da igreja apÃ³s falha de rede.
  int _tenantStreamRetry = 0;

  /// Ãšltimo snapshot vÃ¡lido â€” evita spinner ao voltar de outra aba (Controle Total).
  DocumentSnapshot<Map<String, dynamic>>? _lastGoodTenantDoc;

  /// Evita loop ao hidratar cache local apÃ³s falha transitÃ³ria do stream.
  bool _tenantFallbackHydrateScheduled = false;

  /// Bootstrap one-shot â€” sem StreamBuilder Firestore (evita INTERNAL ASSERTION web).
  bool _shellTenantBootstrapRunning = false;
  Object? _shellTenantLastError;

  /// Papel efectivo no menu (upgrade se claims atrasados mas e-mail = gestor).
  String? _roleOverride;

  String get _panelRole {
    final override = (_roleOverride ?? '').trim().toLowerCase();
    if (override.isNotEmpty) return override;
    return widget.role.trim().toLowerCase();
  }

  bool get _canPurchaseLicense =>
      AppPermissions.canPurchaseChurchLicense(_panelRole);

  /// Android/Web: botÃ£o Â«Alterar planoÂ». iOS Reader: oculto (Apple 3.1.1).
  bool get _showUpgradePlanUi =>
      _canPurchaseLicense && !IosPaymentsGate.hideInAppPlanPurchaseUi;

  void _syncPanelRoleFromChurch(Map<String, dynamic>? churchData) {
    final user = firebaseDefaultAuth.currentUser;
    final resolved = AuthGatePanelRole.resolve(
      roleFromClaims: widget.role,
      roleFromUserDoc: widget.role,
      roleFromCache: widget.role,
      churchData: churchData,
      userEmail: user?.email,
    );
    if (resolved == _panelRole) return;
    if (!AppPermissions.isRestrictedMember(widget.role)) return;
    if (_roleOverride == resolved) return;
    if (mounted) setState(() => _roleOverride = resolved);
  }

  /// Doc canÃ³nico (`departamentos`, chat, slug) â€” resolvido uma vez no arranque/resume.
  String? _operationalTenantId;

  /// Evita montar mÃ³dulos com tenant errado antes do resolve (web IndexedStack).
  bool _tenantResolveComplete = false;

  ValueKey _shellPageKey(int index) =>
      ValueKey('page_${index}_$_moduleTenantId');

  /// Sempre doc canônico — nunca slug legado nos módulos do shell.
  String get _moduleTenantId {
    final ctx = ChurchContextService.currentChurchId?.trim() ?? '';
    if (ctx.isNotEmpty) return ctx;
    final op = (_operationalTenantId ?? '').trim();
    if (op.isNotEmpty) return ChurchPanelTenant.resolve(op);
    return ChurchPanelTenant.resolve(widget.tenantId.trim());
  }

  /// Evita enfileirar [addPostFrameCallback] a cada frame do StreamBuilder (estresse no UI thread).
  String _lastSubscriptionGuardSignature = '';

  /// Busca global (Ctrl/Cmd+K): sÃ³ quando o painel principal estÃ¡ liberado.
  bool _globalSearchAllowed = false;
  bool _globalSearchDialogVisible = false;
  String? _shellBootstrapMemberSearch;
  String? _shellBootstrapEventSearch;
  String? _shellBootstrapPatrimonioSearch;

  /// Um disparo: abrir ficha do membro ao entrar pelo QR (gestor).
  String? _shellBootstrapOpenMemberId;
  String? _shellBootstrapOpenEventDocId;
  String? _shellBootstrapOpenAvisoDocId;
  String? _shellBootstrapOpenPatrimonioDocId;

  /// PrÃ©-carrega dados ao passar o rato no menu (web/desktop).
  final Set<int> _shellPrefetchDone = {};

  /// Ãcones **Material `*_rounded`**. Na web (release), o subset da fonte pode
  /// omitir glifos â€” [kChurchShellNavEntries] + [_ChurchShellNavMaterialIconsKeepalive]
  /// e `--no-tree-shake-icons` nos scripts.
  late final List<_NavItem> _items = [
    for (final e in kChurchShellNavEntries) _NavItem(e.icon, e.label, e.accent),
  ];

  bool get _isDesktop => MediaQuery.sizeOf(context).width >= _breakpointDesktop;
  bool get _isMobile => MediaQuery.sizeOf(context).width < _breakpointDesktop;
  bool get _isPhone => MediaQuery.sizeOf(context).width < _breakpointPhone;

  Widget _wrapShellMobileModule(int index, Widget page) => page;

  Future<void> _openUpgradePlans() async {
    if (!mounted) return;
    if (!_canPurchaseLicense) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Somente gestor, secretÃ¡rio ou tesoureiro pode renovar a licenÃ§a. '
            'PeÃ§a a um deles para gerar o pagamento.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // iOS Reader: sem checkout nem link de vendas no app.
    if (IosPaymentsGate.hideInAppPlanPurchaseUi) {
      return;
    }
    unawaited(ExpressRenewBootstrap.instance.warmUp());
    Navigator.push(
      context,
      ThemeCleanPremium.fadeSlideRoute(
        RenewPlanPage(panelRole: _panelRole),
      ),
    );
  }

  Widget? _buildChurchBottomNavigationBar() {
    if (!_isMobile) return null;
    // RodapÃ© + atalhos coloridos Super Premium (cores alinhadas a [kChurchShellNavEntries]).
    // Painel, Membros, Eventos, Agenda, Avisos, Chat â€” drawer no menu superior.
    final shortcuts = <_ChurchShellFooterShortcut>[
      _ChurchShellFooterShortcut(
        shellIndex: 0,
        shortLabel: 'Painel',
        accent: kChurchShellNavEntries[0].accent,
      ),
      _ChurchShellFooterShortcut(
        shellIndex: ChurchShellIndices.membros,
        shortLabel: 'Membros',
        accent: kChurchShellNavEntries[ChurchShellIndices.membros].accent,
      ),
      _ChurchShellFooterShortcut(
        shellIndex: ChurchShellIndices.muralEventos,
        shortLabel: 'Eventos',
        accent: kChurchShellNavEntries[ChurchShellIndices.muralEventos].accent,
      ),
      _ChurchShellFooterShortcut(
        shellIndex: ChurchShellIndices.agenda,
        shortLabel: 'Agenda',
        accent: kChurchShellNavEntries[ChurchShellIndices.agenda].accent,
      ),
      _ChurchShellFooterShortcut(
        shellIndex: ChurchShellIndices.muralAvisos,
        shortLabel: 'Avisos',
        accent: kChurchShellNavEntries[ChurchShellIndices.muralAvisos].accent,
      ),
      _ChurchShellFooterShortcut(
        shellIndex: ChurchShellIndices.chatIgreja,
        shortLabel: 'Chat',
        accent: kChurchShellNavEntries[ChurchShellIndices.chatIgreja].accent,
      ),
    ];

    return Material(
      color: Colors.white,
      elevation: 0,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Color.lerp(Colors.white, const Color(0xFFEFF6FF), 0.5)!,
                  ],
                ),
                border: Border(
                  top: BorderSide(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final count = shortcuts.length;
                  final slotW = constraints.maxWidth / count;
                  final circleSize =
                      (slotW * 0.76).clamp(42.0, 50.0).toDouble();
                  final glyphSize =
                      (circleSize * 0.52).clamp(22.0, 26.0).toDouble();
                  final labelSize =
                      constraints.maxWidth < 340 ? 9.5 : 10.0;
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
                    child: Row(
                      children: [
                        for (var s = 0; s < shortcuts.length; s++)
                          Expanded(
                            child: _PremiumShellFooterShortcut(
                              shellIndex: shortcuts[s].shellIndex,
                              shortLabel: shortcuts[s].shortLabel,
                              accent: shortcuts[s].accent,
                              opensDrawer: shortcuts[s].opensDrawer,
                              icon: shortcuts[s].opensDrawer
                                  ? Icons.menu_rounded
                                  : _items[shortcuts[s].shellIndex!].icon,
                              fullTooltip: shortcuts[s].opensDrawer
                                  ? 'Mais opÃ§Ãµes (menu lateral)'
                                  : _items[shortcuts[s].shellIndex!].label,
                              selected: shortcuts[s].opensDrawer
                                  ? false
                                  : _selectedIndex == shortcuts[s].shellIndex,
                              circleSize: circleSize,
                              iconSize: glyphSize,
                              labelFontSize: labelSize,
                              onTap: () {
                                if (shortcuts[s].opensDrawer) {
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _scaffoldKey.currentState?.openDrawer();
                                  });
                                  return;
                                }
                                final idx = shortcuts[s].shellIndex!;
                                if (!_canAccessItem(idx)) {
                                  _showPanelSnack(
                                    'Sem acesso a este mÃ³dulo.',
                                    isError: true,
                                  );
                                  return;
                                }
                                _prefetchShellModuleData(idx);
                                TenantIntelligentPreload
                                    .scheduleModuleForShellIndex(
                                  _moduleTenantId,
                                  idx,
                                );
                                if (_pageCache[idx] == null) {
                                  _pageCache[idx] = _buildPageForIndex(idx);
                                }
                                setState(() => _selectedIndex = idx);
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const ChurchShellBottomVerseStrip(),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final hint = widget.tenantId.trim();
    if (hint.isNotEmpty) {
      final canonical = ChurchPanelTenant.resolve(hint);
      _operationalTenantId = canonical;
      ChurchContextService.bindPanelIdImmediate(
        seed: hint,
        canonicalId: canonical,
        userUid: firebaseDefaultAuth.currentUser?.uid,
      );
      _applyBoundChurchContextToLastGood(_operationalTenantId!);
      // Desbloqueia módulos no 1.º frame — bind async continua em background.
      _tenantResolveComplete = _operationalTenantId!.isNotEmpty;
    }
    unawaited(_warmTenantDocFromLocalCacheFirst());
    WidgetsBinding.instance.addObserver(this);
    AppSessionStability.registerResumeListener(_onGlobalSessionResume);
    final rawOpen = widget.initialOpenMemberDocId?.trim() ?? '';
    _shellBootstrapOpenMemberId = rawOpen.isEmpty ? null : rawOpen;
    HardwareKeyboard.instance.addHandler(_onShellHardwareKey);
    _loadUserPhotoFromFirestore();
    _lastPaymentTick = PaymentUiFeedbackService.paymentConfirmedTick.value;
    PaymentUiFeedbackService.paymentConfirmedTick
        .addListener(_onPaymentConfirmedTick);
    // MigraÃ§Ã£o automÃ¡tica members â†’ membros (servidor Admin SDK + fallback cliente)
    ChurchPanelNavigationBridge.instance.registerShellNavigator((idx) {
      if (!mounted) return;
      if (!_canAccessItem(idx)) return;
      setState(() => _selectedIndex = idx);
      if (idx == ChurchShellIndices.chatIgreja) {
        _pageCache[idx] ??= _buildPageForIndex(idx);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ChurchPanelNavigationBridge.instance.renotifyPendingChatThreadOpen();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited((() async {
        unawaited(ensureFirebaseReadyForPanelRead().catchError((_) {}));
        if (kIsWeb) {
          unawaited(FirestoreWebGuard.ensurePanelReadReady().catchError((_) {}));
        }
        try {
          await _resolveOperationalTenant(forceRefresh: false).timeout(
            const Duration(seconds: 6),
            onTimeout: () {},
          );
          await _bootstrapShellTenantDoc(forceRefresh: false).timeout(
            const Duration(seconds: 10),
            onTimeout: () {},
          );
        } catch (_) {}
        finally {
          if (mounted) setState(() => _tenantResolveComplete = true);
        }
        ChurchTenantConsolidationService.ensureConsolidated(
          _moduleTenantId,
          source: 'igreja_clean_shell',
        );
        reportChurchClientSessionToUserDoc();
        _runMembersToMembrosMigration();
        _schedulePostTenantWarmups();
        YahwehPerformanceMonitor.markScreenStart('church_shell');
        YahwehPerformanceMonitor.markScreenReadyAfterFirstFrame('church_shell');
        Future<void>.delayed(const Duration(seconds: 12), () {
          if (mounted) unawaited(_bootstrapChatPresenceHeartbeat());
        });
        if (_shellBootstrapOpenMemberId != null && mounted) {
          setState(() => _selectedIndex = ChurchShellIndices.membros);
        } else {
          // Sempre painel inicial ao entrar â€” sem restaurar aba/chat/mÃ³dulo anterior.
          if (widget.initialShellIndex != null &&
              mounted &&
              _canAccessItem(widget.initialShellIndex!)) {
            setState(() => _selectedIndex = widget.initialShellIndex!);
          }
        }
        unawaited(
          AppResumeStateService.saveShellContext(
            tenantId: _moduleTenantId,
            shellIndex: 0,
          ),
        );
        unawaited(GestorWelcomeDialog.tryShowIfNeeded(
          context: context,
          tenantId: _moduleTenantId,
          role: _panelRole,
        ));
      })());
    });
  }

  /// Cache local do cadastro — pinta o shell no 1.º frame (web cold start).
  Future<void> _warmTenantDocFromLocalCacheFirst() async {
    final tid = _moduleTenantId.trim();
    if (tid.isEmpty) return;
    if (_applyBoundChurchContextToLastGood(tid)) {
      if (mounted) setState(() {});
      return;
    }

    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      final peek = AuthProfileCacheService.instance.peek(uid);
      if (peek != null) {
        final profileChurch = peek['church'];
        final profileId = ChurchPanelTenant.resolve(
          (peek['igrejaId'] ?? '').toString(),
        );
        if (profileId.isNotEmpty &&
            profileId == ChurchPanelTenant.resolve(tid) &&
            profileChurch is Map &&
            profileChurch.isNotEmpty) {
          _storeTenantDocSnapshot(
            profileId,
            Map<String, dynamic>.from(profileChurch),
          );
          if (mounted) setState(() {});
          return;
        }
      }
    }

    try {
      final local = await ChurchShellTenantLoadService.tryLocal(
        seedTenantId: widget.tenantId,
      );
      if (local != null && local.data.isNotEmpty && mounted) {
        _storeTenantDocSnapshot(local.churchId, local.data);
        setState(() {});
        return;
      }
    } catch (_) {}

    try {
      final cached = await ChurchPanelLocalCache.readMap(
        churchId: tid,
        module: ChurchPanelLocalCache.moduleCadastro,
        maxAge: const Duration(days: 30),
      );
      if (cached != null && cached.isNotEmpty && mounted) {
        _storeTenantDocSnapshot(tid, cached);
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    AppSessionStability.unregisterResumeListener(_onGlobalSessionResume);
    WidgetsBinding.instance.removeObserver(this);
    ChatPresenceEngine.stopAppWideHeartbeat();
    ChurchPanelNavigationBridge.instance.unregisterShellNavigator();
    HardwareKeyboard.instance.removeHandler(_onShellHardwareKey);
    PaymentUiFeedbackService.paymentConfirmedTick
        .removeListener(_onPaymentConfirmedTick);
    super.dispose();
  }

  Future<void> _resolveOperationalTenant({bool forceRefresh = false}) async {
    final raw = widget.tenantId.trim();
    if (raw.isEmpty) return;
    final uid = firebaseDefaultAuth.currentUser?.uid;
    try {
      final effective = await ChurchContextService.resolveAndBind(
        seed: raw,
        userUid: uid,
        forceRefresh: forceRefresh,
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final canonical = ChurchPanelTenant.resolve(effective);
      final changed = canonical != (_operationalTenantId ?? '').trim();
      if (changed || _operationalTenantId == null) {
        setState(() {
          _operationalTenantId = canonical;
          for (var i = 0; i < _pageCache.length; i++) {
            _pageCache[i] = null;
          }
        });
        _reconfigureFcmForOperationalTenant(canonical);
      }
      ChurchClusterSyncService.syncForOperationalTenant(canonical);
      ChurchTenantConsolidationService.ensureConsolidated(
        canonical,
        force: forceRefresh,
        source: 'shell_resolve_tenant',
      );
      unawaited(
        TenantMigrationService.runAfterBind(
          churchIdHint: canonical,
          seedHint: raw,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      if (_operationalTenantId == null || _operationalTenantId!.trim().isEmpty) {
        final fallback = ChurchPanelTenant.resolve(
          ChurchContextService.currentChurchId ?? raw,
        );
        ChurchOperationalPaths.rememberResolved(raw, fallback, userUid: uid);
        setState(() => _operationalTenantId = fallback);
      }
    }
  }

  void _reconfigureFcmForOperationalTenant(String operationalId) {
    if (kIsWeb) return;
    final u = firebaseDefaultAuth.currentUser;
    if (u == null) return;
    unawaited(
      FcmService.instance.configure(
        uid: u.uid,
        tenantId: operationalId,
        cpf: widget.cpf,
        role: _panelRole,
        forceRefresh: true,
      ),
    );
  }

  bool _applyBoundChurchContextToLastGood(String tid) {
    final want = ChurchPanelTenant.resolve(tid);
    if (want.isEmpty) return false;
    final ctxId = ChurchContextService.currentChurchId?.trim() ?? '';
    final data = ChurchContextService.currentChurchData;
    if (data == null || data.isEmpty) return false;
    final bound = ChurchPanelTenant.resolve(ctxId);
    if (bound != want && ctxId != want) return false;
    _lastGoodTenantDoc = _CachedChurchDocumentSnapshot(id: want, data: data);
    _syncPanelRoleFromChurch(data);
    return true;
  }

  void _storeTenantDocSnapshot(
    String tid,
    Map<String, dynamic> data, {
    DocumentSnapshot<Map<String, dynamic>>? snap,
  }) {
    if (tid.isEmpty || data.isEmpty) return;
    _lastGoodTenantDoc =
        snap ?? _CachedChurchDocumentSnapshot(id: tid, data: data);
    _syncPanelRoleFromChurch(data);
    ChurchContextService.bindChurchData(churchId: tid, data: data);
  }

  /// Cache-first â€” **sem** StreamBuilder (`.get()` Ãºnico via [ChurchShellTenantLoadService]).
  Future<void> _bootstrapShellTenantDoc({bool forceRefresh = false}) async {
    if (_shellTenantBootstrapRunning) return;
    _shellTenantBootstrapRunning = true;
    final tid = _moduleTenantId.trim();
    if (tid.isEmpty) {
      _shellTenantBootstrapRunning = false;
      return;
    }
    if (!forceRefresh && _applyBoundChurchContextToLastGood(tid)) {
      _shellTenantBootstrapRunning = false;
      if (mounted) setState(() {});
      return;
    }
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final result = await ChurchShellTenantLoadService.load(
        seedTenantId: widget.tenantId,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      if (ChurchShellTenantLoadService.isUsable(result)) {
        _shellTenantLastError = result.softError;
        _storeTenantDocSnapshot(
          result.churchId,
          ChurchCadastroLoadService.sliceCadastroFormFields(result.data).isNotEmpty
              ? ChurchCadastroLoadService.sliceCadastroFormFields(result.data)
              : result.data,
        );
        await ChurchShellTenantLoadService.persistAfterLoad(result);
      } else {
        _shellTenantLastError = result.softError ??
            'Não foi possível carregar igrejas/$tid.';
        if (result.data.isNotEmpty) {
          _storeTenantDocSnapshot(
            result.churchId.isNotEmpty ? result.churchId : tid,
            ChurchCadastroLoadService.sliceCadastroFormFields(result.data),
          );
        } else {
          await _hydrateTenantDocFromFallbacks(tid);
        }
      }
    } catch (e) {
      _shellTenantLastError = e;
      await _hydrateTenantDocFromFallbacks(tid);
    } finally {
      _shellTenantBootstrapRunning = false;
      if (mounted) setState(() {});
    }
  }

  @Deprecated('Use _bootstrapShellTenantDoc')
  Future<void> _preloadTenantDocSnapshot() =>
      _bootstrapShellTenantDoc(forceRefresh: false);

  Future<void> _hydrateTenantDocFromFallbacks(String tid) async {
    final id = tid.trim();
    if (id.isEmpty) return;
    if (_applyBoundChurchContextToLastGood(id)) return;

    try {
      final local = await ChurchShellTenantLoadService.tryLocal(
        seedTenantId: id,
      );
      if (local != null && local.data.isNotEmpty) {
        _storeTenantDocSnapshot(local.churchId, local.data);
        return;
      }
    } catch (_) {}

    final uid = firebaseDefaultAuth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      final peek = AuthProfileCacheService.instance.peek(uid);
      if (peek != null) {
        final profileChurch = peek['church'];
        final profileId = ChurchPanelTenant.resolve(
          (peek['igrejaId'] ?? '').toString(),
        );
        if (profileId.isNotEmpty &&
            profileId == ChurchPanelTenant.resolve(id) &&
            profileChurch is Map &&
            profileChurch.isNotEmpty) {
          _storeTenantDocSnapshot(
            profileId,
            Map<String, dynamic>.from(profileChurch),
          );
          return;
        }
      }
    }

    try {
      final cached = await ChurchPanelLocalCache.readMap(
        churchId: id,
        module: ChurchPanelLocalCache.moduleCadastro,
        maxAge: const Duration(days: 30),
      );
      if (cached != null && cached.isNotEmpty) {
        _storeTenantDocSnapshot(id, cached);
        return;
      }
    } catch (_) {}

    try {
      final direct = await IgrejaDirectFirestoreReads.readIgrejaDoc(id);
      if (direct != null && direct.data.isNotEmpty) {
        _storeTenantDocSnapshot(direct.docId, direct.data);
      }
    } catch (_) {}
  }

  Widget _buildTenantBootstrapScaffold({required Widget child}) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: SafeArea(child: child),
      ),
    );
  }

  void _retryTenantDocLoad() {
    _tenantFallbackHydrateScheduled = false;
    setState(() => _tenantStreamRetry++);
    unawaited(() async {
      await _resolveOperationalTenant(forceRefresh: false);
      await _bootstrapShellTenantDoc(forceRefresh: true);
      if (mounted) setState(() {});
    }());
  }

  void _schedulePostTenantWarmups() {
    final tid = _moduleTenantId.trim();
    if (tid.isEmpty) return;
    final warmupDelay = kIsWeb ? const Duration(seconds: 3) : const Duration(seconds: 4);
    final dashboardDelay = kIsWeb ? const Duration(seconds: 2) : const Duration(seconds: 2);
    Future<void>.delayed(warmupDelay, () {
      if (!mounted) return;
      unawaited(ChurchTenantOfflineWarmupService.instance
          .scheduleWarmupAfterLogin(tid));
    });
    Future<void>.delayed(dashboardDelay, () {
      if (!mounted) return;
      TenantIntelligentPreload.scheduleAfterDashboard(tid);
      unawaited(ChurchTenantDashboardWarmupService.scheduleAfterShellOpen(
        context,
        tid,
      ));
    });
  }

  Widget _buildShellGateBody() {
    final tid = _moduleTenantId.trim();
    var tenantDoc = _lastGoodTenantDoc;
    if ((tenantDoc == null || !tenantDoc.exists) && tid.isNotEmpty) {
      _applyBoundChurchContextToLastGood(tid);
      tenantDoc = _lastGoodTenantDoc;
    }
    final fallbackChurchData = ChurchContextService.currentChurchData;
    final hasCachedTenant =
        (tenantDoc != null && tenantDoc.exists) || fallbackChurchData != null;

    if (_shellTenantBootstrapRunning && !hasCachedTenant) {
      return _buildTenantBootstrapScaffold(
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (!hasCachedTenant) {
      if (!_tenantFallbackHydrateScheduled) {
        _tenantFallbackHydrateScheduled = true;
        unawaited(_bootstrapShellTenantDoc().then((_) {
          if (mounted) setState(() {});
        }));
        return _buildTenantBootstrapScaffold(
          child: ChurchPanelResilientLoadBanner(
            hasLocalData: false,
            isSyncing: true,
            syncMessage: 'Sincronizando cadastro da igreja (igrejas/$tid)…',
          ),
        );
      }
      return _buildTenantBootstrapScaffold(
        child: ChurchPanelResilientLoadBanner(
          hasLocalData: false,
          isSyncing: false,
          errorTitle: 'Não foi possível carregar os dados da igreja',
          error: _shellTenantLastError ??
              'Verifique sua conexão ou tente novamente. '
              'Path: igrejas/$tid',
          onRetry: _retryTenantDocLoad,
        ),
      );
    }

    final churchLive = tenantDoc?.data() ?? fallbackChurchData;
    final registrationComplete =
        (churchLive?['registrationComplete'] ?? true) == true;
    if (!registrationComplete) {
      return _buildCompleteCadastroObrigatorio();
    }
    final guard = SubscriptionGuard.evaluate(
        church: churchLive, subscription: widget.subscription);
    final bool legacyBlocked = churchLive != null
        ? LicenseAccessPolicy.licenseAccessBlocked(
            subscription: widget.subscription, church: churchLive)
        : widget.trialExpired;
    final bool licenseBlocked = guard.isFree
        ? guard.adminBlocked
        : (guard.blocked || legacyBlocked);
    _globalSearchAllowed = registrationComplete && !licenseBlocked;
    if (churchLive != null) {
      final sig =
          '${guard.blocked}|${guard.inGrace}|${guard.graceDaysLeft}|${guard.adminBlocked}|${guard.isFree}|${guard.statusAssinatura}';
      if (sig != _lastSubscriptionGuardSignature) {
        _lastSubscriptionGuardSignature = sig;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncSubscriptionSnapshot(guard);
        });
      }
    }

    if (licenseBlocked) {
      final churchName =
          (churchLive?['nome'] ?? churchLive?['name'] ?? 'Sua igreja')
              .toString();
      final logoUrl = imageUrlFromMap(churchLive);
      return _buildLicenseRenewalOnly(
        context,
        churchName: churchName,
        logoUrl: logoUrl.isEmpty ? null : logoUrl,
      );
    }
    final shellModuleFullBleed = _isMobile && _selectedIndex != 0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      drawer: _isMobile ? _buildDrawer() : null,
      drawerEdgeDragWidth: _isMobile ? 56 : null,
      bottomNavigationBar: _buildChurchBottomNavigationBar(),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              top: shellModuleFullBleed,
              left: true,
              right: true,
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isDesktop) _buildSidebar(),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: ThemeCleanPremium.churchPanelBodyGradient,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!shellModuleFullBleed)
                            _buildHeader(licenseBlocked: licenseBlocked),
                          const ConnectivityOfflineStrip(),
                          const ChurchPanelAppUpdateBanner(),
                          _buildPaymentConfirmedBanner(),
                          _buildGracePeriodBanner(guard),
                          if (_selectedIndex != 0)
                            ModuleHeaderPremium(
                              title: _items[_selectedIndex].label,
                              icon: _items[_selectedIndex].icon,
                              subtitle:
                                  _isMobile ? _shellUserGreetingName() : null,
                              onPainelBack: _isMobile && _selectedIndex != 0
                                  ? () => setState(() => _selectedIndex = 0)
                                  : null,
                            ),
                          Expanded(
                            child: Semantics(
                              container: true,
                              label:
                                  'ConteÃºdo do mÃ³dulo ${_items[_selectedIndex].label}',
                              child: Padding(
                                padding: EdgeInsets.zero,
                                child: SaaSContentViewport(
                                  maxWidthOverride: _selectedIndex ==
                                              ChurchShellIndices.patrimonio ||
                                          _selectedIndex ==
                                              ChurchShellIndices.chatIgreja
                                      ? 10000
                                      : null,
                                  child: _buildContent(),
                                ),
                              ),
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
          if (kIsWeb) const _ChurchShellNavMaterialIconsKeepalive(),
          if (!_isMobile) const ChurchShellBottomVerseStrip(),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant IgrejaCleanShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role != widget.role) {
      _roleOverride = null;
      _syncPanelRoleFromChurch(_lastGoodTenantDoc?.data());
    }
    if (oldWidget.tenantId != widget.tenantId) {
      final canonical = ChurchPanelTenant.resolve(widget.tenantId);
      _operationalTenantId = canonical.isNotEmpty ? canonical : null;
      _tenantResolveComplete = canonical.isNotEmpty;
      unawaited(() async {
        try {
          await _resolveOperationalTenant(forceRefresh: true);
          await _bootstrapShellTenantDoc(forceRefresh: true);
        } finally {
          if (mounted) setState(() => _tenantResolveComplete = true);
        }
      }());
      unawaited(_bootstrapChatPresenceHeartbeat());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      AppSessionStability.onGlobalResume();
      unawaited(ChatPresenceEngine.pingAppWideHeartbeatIfActive());
      unawaited(_resolveOperationalTenant(forceRefresh: false));
      ChurchTenantOfflineWarmupService.instance
          .scheduleLightRefreshOnResume(_moduleTenantId);
    }
  }

  void _onGlobalSessionResume() {
    ChurchTenantOfflineWarmupService.instance
        .scheduleLightRefreshOnResume(_moduleTenantId);
    unawaited(_resolveOperationalTenant(forceRefresh: false));
    unawaited(ChatPresenceEngine.pingAppWideHeartbeatIfActive());
  }

  Future<void> _bootstrapChatPresenceHeartbeat() async {
    final u = firebaseDefaultAuth.currentUser;
    if (u == null) return;
    final raw = _moduleTenantId.trim();
    if (raw.isEmpty) return;
    try {
      final tid = ChurchRepository.churchId(raw);
      if (!mounted) return;
      ChatPresenceEngine.startAppWideHeartbeat(
        tid.isNotEmpty ? tid : raw,
      );
    } catch (_) {
      if (!mounted) return;
      ChatPresenceEngine.startAppWideHeartbeat(raw);
    }
  }

  bool _focusInsideEditableText() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null) return false;
    return primary.context?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
  }

  bool _onShellHardwareKey(KeyEvent event) {
    if (!_globalSearchAllowed || _globalSearchDialogVisible) return false;
    if (event is! KeyDownEvent) return false;
    if (_focusInsideEditableText()) return false;

    // Tecla / â€” abre busca (comum na web e apps estilo "command palette").
    if (event.logicalKey == LogicalKeyboardKey.slash) {
      _openChurchGlobalSearch();
      return true;
    }

    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    if (!meta && !ctrl) return false;
    _openChurchGlobalSearch();
    return true;
  }

  void _openChurchGlobalSearch() {
    if (!_globalSearchAllowed || !mounted || _globalSearchDialogVisible) {
      return;
    }
    _globalSearchDialogVisible = true;
    showChurchGlobalSearchDialog(
      context: context,
      tenantId: _moduleTenantId,
      userRole: _panelRole,
      userCpfDigits: () {
        var d = widget.cpf.replaceAll(RegExp(r'\D'), '');
        if (d.length == 10) d = '0$d';
        return d.length == 11 ? d : null;
      }(),
      canAccessShellIndex: _canAccessItem,
      onSelect: _handleGlobalSearchSelection,
    ).whenComplete(() {
      if (mounted) setState(() => _globalSearchDialogVisible = false);
    });
  }

  void _handleGlobalSearchSelection(ChurchGlobalSearchSelection s) {
    if (s.avisoDocForDirectEdit != null) {
      unawaited(_openMuralAvisoEditorFromSearch(s.avisoDocForDirectEdit!));
      return;
    }
    _applyGlobalSearchNavigation(shellIndex: s.shellIndex, query: s.query);
  }

  Future<void> _openMuralAvisoEditorFromSearch(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty || !mounted) return;
    final op = ChurchPanelTenantGateway.churchId(tid.trim());
    final church = await ChurchUiCollections.churchDoc(op).get();
    if (!mounted) return;
    final d = church.data() ?? {};
    var slug = (d['slug'] ?? '').toString().trim();
    if (slug.isEmpty) slug = tid;
    final avisos =         ChurchUiCollections.avisos(op);
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MuralAvisoEditorPage(
          tenantId: tid,
          resolvedTenantId: op,
          postsCollection: avisos,
          doc: doc,
          type: 'aviso',
          churchSlug: slug,
        ),
      ),
    );
  }

  void _applyGlobalSearchNavigation({
    required int shellIndex,
    required String query,
  }) {
    if (!_canAccessItem(shellIndex)) {
      _showPanelSnack('Sem acesso a este mÃ³dulo.', isError: true);
      return;
    }
    setState(() {
      switch (shellIndex) {
        case kChurchShellIndexMembers:
          _shellBootstrapMemberSearch = query;
          _pageCache[kChurchShellIndexMembers] = null;
          break;
        case kChurchShellIndexMural:
          _pageCache[kChurchShellIndexMural] = null;
          break;
        case kChurchShellIndexEvents:
          _shellBootstrapEventSearch = query;
          _pageCache[kChurchShellIndexEvents] = null;
          break;
        case kChurchShellIndexPatrimonio:
          _shellBootstrapPatrimonioSearch = query;
          _pageCache[kChurchShellIndexPatrimonio] = null;
          break;
        default:
          break;
      }
      _selectedIndex = shellIndex;
    });
  }

  void _onPaymentConfirmedTick() {
    final current = PaymentUiFeedbackService.paymentConfirmedTick.value;
    if (!mounted || current == _lastPaymentTick) return;
    _lastPaymentTick = current;
    setState(() {
      _paymentBannerAnimSeed = _paymentBannerAnimSeed + 1;
      _showPaymentConfirmedBanner = true;
    });
  }

  /// Copia `members` â†’ `membros` no Firestore (Cloud Function com Admin SDK). Gestor/master.
  Future<void> _runMembersToMembrosMigration() async {
    final r = _panelRole.toUpperCase().trim();
    final canTrigger = r == 'GESTOR' ||
        r == 'ADMIN' ||
        r == 'ADM' ||
        r == 'MASTER' ||
        r == 'ADMINISTRADOR';
    if (!canTrigger || widget.tenantId.isEmpty) {
      await MigrateMembersToMembrosService.instance
          .runIfNeeded(widget.tenantId);
      return;
    }
    try {
      final fn = FirebaseFunctions.instance
          .httpsCallable('ensureMigrateMembersToMembros');
      final res = await fn.call({'tenantId': widget.tenantId});
      final data = Map<String, dynamic>.from(res.data as Map);
      final copied = (data['copied'] as num?)?.toInt() ?? 0;
      if (copied > 0 && mounted) {
        _showPanelSnack(
          data['message']?.toString() ??
              'MigraÃ§Ã£o: $copied registro(s) de members â†’ membros.',
        );
      }
    } catch (_) {
      await MigrateMembersToMembrosService.instance
          .runIfNeeded(widget.tenantId);
    }
  }

  void _loadUserPhotoFromFirestore() {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null || (user.photoURL ?? '').trim().isNotEmpty) return;
    firebaseDefaultFirestore
        .collection('users')
        .doc(user.uid)
        .get()
        .then((doc) {
      if (!mounted || !doc.exists) return;
      final url = imageUrlFromMap(doc.data());
      if (url.isNotEmpty && mounted)
        setState(() => _userPhotoUrlFromFirestore = url);
    }).catchError((_) {});
  }

  void _showPanelSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        backgroundColor:
            isError ? const Color(0xFF1E293B) : ThemeCleanPremium.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        ),
      ),
    );
  }

  bool _canAccessItem(int index) {
    return ChurchRolePermissions.shellAllowsNavIndex(
      _panelRole,
      index,
      memberCanViewFinance: widget.podeVerFinanceiro,
      memberCanViewPatrimonio: widget.podeVerPatrimonio,
      memberCanViewFornecedores: widget.podeVerFornecedores,
      permissions: widget.permissions,
    );
  }

  /// Lista sÃ³ mÃ³dulos que o utilizador pode abrir â€” membro bÃ¡sico nÃ£o vÃª entradas bloqueadas
  /// (evita cinza + â€œLiberado pelo gestorâ€; o que aparece Ã© utilizÃ¡vel).
  bool _shouldListNavIndex(int i) => _canAccessItem(i);

  void _navigateToShellModuleFromDashboard(int index) {
    if (!_canAccessItem(index)) {
      _showPanelSnack('Acesso negado para este mÃ³dulo.', isError: true);
      return;
    }
    setState(() => _selectedIndex = index);
    TenantIntelligentPreload.scheduleModuleForShellIndex(
      _moduleTenantId,
      index,
    );
    unawaited(
      AppResumeStateService.saveShellContext(
        tenantId: _moduleTenantId,
        shellIndex: index,
      ),
    );
  }

  void _prefetchShellModuleData(int index) {
    if (!_globalSearchAllowed) return;
    if (!_canAccessItem(index)) return;
    if (_shellPrefetchDone.contains(index)) return;
    _shellPrefetchDone.add(index);
    final tid = _moduleTenantId.trim();
    if (tid.isEmpty) {
      _shellPrefetchDone.remove(index);
      return;
    }
    try {
      switch (index) {
        case ChurchShellIndices.membros:
          unawaited(
            runFirebaseBackgroundTask<void>(
              () async {
                final op = ChurchPanelTenantGateway.churchId(tid.trim());
                final base =                     ChurchUiCollections.churchDoc(op);
                await base
                    .collection('membros')
                    .orderBy('updatedAt', descending: true)
                    .limit(24)
                    .get();
              },
              debugLabel: 'shell_prefetch_membros',
            ),
          );
          break;
        case ChurchShellIndices.muralAvisos:
          unawaited(
            runFirebaseBackgroundTask<void>(
              () async {
                final base =                     ChurchUiCollections.churchDoc(tid);
                await base
                    .collection('avisos')
                    .orderBy('createdAt', descending: true)
                    .limit(24)
                    .get();
              },
              debugLabel: 'shell_prefetch_avisos',
            ),
          );
          break;
        case ChurchShellIndices.muralEventos:
          unawaited(
            runFirebaseBackgroundTask<void>(
              () async {
                final base =                     ChurchUiCollections.churchDoc(tid);
                await base
                    .collection('eventos')
                    .orderBy('startAt', descending: true)
                    .limit(24)
                    .get();
              },
              debugLabel: 'shell_prefetch_eventos',
            ),
          );
          break;
        case 20:
          unawaited(
            runFirebaseBackgroundTask<void>(
              () async {
                await                     ChurchUiCollections.financeiro(tid)
                    .limit(24)
                    .get();
              },
              debugLabel: 'shell_prefetch_finance',
            ),
          );
          break;
        case 21:
          unawaited(
            runFirebaseBackgroundTask<void>(
              () async {
                await                     ChurchUiCollections.patrimonio(tid)
                    .limit(24)
                    .get();
              },
              debugLabel: 'shell_prefetch_patrimonio',
            ),
          );
          break;
        case 22:
          unawaited(
            runFirebaseBackgroundTask<void>(
              () async {
                await                     ChurchUiCollections.fornecedores(tid)
                    .limit(24)
                    .get();
              },
              debugLabel: 'shell_prefetch_fornecedores',
            ),
          );
          break;
        case ChurchShellIndices.chatIgreja:
          unawaited(
            runFirebaseBackgroundTask<void>(
              () async {
                await                     ChurchUiCollections.chats(tid)
                    .orderBy('lastMessageAt', descending: true)
                    .limit(16)
                    .get();
              },
              debugLabel: 'shell_prefetch_chat',
            ),
          );
          break;
        default:
          _shellPrefetchDone.remove(index);
      }
    } catch (_) {
      _shellPrefetchDone.remove(index);
    }
  }

  /// Ãcone 3D colorido (desktop + drawer).
  Widget _navMenuIconChip(int i, bool selected, {bool compact = false}) {
    final box = compact ? 38.0 : 42.0;
    return ChurchShellNavIcon3D(
      icon: _items[i].icon,
      accent: _items[i].accent,
      selected: selected,
      size: box,
      iconSize: compact ? 20 : 22,
    );
  }

  Widget _sidebarSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 22, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color:
                      ThemeCleanPremium.navSidebarAccent.withValues(alpha: 0.35),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(int i, {required bool compact}) {
    final item = _items[i];
    final selected = _selectedIndex == i;
    final tile = MouseRegion(
      onEnter: (_) => _prefetchShellModuleData(i),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            if (!_canAccessItem(i)) {
              _showPanelSnack('Acesso negado para este mÃ³dulo.', isError: true);
              return;
            }
            setState(() => _selectedIndex = i);
          },
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        item.accent.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0.08),
                      ],
                    )
                  : null,
              border: Border.all(
                color: selected
                    ? item.accent.withValues(alpha: 0.45)
                    : Colors.transparent,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: item.accent.withValues(alpha: 0.35),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ThemeCleanPremium.minTouchTarget,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 2 : 8,
                  vertical: 5,
                ),
                child: compact
                    ? Center(child: _navMenuIconChip(i, selected, compact: true))
                    : Row(
                        children: [
                          _navMenuIconChip(i, selected),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item.label,
                              style: GoogleFonts.inter(
                                color: Colors.white
                                    .withValues(alpha: selected ? 1.0 : 0.82),
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 13.5,
                                letterSpacing: -0.25,
                                height: 1.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    if (compact) {
      return Tooltip(
        message: item.label,
        waitDuration: const Duration(milliseconds: 400),
        child: tile,
      );
    }
    return tile;
  }

  static const List<({String title, List<int> indices})> _menuSections = [
    (title: 'Geral', indices: [0, 1, 2, 22]),
    (title: 'Pessoas', indices: [3, 4, 5, 6]),
    (title: 'ComunicaÃ§Ã£o', indices: [7, 8, 9, 10, 18, 23]),
    (title: 'Agenda', indices: [11, 12]),
    (title: 'Documentos', indices: [13, 14, 15]),
    (title: 'Sistema', indices: [16, 17]),
    (title: 'Financeiro e patrimÃ´nio', indices: [19, 20, 21]),
  ];

  List<({String title, List<int> indices})> _menuSectionsForRole(String role) {
    if (!AppPermissions.isRestrictedMember(role)) return _menuSections;
    return [
      (
        title: 'Minha conta',
        indices: [ChurchShellIndices.configuracoes],
      ),
      (title: 'Geral', indices: [0, 22]),
      (title: 'Pessoas', indices: [3]),
      (title: 'ComunicaÃ§Ã£o', indices: [7, 8, 9, 10, 23]),
      (title: 'Agenda', indices: [11, 12]),
      (title: 'Documentos', indices: [13]),
    ];
  }

  /// Entrada visÃ­vel para a busca global (Ctrl/Cmd+K, tecla /).
  ///
  /// Larguras lÃ³gicas tÃ­picas: ~320 legado; 360â€“430 celulares; â‰¥600 tablet.
  /// Abaixo de [_kSearchIconOnlyMaxWidth] sÃ³ Ã­cone â€” libera espaÃ§o para saudaÃ§Ã£o e aÃ§Ãµes.
  static const double _kSearchIconOnlyMaxWidth = 352;
  static const double _kSearchCompactLabelMaxWidth = 400;

  /// Nome para saudaÃ§Ã£o no cabeÃ§alho azul e, no telemÃ³vel, subtÃ­tulo no cartÃ£o do mÃ³dulo.
  String _shellUserGreetingName() {
    final user = firebaseDefaultAuth.currentUser;
    final fallback = user?.email ?? 'UsuÃ¡rio';
    final dn = (user?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    return fallback;
  }

  Widget _buildHeaderSearchChip() {
    if (!_globalSearchAllowed) return const SizedBox.shrink();
    final w = MediaQuery.sizeOf(context).width;
    final iconOnly = w < _kSearchIconOnlyMaxWidth;
    final compactLabel =
        !iconOnly && w < _kSearchCompactLabelMaxWidth;
    final showHints = _isDesktop;
    final showBuscarLabel = !iconOnly;
    final buscarFontSize = compactLabel ? 12.5 : 14.0;

    const tooltipMessage =
        'Busca global: membros, eventos, mural e patrimÃ´nio.\n'
        'Atalhos de teclado: / (barra) Â· Ctrl+K Â· Cmd+K no Mac.';

    Widget chip = Padding(
      padding: EdgeInsets.only(
        right: iconOnly ? 2 : (compactLabel ? 6 : 10),
      ),
      child: Material(
        color: Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: _openChurchGlobalSearch,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: iconOnly ? 8 : (compactLabel ? 10 : 14),
              vertical: iconOnly ? 6 : 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_rounded,
                  color: Colors.white.withOpacity(0.95),
                  size: iconOnly ? 20 : (compactLabel ? 21 : 22),
                ),
                if (showBuscarLabel) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Buscarâ€¦',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.92),
                      fontSize: buscarFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (showHints) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '/',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ctrl+K',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    chip = Semantics(
      button: true,
      label: 'Buscar no painel da igreja',
      hint:
          'Abre a busca. No teclado fÃ­sico: tecla barra, Ctrl+K ou Cmd+K.',
      child: chip,
    );

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );
  }

  Widget _buildHeader({required bool licenseBlocked}) {
    final user = firebaseDefaultAuth.currentUser;
    final greetingName = _shellUserGreetingName();
    final photoUrl = (user?.photoURL ?? '').trim().isNotEmpty
        ? user!.photoURL
        : _userPhotoUrlFromFirestore;
    final hora = DateTime.now().hour;
    final periodo = hora < 12
        ? 'Bom dia'
        : hora < 18
            ? 'Boa tarde'
            : 'Boa noite';
    final avatarSize = _isDesktop ? 32.0 : 40.0;
    final sidePad = _isDesktop
        ? ThemeCleanPremium.spaceMd
        : (_isPhone ? ThemeCleanPremium.spaceSm : ThemeCleanPremium.spaceMd);
    final verticalPad = _isDesktop ? 4.0 : 8.0;
    return Material(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.18),
      color: ThemeCleanPremium.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            sidePad,
            verticalPad,
            sidePad,
            verticalPad,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_isDesktop)
                IconButton(
                  icon: Icon(
                    _sidebarCollapsed
                        ? Icons.keyboard_double_arrow_right_rounded
                        : Icons.keyboard_double_arrow_left_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  tooltip: _sidebarCollapsed
                      ? 'Expandir menu lateral'
                      : 'Recolher menu lateral',
                  onPressed: () =>
                      setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              if (_isMobile)
                IconButton(
                  icon: Icon(
                    _selectedIndex != 0
                        ? Icons.arrow_back_rounded
                        : Icons.menu_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: () {
                    if (_selectedIndex != 0) {
                      setState(() => _selectedIndex = 0);
                    } else {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scaffoldKey.currentState?.openDrawer();
                      });
                    }
                  },
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  tooltip:
                      _selectedIndex != 0 ? 'Voltar ao Painel' : 'Abrir menu',
                ),
              AvatarGestorWidget(
                imageUrl: (photoUrl ?? '').trim().isEmpty ? null : photoUrl,
                tenantId: _moduleTenantId,
                memberDocIdOrCpf:
                    widget.cpf.replaceAll(RegExp(r'\D'), '').isNotEmpty
                        ? widget.cpf.replaceAll(RegExp(r'\D'), '')
                        : widget.cpf.trim(),
                size: avatarSize,
              ),
              SizedBox(width: _isDesktop ? 10 : ThemeCleanPremium.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$periodo, $greetingName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _isDesktop ? 14 : 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.12,
                      ),
                    ),
                    if (widget.tenantId.trim().isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: widget.tenantId.trim()));
                            ScaffoldMessenger.of(context).showSnackBar(
                              ThemeCleanPremium.successSnackBar(
                                  'ID da igreja copiado.'),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    'ID: ${widget.tenantId.trim()}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withOpacity(0.85),
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.copy_rounded,
                                  size: 12,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    _HeaderLocalizacao(tenantId: widget.tenantId.trim()),
                    if (licenseBlocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Teste expirado. Ative um plano.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade200,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (_isDesktop)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _HeaderVencimento(
                            tenantId: _moduleTenantId, light: true),
                      ),
                  ],
                ),
              ),
              ChurchNotificationBell(
                tenantId: _moduleTenantId,
                cpf: widget.cpf,
                role: _panelRole,
                onNavigateToShellModule: _navigateToShellModuleFromDashboard,
              ),
              Flexible(
                fit: FlexFit.loose,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72, maxWidth: 420),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _buildHeaderSearchChip(),
                    ),
                  ),
                ),
              ),
              if (_isDesktop) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 2),
                  child: SizedBox(
                    height: 26,
                    width: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
                if (_showUpgradePlanUi)
                  IconButton(
                    tooltip: IosPaymentsGate.shouldHidePayments
                        ? 'Atualizar plano'
                        : 'Planos e assinatura',
                    onPressed: () => unawaited(_openUpgradePlans()),
                    // Material estÃ¡vel na web (subset de Ã­cones arredondados pode falhar).
                    icon: const Icon(Icons.emoji_events_rounded,
                        color: Colors.white, size: 22),
                    style:
                        IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  ),
              ],
              if (_isMobile && _showUpgradePlanUi)
                IconButton(
                  icon: const Icon(Icons.emoji_events_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => unawaited(_openUpgradePlans()),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  tooltip: IosPaymentsGate.shouldHidePayments
                      ? 'Atualizar plano'
                      : 'Planos',
                ),
              IconButton(
                tooltip: 'Sair',
                icon: const Icon(Icons.logout_rounded,
                    color: Colors.white, size: 22),
                onPressed: () =>
                    unawaited(ChurchSignOutNavigation.signOutForAccountSwitch()),
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
              IconButton(
                icon: const Icon(Icons.settings_rounded,
                    color: Colors.white, size: 22),
                onPressed: () {
                  setState(() => _selectedIndex = ChurchShellIndices.configuracoes);
                },
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                tooltip: 'ConfiguraÃ§Ãµes',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentConfirmedBanner() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: !_showPaymentConfirmedBanner
          ? const SizedBox.shrink()
          : Container(
              key: ValueKey('payment_confirmed_banner_$_paymentBannerAnimSeed'),
              margin: const EdgeInsets.fromLTRB(
                ThemeCleanPremium.spaceMd,
                ThemeCleanPremium.spaceSm,
                ThemeCleanPremium.spaceMd,
                0,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeCleanPremium.spaceMd,
                vertical: ThemeCleanPremium.spaceSm,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                border: Border.all(color: const Color(0xFFA7F3D0)),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      color: Color(0xFF047857), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pagamento confirmado. LicenÃ§a ativa e sistema liberado.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: TweenAnimationBuilder<double>(
                            key: ValueKey(
                                'payment_banner_progress_$_paymentBannerAnimSeed'),
                            tween: Tween<double>(begin: 1, end: 0),
                            duration: const Duration(seconds: 4),
                            curve: Curves.linear,
                            onEnd: () {
                              if (!mounted) return;
                              if (_showPaymentConfirmedBanner) {
                                setState(
                                    () => _showPaymentConfirmedBanner = false);
                              }
                            },
                            builder: (context, value, _) {
                              return LinearProgressIndicator(
                                value: value,
                                minHeight: 4,
                                backgroundColor: const Color(0xFFA7F3D0),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF047857)),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '4s',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      if (!mounted) return;
                      setState(() => _showPaymentConfirmedBanner = false);
                    },
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      foregroundColor: const Color(0xFF065F46),
                    ),
                    child: const Text(
                      'Fechar agora',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () {
                      if (!mounted) return;
                      setState(() => _showPaymentConfirmedBanner = false);
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: const Color(0xFF065F46),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(
                        ThemeCleanPremium.minTouchTarget,
                        ThemeCleanPremium.minTouchTarget,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _syncSubscriptionSnapshot(SubscriptionGuardState guard) async {
    if (guard.isFree) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSubscriptionSyncMs < 5 * 60 * 1000) return;
    _lastSubscriptionSyncMs = nowMs;
    try {
      final op = ChurchPanelTenantGateway.churchId(widget.tenantId.trim());
      await           ChurchUiCollections.churchDoc(op)
          .set(SubscriptionGuard.normalizedChurchFields(guard),
              SetOptions(merge: true));
    } catch (_) {
      // Sem falha visÃ­vel no cliente: a proteÃ§Ã£o continua local.
    }
  }

  Widget _buildGracePeriodBanner(SubscriptionGuardState guard) {
    if (guard.isFree || !guard.inGrace || guard.blocked) {
      return const SizedBox.shrink();
    }
    final days = guard.graceDaysLeft;
    final txt = days <= 0
        ? 'AtenÃ§Ã£o: sua assinatura venceu. O sistema serÃ¡ bloqueado hoje.'
        : 'AtenÃ§Ã£o: sua assinatura venceu. O sistema serÃ¡ bloqueado em $days dia(s).';
    return Container(
      margin: const EdgeInsets.fromLTRB(
        ThemeCleanPremium.spaceMd,
        ThemeCleanPremium.spaceSm,
        ThemeCleanPremium.spaceMd,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeCleanPremium.spaceMd,
        vertical: ThemeCleanPremium.spaceSm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              txt,
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Menu lateral esquerdo vertical azul escuro (desktop) â€” expansÃ­vel / colapsÃ¡vel.
  Widget _buildSidebar() {
    final compact = _sidebarCollapsed;
    final sidebarW = compact ? 76.0 : 224.0;
    final navBase = ThemeCleanPremium.navSidebar;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: sidebarW,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(navBase, Colors.white, 0.07)!,
            navBase,
            Color.lerp(navBase, const Color(0xFF020617), 0.18)!,
          ],
          stops: const [0.0, 0.42, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(height: compact ? 10 : ThemeCleanPremium.spaceMd),
          if (compact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 30,
                child: Image.asset(
                  'assets/LOGO_GESTAO_YAHWEH.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.church_rounded,
                      color: Colors.white, size: 26),
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 28,
                  child: Image.asset(
                    'assets/LOGO_GESTAO_YAHWEH.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.church_rounded,
                        color: Colors.white,
                        size: 28),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'GestÃ£o YAHWEH',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          SizedBox(height: compact ? 8 : ThemeCleanPremium.spaceMd),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 6 : ThemeCleanPremium.spaceMd,
                  vertical: 10),
              children: [
                for (final section in _menuSectionsForRole(_panelRole)) ...[
                  if (section.indices.any(_shouldListNavIndex)) ...[
                    if (!compact) _sidebarSectionLabel(section.title),
                    for (final i in section.indices)
                      if (_shouldListNavIndex(i))
                        Padding(
                          key: ValueKey('nav_$i'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildNavTile(
                            i,
                            compact: compact,
                          ),
                        ),
                  ],
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                compact ? 6 : ThemeCleanPremium.spaceSm,
                ThemeCleanPremium.spaceSm,
                compact ? 6 : ThemeCleanPremium.spaceSm,
                ThemeCleanPremium.spaceMd),
            child: _showUpgradePlanUi
                ? (compact
                    ? Tooltip(
                        message: IosPaymentsGate.shouldHidePayments
                            ? 'Atualizar plano'
                            : 'Adquirir plano',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => unawaited(_openUpgradePlans()),
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusMd),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF0A3D91),
                                    Color(0xFF1565C0)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(Icons.add_card_rounded,
                                  size: 22,
                                  color: ThemeCleanPremium.navSidebarAccent),
                            ),
                          ),
                        ),
                      )
                    : Material(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusMd),
                        child: InkWell(
                          onTap: () => unawaited(_openUpgradePlans()),
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd),
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0A3D91),
                                  Color(0xFF1565C0)
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: ThemeCleanPremium.navSidebar
                                      .withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_card_rounded,
                                    size: 20,
                                    color: ThemeCleanPremium.navSidebarAccent),
                                const SizedBox(width: 10),
                                Text(
                                  IosPaymentsGate.shouldHidePayments
                                      ? 'Atualizar plano'
                                      : 'Adquirir Plano',
                                  style: const TextStyle(
                                      color:
                                          ThemeCleanPremium.navSidebarAccent,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ))
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
        ],
      ),
    );
  }

  /// Drawer mobile â€” mesmo menu lateral azul escuro (Android/iOS, todas as versÃµes)
  Widget _buildDrawer() {
    return Drawer(
      width: _isMobile
          ? (MediaQuery.sizeOf(context).width * 0.88)
              .clamp(280.0, 360.0)
              .toDouble()
          : null,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(ThemeCleanPremium.navSidebar, Colors.white, 0.07)!,
              ThemeCleanPremium.navSidebar,
              Color.lerp(ThemeCleanPremium.navSidebar, const Color(0xFF020617),
                  0.18)!,
            ],
            stops: const [0.0, 0.42, 1.0],
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: true,
          left: true,
          right: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    SizedBox(
                      height: 32,
                      child: Image.asset(
                        'assets/LOGO_GESTAO_YAHWEH.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.church_rounded,
                            color: Colors.white,
                            size: 32),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'GestÃ£o YAHWEH',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        letterSpacing: -0.35,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: ThemeCleanPremium.spaceSm, vertical: 10),
                  children: [
                    for (final section in _menuSectionsForRole(_panelRole)) ...[
                      if (section.indices.any(_shouldListNavIndex))
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _sidebarSectionLabel(section.title),
                        ),
                      for (final i in section.indices)
                        if (_shouldListNavIndex(i))
                          Builder(
                            builder: (context) {
                              return MouseRegion(
                                onEnter: (_) => _prefetchShellModuleData(i),
                                child: ListTile(
                                  key: ValueKey('drawer_$i'),
                                  leading: _navMenuIconChip(
                                    i,
                                    _selectedIndex == i,
                                  ),
                                  title: Text(
                                    _items[i].label,
                                    style: GoogleFonts.inter(
                                      color: Colors.white.withValues(
                                        alpha: _selectedIndex == i ? 1.0 : 0.85,
                                      ),
                                      fontWeight: _selectedIndex == i
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      fontSize: _isPhone ? 15 : 13.5,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  selected: _selectedIndex == i,
                                  selectedTileColor:
                                      Colors.white.withValues(alpha: 0.08),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  minVerticalPadding: _isPhone ? 14 : 12,
                                  onTap: () {
                                    if (!_canAccessItem(i)) {
                                      _showPanelSnack(
                                        'Acesso negado para este mÃ³dulo.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                    setState(() => _selectedIndex = i);
                                    Navigator.of(context).pop();
                                  },
                                ),
                              );
                            },
                          ),
                    ],
                  ],
                ),
              ),
              if (ThemeModeScope.of(context) != null)
                ListTile(
                  leading: Icon(Icons.dark_mode_rounded,
                      color: Colors.white70, size: 22),
                  title: const Text('Modo escuro',
                      style: TextStyle(color: Colors.white, fontSize: 14)),
                  trailing: Switch(
                    value: ThemeModeScope.of(context)!.mode == ThemeMode.dark,
                    onChanged: (v) => ThemeModeScope.of(context)!
                        .setMode(v ? ThemeMode.dark : ThemeMode.light),
                    activeColor: ThemeCleanPremium.navSidebarAccent,
                  ),
                ),
              if (_showUpgradePlanUi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                  child: Material(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(_openUpgradePlans());
                      },
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusSm),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0A3D91), Color(0xFF1565C0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: ThemeCleanPremium.navSidebar
                                  .withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_card_rounded,
                                size: 20,
                                color: ThemeCleanPremium.navSidebarAccent),
                            const SizedBox(width: 10),
                            Text(
                              IosPaymentsGate.shouldHidePayments
                                  ? 'Atualizar plano'
                                  : 'Adquirir Plano',
                              style: const TextStyle(
                                  color: ThemeCleanPremium.navSidebarAccent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// ConstrÃ³i a pÃ¡gina do menu por Ã­ndice (uma vez; depois reutilizada pelo cache).
  Widget _buildPageForIndex(int index) {
    switch (index) {
      case 0:
        return IgrejaDashboardModerno(
          key: _shellPageKey(0),
          tenantId: _moduleTenantId,
          role: _panelRole,
          cpf: widget.cpf,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          podeVerFornecedores: widget.podeVerFornecedores,
          permissions: widget.permissions,
          onNavigateToMembers: () =>
              setState(() => _selectedIndex = ChurchShellIndices.membros),
          onNavigateToShellModule: _navigateToShellModuleFromDashboard,
        );
      case 1:
        return IgrejaCadastroPage(
            key: _shellPageKey(1),
            tenantId: _moduleTenantId,
            role: _panelRole,
            embeddedInShell: true);
      case 2:
        return ConfiguracoesPage(
          key: _shellPageKey(2),
          tenantId: _moduleTenantId,
          role: _panelRole,
          permissions: widget.permissions,
          subscription: widget.subscription,
        );
      case 3:
        final bootMember = _shellBootstrapMemberSearch;
        if (bootMember != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _shellBootstrapMemberSearch = null);
            }
          });
        }
        final bootOpenId = _shellBootstrapOpenMemberId;
        if (bootOpenId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _shellBootstrapOpenMemberId = null);
            }
          });
        }
        return MembersPage(
          key: _shellPageKey(3),
          tenantId: _moduleTenantId,
          role: _panelRole,
          subscription: widget.subscription,
          linkedCpf: widget.cpf.trim().isEmpty ? null : widget.cpf,
          permissions: widget.permissions,
          embeddedInShell: true,
          initialSearchQuery: bootMember,
          initialOpenMemberDocId: bootOpenId,
        );
      case 4:
        return DepartmentsPage(
            key: _shellPageKey(4),
            tenantId: _moduleTenantId,
            role: _panelRole,
            permissions: widget.permissions,
            embeddedInShell: true);
      case 5:
        return VisitorsPage(
            key: _shellPageKey(5),
            tenantId: _moduleTenantId,
            role: _panelRole,
            embeddedInShell: true);
      case 6:
        return CargosPage(
            key: _shellPageKey(6),
            tenantId: _moduleTenantId,
            role: _panelRole,
            embeddedInShell: true,
            onOpenPanelCorpoAdministrativo: () {
              setState(() => _selectedIndex = 0);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                PanelScrollBridge.scrollToCorpoAdministrativo?.call();
              });
            });
      case 7:
        final bootAviso = _shellBootstrapOpenAvisoDocId;
        if (bootAviso != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _shellBootstrapOpenAvisoDocId = null);
            }
          });
        }
        return MuralPage(
            key: _shellPageKey(7),
            tenantId: _moduleTenantId,
            role: _panelRole,
            permissions: widget.permissions,
            embeddedInShell: true,
            initialOpenAvisoDocId: bootAviso);
      case 8:
        final bootEvent = _shellBootstrapEventSearch;
        final bootEventDoc = _shellBootstrapOpenEventDocId;
        if (bootEvent != null || bootEventDoc != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _shellBootstrapEventSearch = null;
                _shellBootstrapOpenEventDocId = null;
              });
            }
          });
        }
        return EventsManagerPage(
            key: _shellPageKey(8),
            tenantId: _moduleTenantId,
            role: _panelRole,
            permissions: widget.permissions,
            embeddedInShell: true,
            initialFeedSearchQuery: bootEvent,
            initialOpenEventDocId: bootEventDoc);
      case 9:
        return PrayerRequestsPage(
            key: _shellPageKey(9),
            tenantId: _moduleTenantId,
            role: _panelRole,
            embeddedInShell: true);
      case 10:
        return CalendarPage(
            key: _shellPageKey(10),
            tenantId: _moduleTenantId,
            role: _panelRole,
            permissions: widget.permissions,
            embeddedInShell: true);
      case 11:
        return MySchedulesPage(
            key: _shellPageKey(11),
            tenantId: _moduleTenantId,
            cpf: widget.cpf,
            role: _panelRole,
            embeddedInShell: true);
      case 12:
        return SchedulesPage(
            key: _shellPageKey(12),
            tenantId: _moduleTenantId,
            role: _panelRole,
            cpf: widget.cpf,
            embeddedInShell: true);
      case 13:
        return MemberCardPage(
          key: _shellPageKey(13),
          tenantId: _moduleTenantId,
          role: _panelRole,
          cpf: widget.cpf,
          embeddedInShell: true,
          cnhFullscreenOnly:
              AppPermissions.isRestrictedMember(_panelRole),
          onNavigateToMembers: AppPermissions.isRestrictedMember(_panelRole)
              ? null
              : () => setState(
                    () => _selectedIndex = ChurchShellIndices.membros,
                  ),
        );
      case 14:
        return CertificadosPage(
            key: _shellPageKey(14),
            tenantId: _moduleTenantId,
            role: _panelRole);
      case 15:
        return ChurchLettersPage(
          key: _shellPageKey(15),
          tenantId: _moduleTenantId,
          role: _panelRole,
          cpf: widget.cpf,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 16:
        return RelatoriosPage(
          key: _shellPageKey(16),
          tenantId: _moduleTenantId,
          role: _panelRole,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          podeEmitirRelatoriosCompletos: widget.podeEmitirRelatoriosCompletos,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 17:
        return SistemaInformacoesPage(
            key: _shellPageKey(17), tenantId: _moduleTenantId);
      case 18:
        return AprovarMembrosPendentesPage(
          key: _shellPageKey(18),
          tenantId: _moduleTenantId,
          gestorRole: _panelRole,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 19:
        return FinancePage(
          key: _shellPageKey(19),
          tenantId: _moduleTenantId,
          role: _panelRole,
          cpf: widget.cpf,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 20:
        final bootPat = _shellBootstrapPatrimonioSearch;
        final bootPatDoc = _shellBootstrapOpenPatrimonioDocId;
        if (bootPat != null || bootPatDoc != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _shellBootstrapPatrimonioSearch = null;
                _shellBootstrapOpenPatrimonioDocId = null;
              });
            }
          });
        }
        return PatrimonioPage(
          key: _shellPageKey(20),
          tenantId: _moduleTenantId,
          role: _panelRole,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          permissions: widget.permissions,
          initialSearchQuery: bootPat,
          initialOpenPatrimonioDocId: bootPatDoc,
          embeddedInShell: true,
        );
      case 21:
        return FornecedoresPage(
          key: _shellPageKey(21),
          tenantId: _moduleTenantId,
          role: _panelRole,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerFornecedores: widget.podeVerFornecedores,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 22:
        if (IosPaymentsGate.isIosNative) {
          return IosDonationReaderView(
            key: ValueKey('page_22_ios_donation_$_moduleTenantId'),
            tenantId: _moduleTenantId,
            embeddedInShell: true,
          );
        }
        return ChurchDonationsPage(
          key: _shellPageKey(22),
          tenantId: _moduleTenantId,
          role: _panelRole,
          cpf: widget.cpf,
          embeddedInShell: true,
        );
      case 23:
        return ChurchChatHubPage(
          key: _shellPageKey(23),
          tenantId: _moduleTenantId,
          cpf: widget.cpf,
          role: _panelRole,
          embeddedInShell: true,
          permissions: widget.permissions,
        );
      default:
        return IgrejaDashboardModerno(
            key: ValueKey('page_$index'),
            tenantId: _moduleTenantId,
            role: _panelRole,
            cpf: widget.cpf,
            podeVerFinanceiro: widget.podeVerFinanceiro,
            podeVerPatrimonio: widget.podeVerPatrimonio,
            podeVerFornecedores: widget.podeVerFornecedores,
            permissions: widget.permissions,
            onNavigateToMembers: () =>
              setState(() => _selectedIndex = ChurchShellIndices.membros),
            onNavigateToShellModule: _navigateToShellModuleFromDashboard);
    }
  }

  Widget _buildContent() {
    if (!_tenantResolveComplete) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_selectedIndex < 0 || _selectedIndex >= _pageCache.length) {
      return RepaintBoundary(child: _buildPageForIndex(0));
    }
    if (!_canAccessItem(_selectedIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
        _showPanelSnack('Acesso negado para este mÃ³dulo.', isError: true);
      });
      return RepaintBoundary(child: _buildPageForIndex(0));
    }

    /// Desktop nativo: mantÃ©m pÃ¡ginas visitadas no [IndexedStack].
    /// Web: sÃ³ a aba activa â€” evita dezenas de listeners Firestore (INTERNAL ASSERTION).
    if (_isDesktop && !kIsWeb) {
      if (_pageCache[_selectedIndex] == null) {
        _pageCache[_selectedIndex] = _buildPageForIndex(_selectedIndex);
      }
      return RepaintBoundary(
        child: IndexedStack(
          index: _selectedIndex,
          sizing: StackFit.expand,
          children: List.generate(_pageCache.length, (i) {
            if (_pageCache[i] == null && i != _selectedIndex) {
              return const SizedBox.shrink();
            }
            if (_pageCache[i] == null) {
              _pageCache[i] = _buildPageForIndex(i);
            }
            return _pageCache[i]!;
          }),
        ),
      );
    }

    /// Mobile: sÃ³ a aba ativa do rodapÃ© â€” evita 6 mÃ³dulos pesados em paralelo.
    final footerTab =
        ChurchShellLazyModulePolicy.isMobileFooterTab(_selectedIndex);
    if (footerTab) {
      _pageCache[_selectedIndex] ??= _buildPageForIndex(_selectedIndex);
      for (var i = 0; i < _pageCache.length; i++) {
        if (i != _selectedIndex) {
          _pageCache[i] = null;
        }
      }
      return RepaintBoundary(child: _pageCache[_selectedIndex]!);
    }
    _pageCache[_selectedIndex] ??= _buildPageForIndex(_selectedIndex);
    return RepaintBoundary(
      child: _wrapShellMobileModule(
        _selectedIndex,
        _pageCache[_selectedIndex]!,
      ),
    );
  }

  /// LicenÃ§a vencida (trial + carÃªncia ou assinatura): sÃ³ renovaÃ§Ã£o / pagamento, conforme regra do master.
  Widget _buildLicenseRenewalOnly(
    BuildContext context, {
    required String churchName,
    String? logoUrl,
  }) {
    return PopScope(
      canPop: false,
      child: SubscriptionExpiredPage(
        churchName: churchName,
        logoUrl: logoUrl,
        canPurchaseLicense: _canPurchaseLicense,
        onRenew: _canPurchaseLicense
            ? () => unawaited(_openUpgradePlans())
            : () {},
        onLogout: ChurchSignOutNavigation.signOutForAccountSwitch,
      ),
    );
  }

  /// Tela que exige completar o cadastro da igreja antes de qualquer lanÃ§amento.
  Widget _buildCompleteCadastroObrigatorio() {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: ThemeCleanPremium.churchPanelBodyGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg)),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(Icons.business_rounded,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 20),
                        Text(
                          'Cadastre sua igreja',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Para usar o painel e fazer lanÃ§amentos, complete o cadastro da igreja: nome, CPF/CNPJ (se tiver), logo, endereÃ§o e link do site. Sua ficha pessoal (foto, CPF, etc.) fica em Membros.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                              height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              ThemeCleanPremium.fadeSlideRoute(IgrejaCadastroPage(
                                  tenantId: _moduleTenantId,
                                  role: _panelRole,
                                  embeddedInShell: false)),
                            );
                          },
                          icon: const Icon(Icons.store_rounded),
                          label: const Text('Ir para Cadastro da Igreja'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Blindagem: Voltar / tecla Android sempre para na tela inicial; sÃ³ sai pelo Logout.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!mounted) return;
        final scaffold = _scaffoldKey.currentState;
        if (scaffold?.isDrawerOpen ?? false) {
          scaffold!.closeDrawer();
          return;
        }
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        } else {
          _showPanelSnack(
            'Use o botÃ£o "Sair" no menu para encerrar a sessÃ£o.',
            isError: true,
          );
        }
      },
      child: !_tenantResolveComplete
          ? _buildTenantBootstrapScaffold(
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _buildShellGateBody(),
    );
  }
}

/// MantÃ©m glifos do menu no subset da fonte Material na **web** (build release).
/// Lista gerada a partir de [kChurchShellNavEntries] â€” impossÃ­vel esquecer um item (ex.: mail/mic).
class _ChurchShellNavMaterialIconsKeepalive extends StatelessWidget {
  const _ChurchShellNavMaterialIconsKeepalive();

  @override
  Widget build(BuildContext context) {
    final icons = <IconData>[
      for (final e in kChurchShellNavEntries) e.icon,
      ...kChurchShellNavMaterialIconExtras,
    ];
    return Offstage(
      child: Wrap(
        children: [for (final id in icons) Icon(id, size: 1)],
      ),
    );
  }
}

/// Linha â€œLocal: â€¦â€ no topo (dados do cadastro da igreja em Firestore).
class _HeaderLocalizacao extends StatelessWidget {
  final String tenantId;

  const _HeaderLocalizacao({required this.tenantId});

  static String? _lineFromChurch(Map<String, dynamic>? m) {
    if (m == null) return null;
    final loc = (m['localizacao'] ?? '').toString().trim();
    if (loc.isNotEmpty) return loc;
    final cidade =
        (m['cidade'] ?? m['localidade'] ?? '').toString().trim();
    final uf = (m['estado'] ?? m['uf'] ?? '').toString().trim();
    final bairro = (m['bairro'] ?? '').toString().trim();
    final rua =
        (m['rua'] ?? m['endereco'] ?? m['address'] ?? '').toString().trim();
    final parts = <String>[];
    if (rua.isNotEmpty) parts.add(rua);
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty && uf.isNotEmpty) {
      parts.add('$cidade - $uf');
    } else if (cidade.isNotEmpty) {
      parts.add(cidade);
    }
    if (parts.isEmpty) return null;
    return parts.join(' Â· ');
  }

  @override
  Widget build(BuildContext context) {
    if (tenantId.isEmpty) return const SizedBox.shrink();
    final ctxId = ChurchContextService.currentChurchId?.trim() ?? '';
    final ctxData = ChurchContextService.currentChurchData;
    final line = ctxId == tenantId.trim()
        ? _lineFromChurch(ctxData)
        : _lineFromChurch(null);
    if (line == null || line.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.location_on_outlined,
            size: 15,
            color: Colors.white.withValues(alpha: 0.92),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              'Local: $line',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.94),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderVencimento extends StatelessWidget {
  final String tenantId;
  final bool light;

  const _HeaderVencimento({required this.tenantId, this.light = false});

  @override
  Widget build(BuildContext context) {
    final textColor = light ? Colors.white70 : const Color(0xFF64748B);
    final ctxId = ChurchContextService.currentChurchId?.trim() ?? '';
    final data = ctxId == tenantId.trim()
        ? ChurchContextService.currentChurchData
        : null;
    if (data == null || data.isEmpty) {
      return Text('Vencimento: —',
          style: TextStyle(fontSize: 11, color: textColor));
    }
    if (LicenseAccessPolicy.churchIsFree(data)) {
      return Text(
        'Licença: FREE',
        style: TextStyle(
          fontSize: 11,
          color: light ? const Color(0xFF6EE7B7) : const Color(0xFF0D9488),
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final billing = data['billing'] as Map<String, dynamic>?;
    final next = billing?['nextChargeAt'];
    if (next == null) {
      return Text('Vencimento: —',
          style: TextStyle(fontSize: 11, color: textColor));
    }
    final dt = next is Timestamp ? next.toDate() : null;
    if (dt == null) {
      return Text('Vencimento: —',
          style: TextStyle(fontSize: 11, color: textColor));
    }
    final s =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    return Text('Vencimento: $s',
        style: TextStyle(
            fontSize: 11,
            color: light ? Colors.white : Colors.blue.shade800,
            fontWeight: FontWeight.w600));
  }
}

/// Atalho da barra inferior do painel da igreja (Ã­ndice no shell).
class _ChurchShellFooterShortcut {
  final int? shellIndex;
  final String shortLabel;
  final Color accent;
  final bool opensDrawer;

  const _ChurchShellFooterShortcut({
    required this.shellIndex,
    required this.shortLabel,
    required this.accent,
  }) : opensDrawer = false;
}

/// Chip colorido Super Premium â€” cÃ­rculo com gradiente ao selecionar.
class _PremiumShellFooterShortcut extends StatelessWidget {
  final int? shellIndex;
  final String shortLabel;
  final Color accent;
  final bool opensDrawer;
  final IconData icon;
  final String fullTooltip;
  final bool selected;
  final double circleSize;
  final double iconSize;
  final double labelFontSize;
  final VoidCallback onTap;

  const _PremiumShellFooterShortcut({
    required this.shellIndex,
    required this.shortLabel,
    required this.accent,
    required this.opensDrawer,
    required this.icon,
    required this.fullTooltip,
    required this.selected,
    required this.circleSize,
    required this.iconSize,
    required this.labelFontSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = accent;
    return Tooltip(
      message: fullTooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: c.withValues(alpha: 0.2),
          highlightColor: c.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 1),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ChurchShellNavIcon3D(
                  icon: icon,
                  accent: c,
                  selected: selected,
                  shape: ChurchShellIconShape.circle,
                  size: circleSize,
                  iconSize: iconSize,
                ),
                SizedBox(height: circleSize >= 48 ? 5 : 4),
                Text(
                  shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: labelFontSize,
                    height: 1.05,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    letterSpacing: -0.25,
                    color: selected
                        ? Color.lerp(c, const Color(0xFF0F172A), 0.25)!
                        : const Color(0xFF64748B),
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

// ignore: subtype_of_sealed_class â€” snapshot sintÃ©tico a partir do cache/sessÃ£o.
class _CachedChurchDocumentSnapshot
    implements DocumentSnapshot<Map<String, dynamic>> {
  _CachedChurchDocumentSnapshot({
    required this.id,
    required Map<String, dynamic> data,
  }) : _data = Map<String, dynamic>.from(data);

  @override
  final String id;

  final Map<String, dynamic> _data;

  @override
  bool get exists => _data.isNotEmpty;

  @override
  Map<String, dynamic>? data() => Map<String, dynamic>.from(_data);

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  SnapshotMetadata get metadata => const _CachedChurchSnapshotMetadata();

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('cached church snapshot has no reference');
}

class _CachedChurchSnapshotMetadata implements SnapshotMetadata {
  const _CachedChurchSnapshotMetadata();

  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}
