import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/theme_mode_provider.dart';
import 'package:gestao_yahweh/services/payment_ui_feedback_service.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
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
import 'pages/member_card_page.dart';
import 'pages/members_page.dart';
import 'pages/mural_page.dart';
import 'pages/my_schedules_page.dart';
import 'pages/plans/renew_plan_page.dart';
import 'pages/subscription_expired_page.dart';
import 'pages/schedules_page.dart';
import 'pages/certificados_page.dart';
import 'pages/prayer_requests_page.dart';
import 'pages/visitors_page.dart';
import 'pages/cargos_page.dart';
import 'pages/calendar_page.dart';
import 'pages/sistema_informacoes_page.dart';
import 'pages/configuracoes_page.dart';
import 'pages/relatorios_page.dart';
import 'pages/aprovar_membros_pendentes_page.dart';
import 'pages/pastoral_comunicacao_page.dart';
import '../services/app_permissions.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import '../services/migrate_members_to_membros_service.dart';
import 'widgets/version_footer.dart';
import 'widgets/module_header_premium.dart';
import 'widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/core/license_access_policy.dart';
import 'package:gestao_yahweh/app_theme.dart';
import 'package:gestao_yahweh/ui/widgets/church_global_search_dialog.dart';
import 'package:gestao_yahweh/ui/widgets/instagram_mural.dart'
    show MuralAvisoEditorPage;

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

  /// Permissões específicas por módulo (RBAC granular), ex.: ['financeiro','membros'].
  final List<String>? permissions;

  /// Abre Membros com a ficha deste id (ex.: leitura do QR da carteirinha por gestor).
  final String? initialOpenMemberDocId;

  const IgrejaCleanShell({
    super.key,
    required this.tenantId,
    required this.cpf,
    required this.role,
    required this.trialExpired,
    this.subscription,
    this.podeVerFinanceiro,
    this.podeVerPatrimonio,
    this.permissions,
    this.initialOpenMemberDocId,
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
  final List<Widget?> _pageCache = List.filled(21, null);
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

  final List<_NavItem> _items = const [
    _NavItem(Icons.dashboard_rounded, 'Painel'),
    _NavItem(Icons.store_rounded, 'Cadastro da Igreja'),
    _NavItem(Icons.people_rounded, 'Membros'),
    _NavItem(Icons.groups_rounded, 'Departamentos'),
    _NavItem(Icons.person_add_rounded, 'Visitantes'),
    _NavItem(Icons.work_rounded, 'Cargos'),
    _NavItem(Icons.campaign_rounded, 'Mural de Avisos'),
    _NavItem(Icons.event_rounded, 'Mural de Eventos'),
    _NavItem(Icons.volunteer_activism_rounded, 'Pedidos de Oração'),
    _NavItem(Icons.calendar_month_rounded, 'Agenda'),
    _NavItem(Icons.calendar_today_rounded, 'Minha Escala'),
    _NavItem(Icons.event_available_rounded, 'Escala Geral'),
    _NavItem(Icons.badge_rounded, 'Cartão do membro'),
    _NavItem(Icons.workspace_premium_rounded, 'Certificados'),
    _NavItem(Icons.account_balance_wallet_rounded, 'Financeiro'),
    _NavItem(Icons.inventory_2_rounded, 'Patrimônio'),
    _NavItem(Icons.assessment_rounded, 'Relatórios'),
    _NavItem(Icons.settings_rounded, 'Configurações'),
    _NavItem(Icons.info_outline_rounded, 'Informações'),
    _NavItem(Icons.how_to_reg_rounded, 'Aprovações rápidas'),
    _NavItem(Icons.campaign_rounded, 'Pastoral & comunicação'),
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
    return NavigationBar(
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runMembersToMembrosMigration();
      if (_shellBootstrapOpenMemberId != null && mounted) {
        setState(() => _selectedIndex = 2);
      }
    });
  }

  @override
  void dispose() {
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
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final meta = pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    if (!meta && !ctrl) return false;
    if (_focusInsideEditableText()) return false;
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
      permissions: widget.permissions,
    );
  }

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
        case 14:
          unawaited(base.collection('finance').limit(24).get());
          break;
        case 15:
          unawaited(base.collection('patrimonio').limit(24).get());
          break;
        default:
          _shellPrefetchDone.remove(index);
      }
    } catch (_) {
      _shellPrefetchDone.remove(index);
    }
  }

  Widget _buildNavTile(int i, {required bool compact}) {
    final item = _items[i];
    final selected = _selectedIndex == i;
    final tile = MouseRegion(
      onEnter: (_) => _prefetchShellModuleData(i),
      child: Material(
        color:
            selected ? ThemeCleanPremium.navSidebarHover : Colors.transparent,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: InkWell(
          onTap: () {
            if (!_canAccessItem(i)) {
              _showPanelSnack('Acesso negado para este módulo.', isError: true);
              return;
            }
            setState(() => _selectedIndex = i);
          },
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ThemeCleanPremium.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 0 : ThemeCleanPremium.spaceSm,
                  vertical: 6),
              child: compact
                  ? Center(
                      child: Icon(
                        item.icon,
                        color: selected
                            ? ThemeCleanPremium.navSidebarAccent
                            : Colors.white70,
                        size: 24,
                      ),
                    )
                  : Row(
                      children: [
                        if (selected)
                          Container(
                            width: 4,
                            height: 24,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: ThemeCleanPremium.navSidebarAccent,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [
                                BoxShadow(
                                  color: ThemeCleanPremium.navSidebarAccent
                                      .withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        Icon(
                          item.icon,
                          color: selected
                              ? ThemeCleanPremium.navSidebarAccent
                              : Colors.white70,
                          size: 22,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            item.label,
                            style: TextStyle(
                              color: selected
                                  ? ThemeCleanPremium.navSidebarAccent
                                  : Colors.white,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 14,
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
    (title: 'Geral', indices: [0, 1]),
    (title: 'Pessoas', indices: [2, 3, 4, 5]),
    (title: 'Comunicação', indices: [6, 7, 8, 9, 20]),
    (title: 'Agenda', indices: [10, 11]),
    (title: 'Documentos', indices: [12, 13]),
    (title: 'Financeiro', indices: [14, 15]),
    (title: 'Relatórios', indices: [16]),
    (title: 'Sistema', indices: [17, 18, 19]),
  ];

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
      elevation: 0,
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
              if (_isDesktop) ...[
                IconButton(
                  tooltip: 'Busca rápida (Ctrl+K ou Cmd+K)',
                  onPressed:
                      _globalSearchAllowed ? _openChurchGlobalSearch : null,
                  icon: Icon(
                    Icons.search_rounded,
                    color: _globalSearchAllowed
                        ? Colors.white
                        : Colors.white.withOpacity(0.35),
                    size: 22,
                  ),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
                IconButton(
                  tooltip: 'Planos e assinatura',
                  onPressed: () => Navigator.push(context,
                      ThemeCleanPremium.fadeSlideRoute(const RenewPlanPage())),
                  icon: const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 22),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
              if (_isMobile) ...[
                IconButton(
                  tooltip: 'Busca rápida',
                  onPressed:
                      _globalSearchAllowed ? _openChurchGlobalSearch : null,
                  icon: Icon(
                    Icons.search_rounded,
                    color: _globalSearchAllowed
                        ? Colors.white
                        : Colors.white.withOpacity(0.35),
                    size: 22,
                  ),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
                IconButton(
                  icon: const Icon(Icons.workspace_premium_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => Navigator.push(context,
                      ThemeCleanPremium.fadeSlideRoute(const RenewPlanPage())),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  tooltip: 'Planos',
                ),
              ],
              IconButton(
                icon: const Icon(Icons.logout_rounded,
                    color: Colors.white, size: 22),
                onPressed: () {
                  final nav =
                      Navigator.of(context, rootNavigator: true);
                  FirebaseAuth.instance.signOut().then((_) {
                    nav.pushNamedAndRemoveUntil('/', (_) => false);
                  });
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
    final sidebarW = compact ? 72.0 : 212.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: sidebarW,
      decoration: const BoxDecoration(
        color: ThemeCleanPremium.navSidebar,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(2, 0))
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
                const Flexible(
                    child: Text('Gestão YAHWEH',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14))),
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
                  if (section.indices.any(_canAccessItem)) ...[
                    if (!compact)
                      Padding(
                        padding: const EdgeInsets.only(
                            left: ThemeCleanPremium.spaceSm,
                            top: ThemeCleanPremium.spaceMd,
                            bottom: ThemeCleanPremium.spaceSm),
                        child: Text(
                          section.title.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withOpacity(0.5),
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    for (final i in section.indices)
                      if (_canAccessItem(i))
                        Padding(
                          key: ValueKey('nav_$i'),
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildNavTile(i, compact: compact),
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
        color: ThemeCleanPremium.navSidebar,
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
                    const Text('Gestão YAHWEH',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: ThemeCleanPremium.spaceSm, vertical: 10),
                  children: [
                    for (final section in _menuSections) ...[
                      if (section.indices.any(_canAccessItem)) ...[
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 18, top: 18, bottom: 10),
                          child: Text(
                            section.title.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withOpacity(0.5),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                      for (final i in section.indices)
                        if (_canAccessItem(i))
                          MouseRegion(
                            onEnter: (_) => _prefetchShellModuleData(i),
                            child: ListTile(
                              key: ValueKey('drawer_$i'),
                              leading: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_selectedIndex == i)
                                    Container(
                                      width: 4,
                                      height: 22,
                                      margin: const EdgeInsets.only(right: 10),
                                      decoration: BoxDecoration(
                                        color:
                                            ThemeCleanPremium.navSidebarAccent,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  Icon(_items[i].icon,
                                      color: _selectedIndex == i
                                          ? ThemeCleanPremium.navSidebarAccent
                                          : Colors.white70,
                                      size: 22),
                                ],
                              ),
                              title: Text(
                                _items[i].label,
                                style: TextStyle(
                                  color: _selectedIndex == i
                                      ? ThemeCleanPremium.navSidebarAccent
                                      : Colors.white,
                                  fontWeight: _selectedIndex == i
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: _isPhone ? 15 : 14,
                                ),
                              ),
                              selected: _selectedIndex == i,
                              selectedTileColor:
                                  ThemeCleanPremium.navSidebarHover,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      ThemeCleanPremium.radiusMd)),
                              minVerticalPadding: _isPhone ? 16 : 14,
                              onTap: () {
                                if (!_canAccessItem(i)) {
                                  _showPanelSnack(
                                      'Acesso negado para este módulo.',
                                      isError: true);
                                  return;
                                }
                                setState(() => _selectedIndex = i);
                                Navigator.of(context).pop();
                              },
                            ),
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
          permissions: widget.permissions,
          onNavigateToEventos: () => setState(() => _selectedIndex = 7),
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
            permissions: widget.permissions);
      case 4:
        return VisitorsPage(
            key: const ValueKey('page_4'),
            tenantId: widget.tenantId,
            role: widget.role);
      case 5:
        return CargosPage(
            key: const ValueKey('page_5'),
            tenantId: widget.tenantId,
            role: widget.role);
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
            embeddedInShell: true,
            initialFeedSearchQuery: bootEvent);
      case 8:
        return PrayerRequestsPage(
            key: const ValueKey('page_8'),
            tenantId: widget.tenantId,
            role: widget.role);
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
            role: widget.role);
      case 11:
        return SchedulesPage(
            key: const ValueKey('page_11'),
            tenantId: widget.tenantId,
            role: widget.role,
            cpf: widget.cpf);
      case 12:
        return MemberCardPage(
          key: const ValueKey('page_12'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
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
        return FinancePage(
          key: const ValueKey('page_14'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          permissions: widget.permissions,
        );
      case 15:
        final bootPat = _shellBootstrapPatrimonioSearch;
        if (bootPat != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _shellBootstrapPatrimonioSearch = null);
            }
          });
        }
        return PatrimonioPage(
          key: const ValueKey('page_15'),
          tenantId: widget.tenantId,
          role: widget.role,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          permissions: widget.permissions,
          initialSearchQuery: bootPat,
        );
      case 16:
        return RelatoriosPage(
          key: const ValueKey('page_16'),
          tenantId: widget.tenantId,
          role: widget.role,
          podeVerFinanceiro: widget.podeVerFinanceiro,
          podeVerPatrimonio: widget.podeVerPatrimonio,
          permissions: widget.permissions,
          embeddedInShell: true,
        );
      case 17:
        return ConfiguracoesPage(
          key: const ValueKey('page_17'),
          tenantId: widget.tenantId,
          role: widget.role,
          cpf: widget.cpf.trim().isEmpty ? null : widget.cpf,
        );
      case 18:
        return SistemaInformacoesPage(
            key: const ValueKey('page_18'), tenantId: widget.tenantId);
      case 19:
        return AprovarMembrosPendentesPage(
          key: const ValueKey('page_19'),
          tenantId: widget.tenantId,
          gestorRole: widget.role,
        );
      case 20:
        return PastoralComunicacaoPage(
          key: const ValueKey('page_20'),
          tenantId: widget.tenantId,
          role: widget.role,
        );
      default:
        return IgrejaDashboardModerno(
            key: ValueKey('page_$index'),
            tenantId: widget.tenantId,
            role: widget.role,
            cpf: widget.cpf,
            podeVerFinanceiro: widget.podeVerFinanceiro,
            podeVerPatrimonio: widget.podeVerPatrimonio,
            permissions: widget.permissions,
            onNavigateToEventos: () => setState(() => _selectedIndex = 7),
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
        onLogout: () {
          final nav = Navigator.of(context, rootNavigator: true);
          FirebaseAuth.instance.signOut().then((_) {
            nav.pushNamedAndRemoveUntil('/', (_) => false);
          });
        },
      ),
    );
  }

  /// Tela que exige completar o cadastro da igreja antes de qualquer lançamento.
  Widget _buildCompleteCadastroObrigatorio() {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      body: SafeArea(
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
                        'Para usar o painel e fazer lançamentos, é necessário completar o cadastro da sua igreja (nome, endereço e dados do gestor). A logo pode ser adicionada depois.',
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
              body: SafeArea(
                child: ChurchPanelErrorBody(
                  title: 'Não foi possível carregar os dados da igreja',
                  error: tenantSnap.error,
                  onRetry: () => setState(() => _tenantStreamRetry++),
                ),
              ),
            );
          }
          // Evita tratar “aguardando primeiro snapshot” como cadastro incompleto.
          if (tenantSnap.connectionState == ConnectionState.waiting &&
              !tenantSnap.hasData) {
            return Scaffold(
              backgroundColor: ThemeCleanPremium.surfaceVariant,
              body: const SafeArea(
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildHeader(licenseBlocked: licenseBlocked),
                              _buildPaymentConfirmedBanner(),
                              _buildGracePeriodBanner(guard),
                              if (_selectedIndex != 0)
                                ModuleHeaderPremium(
                                  title: _items[_selectedIndex].label,
                                  icon: _items[_selectedIndex].icon,
                                  onPainelBack: _isMobile && _selectedIndex != 0
                                      ? () => setState(() => _selectedIndex = 0)
                                      : null,
                                ),
                              if (_selectedIndex != 0)
                                const SizedBox(height: 4),
                              Expanded(
                                child: Semantics(
                                  container: true,
                                  label:
                                      'Conteúdo do módulo ${_items[_selectedIndex].label}',
                                  child: Padding(
                                    padding: EdgeInsets.zero,
                                    child: SaaSContentViewport(
                                      child: _buildContent(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  bottom: true,
                  child: const VersionFooter(),
                ),
              ],
            ),
          );
        },
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
