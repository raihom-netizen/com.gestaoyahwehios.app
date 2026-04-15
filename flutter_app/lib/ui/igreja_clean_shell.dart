import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/theme_mode_provider.dart';
import 'package:gestao_yahweh/services/payment_ui_feedback_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';
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
import 'pages/relatorios_page.dart';
import 'pages/aprovar_membros_pendentes_page.dart';
import 'pages/pastoral_comunicacao_page.dart';
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
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/core/license_access_policy.dart';
import 'package:gestao_yahweh/app_theme.dart';
import 'package:gestao_yahweh/ui/widgets/church_global_search_dialog.dart';
import 'package:gestao_yahweh/ui/widgets/instagram_mural.dart'
    show MuralAvisoEditorPage;
import 'package:google_fonts/google_fonts.dart';

/// Breakpoints: >= 900 desktop (sidebar fixa), < 900 mobile (drawer), < 600 phone (layout compacto)
const double _breakpointDesktop = 900;

/// Atalhos do [NavigationBar] mobile: Painel, Membros, Eventos, Mural; último abre o drawer.
const List<int> _kBottomNavShellIndices = [0, 2, 7, 6];
const double _breakpointPhone = 600;

/// Ícone e label para cada item do menu
class _NavItem {
  final IconData icon;
  final String label;
  final String? sublabel;

  const _NavItem(this.icon, this.label, [this.sublabel]);
}

/// Shell Clean Premium — Sidebar vertical azul escuro (Desktop) / Drawer (Mobile).
/// Header com saudação e card Plano/Vencimento.
class IgrejaCleanShell extends StatefulWidget {
  final String tenantId;
  final String cpf;
  final String role;
  final bool trialExpired;
  final Map<String, dynamic>? subscription;

  /// Gestor pode liberar financeiro para role "membro" via doc do membro (podeVerFinanceiro).
  final bool? podeVerFinanceiro;

  /// Gestor pode liberar patrimônio para role "membro" via doc do membro (podeVerPatrimonio).
  final bool? podeVerPatrimonio;

  /// Gestor pode liberar Fornecedores para role "membro" (podeVerFornecedores), além de permissão granular.
  final bool? podeVerFornecedores;

  /// Gestor libera PDFs de membros/aniversariantes etc. (senão só Relatório de Eventos).
  final bool? podeEmitirRelatoriosCompletos;

  /// Permissões específicas por módulo (RBAC granular), ex.: ['financeiro','membros'].
  final List<String>? permissions;

  /// Abre Membros com a ficha deste id (ex.: leitura do QR da carteirinha por gestor).
  final String? initialOpenMemberDocId;

  /// Abre direto um módulo do menu (ex.: [kChurchShellIndexMySchedules] após push de escala).
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

class _IgrejaCleanShellState extends State<IgrejaCleanShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  bool _adquirirPlanoExpanded = false;

  /// Desktop web: menu lateral estreito só com ícones (+ tooltip).
  bool _sidebarCollapsed = false;

  /// Foto do usuário vinda do Firestore (quando Auth photoURL está vazio).
  String? _userPhotoUrlFromFirestore;

  /// Cache das páginas do menu para manter estado ao trocar de aba ou ao voltar ao app (evita recarregar e tela preta).
  final List<Widget?> _pageCache = List.filled(24, null);
  bool _showPaymentConfirmedBanner = false;
  int _lastPaymentTick = 0;
  int _paymentBannerAnimSeed = 0;
  int _lastSubscriptionSyncMs = 0;

  /// Recria a subscrição ao doc da igreja após falha de rede.
  int _tenantStreamRetry = 0;

  /// Evita enfileirar [addPostFrameCallback] a cada frame do StreamBuilder (estresse no UI thread).
  String _lastSubscriptionGuardSignature = '';

  /// Busca global (Ctrl/Cmd+K): só quando o painel principal está liberado.
  bool _globalSearchAllowed = false;
  bool _globalSearchDialogVisible = false;
  String? _shellBootstrapMemberSearch;
  String? _shellBootstrapEventSearch;
  String? _shellBootstrapPatrimonioSearch;

  /// Um disparo: abrir ficha do membro ao entrar pelo QR (gestor).
  String? _shellBootstrapOpenMemberId;

  /// Pré-carrega dados ao passar o rato no menu (web/desktop).
  final Set<int> _shellPrefetchDone = {};

  /// Ícones **Material `*_rounded`**. Na web (release), o subset da fonte pode
  /// omitir glifos — [kChurchShellNavEntries] + [_ChurchShellNavMaterialIconsKeepalive]
  /// e `--no-tree-shake-icons` nos scripts.
  late final List<_NavItem> _items = [
    for (final e in kChurchShellNavEntries) _NavItem(e.icon, e.label),
  ];

  bool get _isDesktop => MediaQuery.sizeOf(context).width >= _breakpointDesktop;
  bool get _isMobile => MediaQuery.sizeOf(context).width < _breakpointDesktop;
  bool get _isPhone => MediaQuery.sizeOf(context).width < _breakpointPhone;

  int get _bottomNavSelectedSlot {
    final i = _kBottomNavShellIndices.indexOf(_selectedIndex);
    return i >= 0 ? i : _kBottomNavShellIndices.length;
  }

  Widget? _buildChurchBottomNavigationBar() {
    if (!_isMobile) return null;
    // Rodapé + barra inferior no mesmo bloco: evita SafeArea duplo (body + nav) no PWA/mobile web.
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: ThemeCleanPremium.cardBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 12,
          shadowColor: Colors.black.withOpacity(0.12),
          indicatorColor: ThemeCleanPremium.primary.withOpacity(0.14),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const VersionFooter(safeAreaBottom: false),
          NavigationBar(
            height: 64,
            selectedIndex: _bottomNavSelectedSlot,
            onDestinationSelected: (slot) {
              if (slot == _kBottomNavShellIndices.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scaffoldKey.currentState?.openDrawer();
                });
                return;
              }
              final idx = _kBottomNavShellIndices[slot];
              if (!_canAccessItem(idx)) {
                _showPanelSnack('Sem acesso a este módulo.', isError: true);
                return;
              }
              setState(() => _selectedIndex = idx);
            },
            destinations: [
              NavigationDestination(
                icon: Icon(_items[0].icon),
                label: 'Painel',
                tooltip: _items[0].label,
              ),
              NavigationDestination(
                icon: Icon(_items[2].icon),
                label: 'Membros',
                tooltip: _items[2].label,
              ),
              NavigationDestination(
                icon: Icon(_items[7].icon),
                label: 'Eventos',
                tooltip: _items[7].label,
              ),
              NavigationDestination(
                icon: Icon(_items[6].icon),
                label: 'Mural',
                tooltip: _items[6].label,
              ),
              const NavigationDestination(
                icon: Icon(Icons.menu_rounded),
                label: 'Menu',
                tooltip: 'Mais opções',
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final rawOpen = widget.initialOpenMemberDocId?.trim() ?? '';
    _shellBootstrapOpenMemberId = rawOpen.isEmpty ? null : rawOpen;
    HardwareKeyboard.instance.addHandler(_onShellHardwareKey);
    _loadUserPhotoFromFirestore();
    _lastPaymentTick = PaymentUiFeedbackService.paymentConfirmedTick.value;
    PaymentUiFeedbackService.paymentConfirmedTick
        .addListener(_onPaymentConfirmedTick);
    // Migração automática members → membros (servidor Admin SDK + fallback cliente)
    ChurchPanelNavigationBridge.instance.registerShellNavigator((idx) {
      if (!mounted) return;
      if (!_canAccessItem(idx)) return;
      setState(() => _selectedIndex = idx);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runMembersToMembrosMigration();
      if (_shellBootstrapOpenMemberId != null && mounted) {
        setState(() => _selectedIndex = 2);
      } else if (widget.initialShellIndex != null &&
          mounted &&
          _canAccessItem(widget.initialShellIndex!)) {
        setState(() => _selectedIndex = widget.initialShellIndex!);
      }
      unawaited(GestorWelcomeDialog.tryShowIfNeeded(
        context: context,
        tenantId: widget.tenantId,
        role: widget.role,
      ));
    });
  }

  @override
  void dispose() {
    ChurchPanelNavigationBridge.instance.unregisterShellNavigator();
    HardwareKeyboard.instance.removeHandler(_onShellHardwareKey);
    PaymentUiFeedbackService.paymentConfirmedTick
        .removeListener(_onPaymentConfirmedTick);
    super.dispose();
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

    // Tecla / — abre busca (comum na web e apps estilo "command palette").
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
      tenantId: widget.tenantId,
      userRole: widget.role,
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
    final church =
        await FirebaseFirestore.instance.collection('igrejas').doc(tid).get();
    if (!mounted) return;
    final d = church.data() ?? {};
    var slug = (d['slug'] ?? '').toString().trim();
    if (slug.isEmpty) slug = tid;
    final avisos = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tid)
        .collection('avisos');
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MuralAvisoEditorPage(
          tenantId: tid,
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
      _showPanelSnack('Sem acesso a este módulo.', isError: true);
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

  /// Copia `members` → `membros` no Firestore (Cloud Function com Admin SDK). Gestor/master.
  Future<void> _runMembersToMembrosMigration() async {
    final r = widget.role.toUpperCase().trim();
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
              'Migração: $copied registro(s) de members → membros.',
        );
      }
    } catch (_) {
      await MigrateMembersToMembrosService.instance
          .runIfNeeded(widget.tenantId);
    }
  }

  void _loadUserPhotoFromFirestore() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || (user.photoURL ?? '').trim().isNotEmpty) return;
    FirebaseFirestore.instance
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
      widget.role,
      index,
      memberCanViewFinance: widget.podeVerFinanceiro,
      memberCanViewPatrimonio: widget.podeVerPatrimonio,
      memberCanViewFornecedores: widget.podeVerFornecedores,
      permissions: widget.permissions,
    );
  }

  /// Lista só módulos que o utilizador pode abrir — membro básico não vê entradas bloqueadas
  /// (evita cinza + “Liberado pelo gestor”; o que aparece é utilizável).
  bool _shouldListNavIndex(int i) => _canAccessItem(i);

  void _navigateToShellModuleFromDashboard(int index) {
    if (!_canAccessItem(index)) {
      _showPanelSnack('Acesso negado para este módulo.', isError: true);
      return;
    }
    setState(() => _selectedIndex = index);
  }

  void _prefetchShellModuleData(int index) {
    if (!_globalSearchAllowed) return;
    if (!_canAccessItem(index)) return;
    if (_shellPrefetchDone.contains(index)) return;
    _shellPrefetchDone.add(index);
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      _shellPrefetchDone.remove(index);
      return;
    }
    final base = FirebaseFirestore.instance.collection('igrejas').doc(tid);
    try {
      switch (index) {
        case 2:
          unawaited(base.collection('membros').limit(24).get());
          break;
        case 6:
          unawaited(base.collection('avisos').limit(24).get());
          break;
        case 7:
          unawaited(base
              .collection('noticias')
              .orderBy('startAt', descending: true)
              .limit(24)
              .get());
          break;
        case 20:
          unawaited(base.collection('finance').limit(24).get());
          break;
        case 21:
          unawaited(base.collection('patrimonio').limit(24).get());
          break;
        case 22:
          unawaited(base.collection('fornecedores').limit(24).get());
          break;
        default:
          _shellPrefetchDone.remove(index);
      }
    } catch (_) {
      _shellPrefetchDone.remove(index);
    }
  }

  /// Ícone em “chip” glass sobre o azul do menu (desktop + drawer).
  Widget _navMenuIconChip(int i, bool selected, {bool compact = false}) {
    final s = compact ? 20.0 : 22.0;
    final box = compact ? 36.0 : 40.0;
    return Container(
      width: box,
      height: box,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: selected
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.07),
        border: Border.all(
          color: selected
              ? Colors.white.withValues(alpha: 0.32)
              : Colors.white.withValues(alpha: 0.1),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Icon(
        _items[i].icon,
        size: s,
        color: selected
            ? ThemeCleanPremium.navSidebarAccent
            : Colors.white.withValues(alpha: 0.9),
      ),
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
              _showPanelSnack('Acesso negado para este módulo.', isError: true);
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
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.06),
                      ],
                    )
                  : null,
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
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
    (title: 'Geral', indices: [0, 1, 23]),
    (title: 'Pessoas', indices: [2, 3, 4, 5]),
    // Pastoral (19) fica em Comunicação, não em Financeiro.
    (title: 'Comunicação', indices: [6, 7, 8, 9, 18, 19]),
    (title: 'Agenda', indices: [10, 11]),
    (title: 'Documentos', indices: [12, 13, 14]),
    (title: 'Sistema', indices: [15, 16, 17]),
    (title: 'Financeiro e patrimônio', indices: [20, 21, 22]),
  ];

  /// Entrada visível para a busca global (Ctrl/Cmd+K, tecla /).
  ///
  /// Larguras lógicas típicas: ~320 legado; 360–430 celulares; ≥600 tablet.
  /// Abaixo de [_kSearchIconOnlyMaxWidth] só ícone — libera espaço para saudação e ações.
  static const double _kSearchIconOnlyMaxWidth = 352;
  static const double _kSearchCompactLabelMaxWidth = 400;

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
        'Busca global: membros, eventos, mural e patrimônio.\n'
        'Atalhos de teclado: / (barra) · Ctrl+K · Cmd+K no Mac.';

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
                    'Buscar…',
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
          'Abre a busca. No teclado físico: tecla barra, Ctrl+K ou Cmd+K.',
      child: chip,
    );

    return Tooltip(
      message: tooltipMessage,
      waitDuration: const Duration(milliseconds: 400),
      child: chip,
    );
  }

  Widget _buildHeader({required bool licenseBlocked}) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.displayName ?? user?.email ?? 'Usuário';
    final firstName = userName.split(' ').first;
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
                tenantId: widget.tenantId,
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
                      '$periodo, $firstName',
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
                            tenantId: widget.tenantId, light: true),
                      ),
                  ],
                ),
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
                IconButton(
                  tooltip: 'Planos e assinatura',
                  onPressed: () => Navigator.push(context,
                      ThemeCleanPremium.fadeSlideRoute(const RenewPlanPage())),
                  // Material estável na web (subset de ícones arredondados pode falhar).
                  icon: const Icon(Icons.emoji_events_rounded,
                      color: Colors.white, size: 22),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
              if (_isMobile)
                IconButton(
                  icon: const Icon(Icons.emoji_events_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => Navigator.push(context,
                      ThemeCleanPremium.fadeSlideRoute(const RenewPlanPage())),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  tooltip: 'Planos',
                ),
              IconButton(
                icon: const Icon(Icons.logout_rounded,
                    color: Colors.white, size: 22),
                onPressed: () async {
                  if (kIsWeb) {
                    try {
                      final p = await SharedPreferences.getInstance();
                      await p.remove('last_route');
                    } catch (_) {}
                  }
                  await FirebaseAuth.instance.signOut();
                  // Web: [AuthGate] troca para divulgação (evita stack duplicado / tela branca).
                },
                style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                tooltip: 'Sair',
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
                          'Pagamento confirmado. Licença ativa e sistema liberado.',
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
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastSubscriptionSyncMs < 5 * 60 * 1000) return;
    _lastSubscriptionSyncMs = nowMs;
    try {
      await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .set(SubscriptionGuard.normalizedChurchFields(guard),
              SetOptions(merge: true));
    } catch (_) {
      // Sem falha visível no cliente: a proteção continua local.
    }
  }

  Widget _buildGracePeriodBanner(SubscriptionGuardState guard) {
    if (!guard.inGrace || guard.blocked) return const SizedBox.shrink();
    final days = guard.graceDaysLeft;
    final txt = days <= 0
        ? 'Atenção: sua assinatura venceu. O sistema será bloqueado hoje.'
        : 'Atenção: sua assinatura venceu. O sistema será bloqueado em $days dia(s).';
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

  /// Menu lateral esquerdo vertical azul escuro (desktop) — expansível / colapsável.
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
                    'Gestão YAHWEH',
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
                for (final section in _menuSections) ...[
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
            child: compact
                ? Tooltip(
                    message: 'Adquirir plano',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.push(
                            context,
                            ThemeCleanPremium.fadeSlideRoute(
                                const RenewPlanPage())),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0A3D91), Color(0xFF1565C0)],
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
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    child: InkWell(
                      onTap: () => Navigator.push(
                          context,
                          ThemeCleanPremium.fadeSlideRoute(
                              const RenewPlanPage())),
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0A3D91), Color(0xFF1565C0)],
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
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_card_rounded,
                                size: 20,
                                color: ThemeCleanPremium.navSidebarAccent),
                            SizedBox(width: 10),
                            Text('Adquirir Plano',
                                style: TextStyle(
                                    color: ThemeCleanPremium.navSidebarAccent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceMd),
        ],
      ),
    );
  }

  /// Drawer mobile — mesmo menu lateral azul escuro (Android/iOS, todas as versões)
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
                      'Gestão YAHWEH',
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
                    for (final section in _menuSections) ...[
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
                                        'Acesso negado para este módulo.',
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
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                child: Material(
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.push(
                          context,
                          ThemeCleanPremium.fadeSlideRoute(
                              const RenewPlanPage()));
                    },
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusSm),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0A3D91), Color(0xFF1565C0)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                ThemeCleanPremium.navSidebar.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_card_rounded,
                              size: 20,
                              color: ThemeCleanPremium.navSidebarAccent),
                          SizedBox(width: 10),
                          Text('Adquirir Plano',
                              style: TextStyle(
                                  color: ThemeCleanPremium.navSidebarAccent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
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

  /// Constrói a página do menu por índice (uma vez; depois reutilizada pelo cache).
  Widget _buildPageForIndex(int index) {
    switch (index) {
      case 0:
        return IgrejaDashboardModerno(
          key: const ValueKey('page_0'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          podeVerFornecedores: widget.podeVerFornecedores,
          permissions: widget.permissions,
          onNavigateToMembers: () => setState(() => _selectedIndex = 2),
          onNavigateToShellModule: _navigateToShellModuleFromDashboard,
        );
      case 1:
        return IgrejaCadastroPage(
            key: const ValueKey('page_1'),
            tenantId: widget.tenantId,
            role: widget.role,
            embeddedInShell: true);
      case 2:
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
          key: const ValueKey('page_2'),
          tenantId: widget.tenantId,
          role: widget.role,
          subscription: widget.subscription,
          linkedCpf: widget.cpf.trim().isEmpty ? null : widget.cpf,
          embeddedInShell: true,
          initialSearchQuery: bootMember,
          initialOpenMemberDocId: bootOpenId,
        );
      case 3:
        return DepartmentsPage(
            key: const ValueKey('page_3'),
            tenantId: widget.tenantId,
            role: widget.role,
            permissions: widget.permissions,
            embeddedInShell: true);
      case 4:
        return VisitorsPage(
            key: const ValueKey('page_4'),
            tenantId: widget.tenantId,
            role: widget.role,
            embeddedInShell: true);
      case 5:
        return CargosPage(
            key: const ValueKey('page_5'),
            tenantId: widget.tenantId,
            role: widget.role,
            embeddedInShell: true);
      case 6:
        return MuralPage(
            key: const ValueKey('page_6'),
            tenantId: widget.tenantId,
            role: widget.role,
            embeddedInShell: true);
      case 7:
        final bootEvent = _shellBootstrapEventSearch;
        if (bootEvent != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _shellBootstrapEventSearch = null);
            }
          });
        }
        return EventsManagerPage(
            key: const ValueKey('page_7'),
            tenantId: widget.tenantId,
            role: widget.role,
            permissions: widget.permissions,
            embeddedInShell: true,
            initialFeedSearchQuery: bootEvent);
      case 8:
        return PrayerRequestsPage(
            key: const ValueKey('page_8'),
            tenantId: widget.tenantId,
            role: widget.role,
            embeddedInShell: true);
      case 9:
        return CalendarPage(
            key: const ValueKey('page_9'),
            tenantId: widget.tenantId,
            role: widget.role,
            embeddedInShell: true);
      case 10:
        return MySchedulesPage(
            key: const ValueKey('page_10'),
            tenantId: widget.tenantId,
            cpf: widget.cpf,
            role: widget.role,
            embeddedInShell: true);
      case 11:
        return SchedulesPage(
            key: const ValueKey('page_11'),
            tenantId: widget.tenantId,
            role: widget.role,
            cpf: widget.cpf,
            embeddedInShell: true);
      case 12:
        return MemberCardPage(
          key: const ValueKey('page_12'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
          embeddedInShell: true,
          onNavigateToMembers: AppPermissions.isRestrictedMember(widget.role)
              ? null
              : () => setState(() => _selectedIndex = 2),
        );
      case 13:
        return CertificadosPage(
            key: const ValueKey('page_13'),
            tenantId: widget.tenantId,
            role: widget.role);
      case 14:
        return ChurchLettersPage(
          key: const ValueKey('page_14'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 15:
        return RelatoriosPage(
          key: const ValueKey('page_15'),
          tenantId: widget.tenantId,
          role: widget.role,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          podeEmitirRelatoriosCompletos: widget.podeEmitirRelatoriosCompletos,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 16:
        return ConfiguracoesPage(
          key: const ValueKey('page_16'),
          tenantId: widget.tenantId,
          role: widget.role,
          permissions: widget.permissions,
        );
      case 17:
        return SistemaInformacoesPage(
            key: const ValueKey('page_17'), tenantId: widget.tenantId);
      case 18:
        return AprovarMembrosPendentesPage(
          key: const ValueKey('page_18'),
          tenantId: widget.tenantId,
          gestorRole: widget.role,
          embeddedInShell: true,
        );
      case 19:
        return PastoralComunicacaoPage(
          key: const ValueKey('page_19'),
          tenantId: widget.tenantId,
          role: widget.role,
          embeddedInShell: true,
        );
      case 20:
        return FinancePage(
          key: const ValueKey('page_20'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 21:
        final bootPat = _shellBootstrapPatrimonioSearch;
        if (bootPat != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _shellBootstrapPatrimonioSearch = null);
            }
          });
        }
        return PatrimonioPage(
          key: const ValueKey('page_21'),
          tenantId: widget.tenantId,
          role: widget.role,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          permissions: widget.permissions,
          initialSearchQuery: bootPat,
          embeddedInShell: true,
        );
      case 22:
        return FornecedoresPage(
          key: const ValueKey('page_22'),
          tenantId: widget.tenantId,
          role: widget.role,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerFornecedores: widget.podeVerFornecedores,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 23:
        return ChurchDonationsPage(
          key: const ValueKey('page_23'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
          embeddedInShell: true,
        );
      default:
        return IgrejaDashboardModerno(
            key: ValueKey('page_$index'),
            tenantId: widget.tenantId,
            role: widget.role,
            cpf: widget.cpf,
            podeVerFinanceiro: widget.podeVerFinanceiro,
            podeVerPatrimonio: widget.podeVerPatrimonio,
            podeVerFornecedores: widget.podeVerFornecedores,
            permissions: widget.permissions,
            onNavigateToMembers: () => setState(() => _selectedIndex = 2),
            onNavigateToShellModule: _navigateToShellModuleFromDashboard);
    }
  }

  Widget _buildContent() {
    if (_selectedIndex < 0 || _selectedIndex >= _pageCache.length) {
      return RepaintBoundary(child: _buildPageForIndex(0));
    }
    if (!_canAccessItem(_selectedIndex)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
        _showPanelSnack('Acesso negado para este módulo.', isError: true);
      });
      return RepaintBoundary(child: _buildPageForIndex(0));
    }

    /// Desktop: mantém páginas visitadas no [IndexedStack] (troca rápida, mais RAM).
    if (_isDesktop) {
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

    /// Mobile/tablet: só o Painel (0) fica em cache. Demais módulos desmontam ao sair —
    /// evita até 20 telas pesadas + streams ativos (principal causa de OOM / tela preta).
    if (_selectedIndex == 0) {
      _pageCache[0] ??= _buildPageForIndex(0);
      for (var i = 1; i < _pageCache.length; i++) {
        _pageCache[i] = null;
      }
      return RepaintBoundary(child: _pageCache[0]!);
    }
    for (var i = 1; i < _pageCache.length; i++) {
      _pageCache[i] = null;
    }
    return RepaintBoundary(child: _buildPageForIndex(_selectedIndex));
  }

  /// Licença vencida (trial + carência ou assinatura): só renovação / pagamento, conforme regra do master.
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
        onRenew: () => Navigator.push(
            context, ThemeCleanPremium.fadeSlideRoute(const RenewPlanPage())),
        onLogout: () async {
          if (kIsWeb) {
            try {
              final p = await SharedPreferences.getInstance();
              await p.remove('last_route');
            } catch (_) {}
          }
          await FirebaseAuth.instance.signOut();
        },
      ),
    );
  }

  /// Tela que exige completar o cadastro da igreja antes de qualquer lançamento.
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
                          'Para usar o painel e fazer lançamentos, complete o cadastro da igreja: nome, CPF/CNPJ (se tiver), logo, endereço e link do site. Sua ficha pessoal (foto, CPF, etc.) fica em Membros.',
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
                                  tenantId: widget.tenantId,
                                  role: widget.role,
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
    // Blindagem: Voltar / tecla Android sempre para na tela inicial; só sai pelo Logout.
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
            'Use o botão "Sair" no menu para encerrar a sessão.',
            isError: true,
          );
        }
      },
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        key: ValueKey('tenant_stream_$_tenantStreamRetry'),
        stream: FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.tenantId)
            .snapshots(),
        builder: (context, tenantSnap) {
          if (tenantSnap.hasError) {
            return Scaffold(
              backgroundColor: ThemeCleanPremium.surfaceVariant,
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: ThemeCleanPremium.churchPanelBodyGradient,
                ),
                child: SafeArea(
                  child: ChurchPanelErrorBody(
                    title: 'Não foi possível carregar os dados da igreja',
                    error: tenantSnap.error,
                    onRetry: () => setState(() => _tenantStreamRetry++),
                  ),
                ),
              ),
            );
          }
          // Evita tratar “aguardando primeiro snapshot” como cadastro incompleto.
          if (tenantSnap.connectionState == ConnectionState.waiting &&
              !tenantSnap.hasData) {
            return Scaffold(
              backgroundColor: ThemeCleanPremium.surfaceVariant,
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: ThemeCleanPremium.churchPanelBodyGradient,
                ),
                child: const SafeArea(
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            );
          }
          final registrationComplete = tenantSnap.hasData == true &&
              (tenantSnap.data?.data()?['registrationComplete'] ?? true) ==
                  true;
          if (!registrationComplete) {
            return _buildCompleteCadastroObrigatorio();
          }
          final churchLive =
              tenantSnap.hasData ? tenantSnap.data?.data() : null;
          final guard = SubscriptionGuard.evaluate(
              church: churchLive, subscription: widget.subscription);
          final bool legacyBlocked = churchLive != null
              ? LicenseAccessPolicy.licenseAccessBlocked(
                  subscription: widget.subscription, church: churchLive)
              : widget.trialExpired;
          final bool licenseBlocked = guard.blocked || legacyBlocked;
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
                    top: false,
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
                              gradient:
                                  ThemeCleanPremium.churchPanelBodyGradient,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildHeader(licenseBlocked: licenseBlocked),
                                const ConnectivityOfflineStrip(),
                                const ChurchPanelAppUpdateBanner(),
                                _buildPaymentConfirmedBanner(),
                                _buildGracePeriodBanner(guard),
                                /// Fornecedores / Financeiro: UI própria em ecrã completo (abas pill / resumo) — sem título duplicado.
                                if (_selectedIndex != 0 &&
                                    _selectedIndex != 21 &&
                                    _selectedIndex != 20)
                                  ModuleHeaderPremium(
                                    title: _items[_selectedIndex].label,
                                    icon: _items[_selectedIndex].icon,
                                    onPainelBack:
                                        _isMobile && _selectedIndex != 0
                                            ? () =>
                                                setState(() => _selectedIndex = 0)
                                            : null,
                                  ),
                                Expanded(
                                  child: Semantics(
                                    container: true,
                                    label:
                                        'Conteúdo do módulo ${_items[_selectedIndex].label}',
                                    child: Padding(
                                      padding: EdgeInsets.zero,
                                      child: SaaSContentViewport(
                                        maxWidthOverride:
                                            _selectedIndex == 20 ? 10000 : null,
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
                /// Web: [Icon] com `_items[i].icon` não expõe cada glifo ao tree-shake
                /// do MaterialIcons — quadrados vazios no menu/cabeçalho. Referências
                /// diretas + `--no-tree-shake-icons` nos scripts de build cobrem o caso.
                if (kIsWeb) const _ChurchShellNavMaterialIconsKeepalive(),
                if (!_isMobile) const VersionFooter(),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Mantém glifos do menu no subset da fonte Material na **web** (build release).
/// Lista gerada a partir de [kChurchShellNavEntries] — impossível esquecer um item (ex.: mail/mic).
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

/// Linha “Local: …” no topo (dados do cadastro da igreja em Firestore).
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
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (tenantId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .snapshots(),
      builder: (context, snap) {
        final line = _lineFromChurch(snap.data?.data());
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
      },
    );
  }
}

class _HeaderVencimento extends StatelessWidget {
  final String tenantId;
  final bool light;

  const _HeaderVencimento({required this.tenantId, this.light = false});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('igrejas')
          .doc(tenantId)
          .snapshots(),
      builder: (context, snap) {
        final textColor = light ? Colors.white70 : const Color(0xFF64748B);
        if (!snap.hasData)
          return Text('Vencimento: —',
              style: TextStyle(fontSize: 11, color: textColor));
        final billing = snap.data!.data()?['billing'] as Map<String, dynamic>?;
        final next = billing?['nextChargeAt'];
        if (next == null)
          return Text('Vencimento: —',
              style: TextStyle(fontSize: 11, color: textColor));
        final dt = next is Timestamp ? next.toDate() : null;
        if (dt == null)
          return Text('Vencimento: —',
              style: TextStyle(fontSize: 11, color: textColor));
        final s =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
        return Text('Vencimento: $s',
            style: TextStyle(
                fontSize: 11,
                color: light ? Colors.white : Colors.blue.shade800,
                fontWeight: FontWeight.w600));
      },
    );
  }
}
