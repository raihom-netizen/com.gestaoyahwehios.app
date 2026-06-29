import 'dart:async' show StreamSubscription, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_premium_gradients.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        FreshFirebaseStorageImage,
        SafeNetworkImage,
        firebaseStorageMediaUrlLooksLike,
        isFirebaseStorageHttpUrl,
        imageUrlFromMap,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        preloadNetworkImages,
        sanitizeImageUrl;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/ui/widgets/foto_membro_widget.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart'
    show SafeMemberProfilePhoto, memberPhotoDisplayCacheRevision;
import 'package:gestao_yahweh/ui/widgets/member_avatar_utils.dart' show avatarColorForMember;
import 'package:gestao_yahweh/ui/widgets/member_demographics_utils.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/core/public_member_signup_navigation.dart';
import 'package:gestao_yahweh/core/event_template_schedule.dart'
    show eventTemplateIncludeInAgenda;
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/panel_programacao_loader.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/core/panel_feed_post_validator.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_eventos_load_service.dart';
import 'package:gestao_yahweh/services/church_dashboard_cache_service.dart';
import 'package:gestao_yahweh/services/church_dashboard_current_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_public_site_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_preheat_coordinator.dart';
import 'package:gestao_yahweh/services/panel_media_prefetch_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_analytics.dart';
import 'package:gestao_yahweh/ui/widgets/dashboard_finance_hub.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/services/yahweh_performance_monitor.dart';
import 'package:gestao_yahweh/services/panel_finance_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_finance_chart_service.dart';
import 'package:gestao_yahweh/services/church_finance_realtime_service.dart';
import 'package:gestao_yahweh/services/church_finance_load_service.dart';
import 'package:gestao_yahweh/core/panel/panel_resilient_load.dart';
import 'package:gestao_yahweh/services/yahweh_panel_cache_warmup.dart';
import 'package:gestao_yahweh/core/utils/independent_futures.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaPhotoUrls,
        eventNoticiaVideoThumbUrl,
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaVideosFromDoc,
        eventNoticiaImageStoragePath,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaExternalVideoUrl,
        eventNoticiaUrlEligibleForHostedInlinePlayer,
        looksLikeHostedVideoFileUrl,
        postFeedCarouselAspectRatioForIndex;
import 'package:gestao_yahweh/ui/widgets/church_public_event_detail_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_post_card.dart'
    show yahwehPostGalleryRefs;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show
        scheduleFeedMediaWarmup,
        showYahwehFullscreenZoomableImage,
        YahwehPremiumFeedShimmer;
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/core/noticia_share_links.dart';
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show buildNoticiaInviteShareMessage;
import 'package:gestao_yahweh/ui/widgets/church_noticia_share_sheet.dart'
    show showChurchNoticiaShareSheet, shareRectFromContext;
import 'package:gestao_yahweh/ui/widgets/church_post_rich_text_utils.dart'
    show churchPostPlainText;
import 'package:gestao_yahweh/ui/widgets/noticia_photo_gallery_page.dart';
import 'package:gestao_yahweh/ui/widgets/noticia_comments_bottom_sheet.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_premium_ui.dart'
    show churchMuralCarouselClipHeight;
import 'package:gestao_yahweh/ui/widgets/church_ministry_health_panel.dart';
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart'
    show ChurchHostedVideoSurface, showChurchHostedVideoDialog;
import 'aniversariantes_ano_page.dart';
import 'lideranca_page.dart';
import 'package:gestao_yahweh/core/church_corpo_admin_roles.dart';
import 'package:gestao_yahweh/core/panel_scroll_bridge.dart';
import 'package:gestao_yahweh/services/church_birthday_query_service.dart';
import 'package:gestao_yahweh/ui/widgets/panel_dashboard_home_extras.dart';
import 'package:gestao_yahweh/ui/widgets/panel_home_welcome_banner.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_links_card.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_context_service.dart';
import 'package:gestao_yahweh/services/church_cadastro_load_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/core/tenant/church_context.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/core/dashboard/church_dashboard_panel_controller.dart';
import 'package:gestao_yahweh/core/dashboard/church_dashboard_engagement_controller.dart';
import 'package:gestao_yahweh/core/dashboard/church_dashboard_finance_period.dart';
import 'package:gestao_yahweh/core/finance_infer_tipo.dart';
import 'dart:ui' show ImageFilter;
import 'igreja_cadastro_page.dart';
import 'members_page.dart';
import 'finance_page.dart';
import 'mural_page.dart';
import 'events_manager_page.dart';
import 'aprovar_membros_pendentes_page.dart';
import 'prayer_requests_page.dart';
import 'visitors_page.dart';
import '../../services/app_permissions.dart';
import 'package:gestao_yahweh/core/roles_permissions.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_institutional_video.dart';
import 'package:gestao_yahweh/ui/widgets/church_global_search_dialog.dart'
    show kChurchShellIndexMySchedules;
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/noticia_event_feed.dart'
    show
        noticiaEventoEhRotinaOuGeradoAutomatico,
        noticiaDocEhEventoSpecialFeed;
import 'package:gestao_yahweh/core/event_feed_mural_visibility.dart'
    show noticiaEventoEspecialCaiuDoFeedParaGaleria;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/ui/widgets/pastoral_inbox_home_card.dart';
import 'package:gestao_yahweh/services/church_birthday_parabenizar.dart';
import 'package:gestao_yahweh/ui/widgets/church_wisdom_birthday_ui.dart';
import 'package:gestao_yahweh/services/church_gallery_photo_warmup.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/yahweh_whatsapp_service.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_whatsapp_one_tap_button.dart';
import 'package:gestao_yahweh/ui/widgets/church_role_badge.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_super_premium_action_button.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_leadership_cards.dart';
import 'package:gestao_yahweh/services/church_panel_leadership_load_service.dart'
    show ChurchPanelLeadershipSection;

/// Dashboard Clean Premium — Aniversariantes, líderes, stats e gráficos (saudação no topo do shell).
/// Membros via `MembersDirectorySnapshotService` + cache painel (sem N streams `membros`).
class IgrejaDashboardModerno extends StatefulWidget {
  final String tenantId;
  final String role;
  final String cpf;
  /// Abre o módulo Membros no shell (atalho a partir do painel de saúde ministerial).
  final VoidCallback? onNavigateToMembers;

  /// Mesmas flags do shell — financeiro, patrimônio e fornecedores só no painel para quem pode ver.
  final bool? podeVerFinanceiro;
  final bool? podeVerPatrimonio;
  final bool? podeVerFornecedores;
  final List<String>? permissions;

  /// Abre módulo pelo índice do menu [IgrejaCleanShell] (1 = cadastro, 2 = membros, …).
  final ValueChanged<int> onNavigateToShellModule;

  const IgrejaDashboardModerno({
    super.key,
    required this.tenantId,
    required this.role,
    required this.cpf,
    this.onNavigateToMembers,
    this.podeVerFinanceiro,
    this.podeVerPatrimonio,
    this.podeVerFornecedores,
    this.permissions,
    required this.onNavigateToShellModule,
  });

  @override
  State<IgrejaDashboardModerno> createState() => _IgrejaDashboardModernoState();
}

class _IgrejaDashboardModernoState extends State<IgrejaDashboardModerno>
    with WidgetsBindingObserver {
  final GlobalKey<ChurchMinistryHealthPanelState> _ministryHealthKey =
      GlobalKey<ChurchMinistryHealthPanelState>();

  Stream<QuerySnapshot<Map<String, dynamic>>>? _membersStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _deptStream;
  bool _heavyDashboardStreamsScheduled = false;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _avisosStream;
  /// Eventos especiais (`noticias`) com data futura / ainda no Feed — nunca o que já caiu para a Galeria.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _noticiasPainelStream;
  /// ID efetivo da igreja (resolve slug/alias) — mesmo usado em Storage `igrejas/{id}/membros/...`.
  String _effectiveTenantId = '';
  String _churchSlug = '';
  String _churchNome = '';
  final ChurchDashboardEngagementController _engagementCtrl =
      ChurchDashboardEngagementController();

  ChurchDashboardFinancePreset _dashFinancePreset =
      ChurchDashboardFinancePreset.currentMonth;
  DateTimeRange? _dashCustomFinanceRange;

  /// Cache `_panel_cache/dashboard_summary` — pintura instantânea do topo do painel.
  PanelDashboardSnapshot _panelCache = const PanelDashboardSnapshot();

  final ScrollController _panelScroll = ScrollController();
  final GlobalKey _corpoAdminSectionKey = GlobalKey();
  List<String> _corpoAdminRoles = ChurchCorpoAdminRoles.defaultRoleKeys;

  /// KPIs pré-processados (`_performance_cache/dashboard_current`).
  ChurchDashboardCurrent _dashboardKpis = const ChurchDashboardCurrent();

  /// 1 leitura — `igrejas/{churchId}/_dashboard_cache/main` (servidor pré-calcula).
  ChurchDashboardCacheSnapshot? _dashboardMainCache;

  StreamSubscription<ChurchDashboardCacheSnapshot?>? _dashboardMainSub;

  /// Cache `_panel_cache/members_directory` — fallback quando stream `membros` falha na web.
  MembersDirectorySnapshot _membersDirectory = const MembersDirectorySnapshot();

  StreamSubscription<MembersDirectorySnapshot>? _membersDirectorySub;

  bool _initialAuthTokenForced = false;

  int _financeDashTick = 0;
  VoidCallback? _financeMutationListener;

  DateTimeRange get _resolvedDashFinanceRange =>
      ChurchDashboardFinancePeriod.resolve(
        preset: _dashFinancePreset,
        custom: _dashCustomFinanceRange,
      );

  Future<void> _onDashFinancePresetTap(
      ChurchDashboardFinancePreset preset) async {
    if (preset == ChurchDashboardFinancePreset.custom) {
      final now = DateTime.now();
      final initial = _dashCustomFinanceRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month, now.day),
          );
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 6),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: initial,
        locale: const Locale('pt', 'BR'),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: ThemeCleanPremium.primary,
                brightness: Brightness.light,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      );
      if (!mounted || picked == null) return;
      setState(() {
        _dashFinancePreset = ChurchDashboardFinancePreset.custom;
        _dashCustomFinanceRange = picked;
      });
      return;
    }
    setState(() {
      _dashFinancePreset = preset;
      _dashCustomFinanceRange = null;
    });
  }

  @override
  void initState() {
    super.initState();
    logYahwehModuleScreen('dashboard');
    YahwehPerformanceMonitor.markScreenStart('igreja_dashboard');
    WidgetsBinding.instance.addObserver(this);
    _effectiveTenantId = ChurchPanelTenant.resolve(widget.tenantId);
    PanelScrollBridge.scrollToCorpoAdministrativo =
        _scrollToCorpoAdministrativo;
    final tidBoot = _effectiveTenantId.trim();
    if (tidBoot.isNotEmpty) {
      _effectiveTenantId = tidBoot;
      final memDir = MembersDirectorySnapshotService.peekMemory(tidBoot);
      if (memDir != null && memDir.hasEntries) {
        _membersDirectory = memDir;
      }
      unawaited(_attachPanelFeedStreams(tidBoot).catchError((e, st) {
        debugPrint('Dashboard init attachPanelFeedStreams: $e\n$st');
      }));
      _bindMembersDirectoryWatch(tidBoot);
      unawaited(_paintPanelFromLocalCacheFirst(tidBoot));
      unawaited(MembersDirectorySnapshotService.warmFromCallableIfStale(tidBoot));
      unawaited(_hydrateMembersDirectory(tidBoot));
      final churchIdBoot = ChurchRepository.churchId(tidBoot);
      if (churchIdBoot.isNotEmpty) {
        setState(() {
          _deptStream ??= _createDepartmentsOneShotStream(churchIdBoot);
        });
      }
    }
    _loadStreams();
    _financeMutationListener = () {
      if (!mounted) return;
      setState(() => _financeDashTick++);
    };
    ChurchFinanceRealtimeService.mutationEpoch
        .addListener(_financeMutationListener!);
  }

  void _attachHeavyDashboardStreamsInline(String churchId) {
    _heavyDashboardStreamsScheduled = true;
    // Controle Total: directory + one-shot dept — evita 2+ listeners live por tenant no mobile.
    _membersStream = null;
    _deptStream = _createDepartmentsOneShotStream(churchId);
    unawaited(_hydrateMembersDirectory(_effectiveTenantId));
  }

  void _scheduleHeavyDashboardStreams(
    String churchId, {
    bool force = false,
  }) {
    if (!force && _heavyDashboardStreamsScheduled) return;
    if (!mounted) return;
    if (force) {
      setState(() => _attachHeavyDashboardStreamsInline(churchId));
      return;
    }
    _heavyDashboardStreamsScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _attachHeavyDashboardStreamsInline(churchId));
    });
  }

  void _bindMembersDirectoryWatch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    _membersDirectorySub?.cancel();
    _membersDirectorySub =
        MembersDirectorySnapshotService.watch(tid).listen((dir) {
      if (!mounted || !dir.hasEntries) return;
      if (_membersDirectory.totalCount == dir.totalCount &&
          _membersDirectory.hasEntries) {
        return;
      }
      setState(() => _membersDirectory = dir);
    });
  }

  void _bindDashboardMainCacheWatch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    _dashboardMainSub?.cancel();
    _dashboardMainSub = ChurchDashboardCacheService.watch(churchIdHint: tid).listen(
      (snap) {
        if (!mounted || snap == null || !snap.hasData) return;
        setState(() => _dashboardMainCache = snap);
      },
    );
  }

  @override
  void dispose() {
    if (_financeMutationListener != null) {
      ChurchFinanceRealtimeService.mutationEpoch
          .removeListener(_financeMutationListener!);
    }
    WidgetsBinding.instance.removeObserver(this);
    _dashboardMainSub?.cancel();
    _membersDirectorySub?.cancel();
    _engagementCtrl.dispose();
    _panelScroll.dispose();
    if (PanelScrollBridge.scrollToCorpoAdministrativo ==
        _scrollToCorpoAdministrativo) {
      PanelScrollBridge.scrollToCorpoAdministrativo = null;
    }
    super.dispose();
  }

  void _openAniversariantesAnoPage() {
    final tid = _effectiveTenantId.trim();
    if (tid.isEmpty) return;
    Navigator.of(context).push(
      ThemeCleanPremium.fadeSlideRoute(
        AniversariantesAnoPage(
          tenantId: tid,
          memberRole: widget.role,
          viewerCpfDigits: widget.cpf.replaceAll(RegExp(r'\D'), ''),
          membersDirectory: _bestMembersDirectory(),
        ),
      ),
    );
  }

  void _scrollToCorpoAdministrativo() {
    final ctx = _corpoAdminSectionKey.currentContext;
    if (ctx != null) {
      unawaited(Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      ));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    final tid = _effectiveTenantId.trim();
    if (tid.isEmpty || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_hydrateMembersDirectory(tid));
      setState(() {
        _scheduleHeavyDashboardStreams(
          ChurchRepository.churchId(tid).isNotEmpty
              ? ChurchRepository.churchId(tid)
              : tid,
          force: true,
        );
        if (_effectiveTenantId.trim().isNotEmpty) {
          _attachPanelFeedStreams(_effectiveTenantId);
        }
      });
      unawaited(scheduleYahwehPanelImageWarmup(
        context,
        tid,
        resolvedTenantId: tid,
      ));
    });
  }

  /// churchId canónico — mesma API Membros/Android/iOS/Web.
  Future<String> _resolveEffectiveTenantId() async {
    final bound = ChurchContext.currentChurchId?.trim() ?? '';
    if (bound.isNotEmpty) return bound;
    final id = ChurchRepository.churchId(widget.tenantId);
    return id.isNotEmpty ? id : widget.tenantId.trim();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> _emptyQueryStream() =>
      Stream<QuerySnapshot<Map<String, dynamic>>>.value(
        const MergedFirestoreQuerySnapshot([]),
      );

  bool get _dashCanFinance => AppPermissions.canViewFinance(
        widget.role,
        memberCanViewFinance: widget.podeVerFinanceiro,
        permissions: widget.permissions,
      );

  bool get _panelCanPaintWithoutSkeleton {
    final tid = ChurchPanelTenant.resolve(widget.tenantId).trim();
    if (tid.isEmpty) return false;
    return _effectiveTenantId.trim().isNotEmpty ||
        _dashboardMainCache?.hasData == true ||
        _panelCache.isFreshForInstantPanel ||
        _panelCache.hasBirthdayData ||
        _panelCache.hasHomeLeaders ||
        _panelCache.hasHomeCorpo ||
        _panelCache.membersTotalCount > 0 ||
        _membersDirectory.hasEntries ||
        (_avisosStream != null && _noticiasPainelStream != null);
  }

  int? _effectiveCachedMemberTotal() {
    final main = _dashboardMainCache?.totalMembros ?? 0;
    if (main > 0) return main;
    final k = _dashboardKpis.totalMembers;
    if (k > 0) return k;
    final p = _panelCache.membersTotalCount;
    if (p > 0) return p;
    final d = _membersDirectory.totalCount;
    if (d > 0) return d;
    return null;
  }

  /// Slug público da igreja (slug, slugId ou alias).
  static String _slugFromTenantData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return '';
    return (data['slug'] ?? data['slugId'] ?? data['alias'] ?? '')
        .toString()
        .trim();
  }

  MembersDirectorySnapshot? _bestMembersDirectory() {
    if (_membersDirectory.hasEntries) return _membersDirectory;
    final peek =
        MembersDirectorySnapshotService.peekMemory(_effectiveTenantId);
    if (peek != null && peek.hasEntries) return peek;
    return null;
  }

  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
      _syntheticMembersSnapFromDirectory() {
    final dir = _bestMembersDirectory();
    if (dir == null) {
      return AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>.waiting();
    }
    return AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>.withData(
      ConnectionState.done,
      MembersDirectorySnapshotService.toMergedQuerySnapshot(
        _effectiveTenantId,
        dir,
      ),
    );
  }

  Future<void> _hydrateMembersDirectory(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final peek = MembersDirectorySnapshotService.peekMemory(tid);
    if (peek != null && peek.hasEntries && mounted) {
      setState(() => _membersDirectory = peek);
    }
    var dir = await MembersDirectorySnapshotService.readOnce(tid);
    if (!mounted) return;
    if (dir.hasEntries) {
      setState(() => _membersDirectory = dir);
      return;
    }
    final knownTotal = _effectiveCachedMemberTotal() ?? 0;
    if (knownTotal <= 0) return;
    dir = await MembersDirectorySnapshotService.warmFromCallableIfStale(tid);
    if (!mounted || !dir.hasEntries) return;
    setState(() => _membersDirectory = dir);
  }

  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> _resolvedMembersAsyncSnap(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> streamSnap,
  ) {
    final dir = _bestMembersDirectory();
    if (dir != null) {
      final streamDocs = streamSnap.data?.docs ?? const [];
      if (streamSnap.hasError ||
          streamDocs.isEmpty ||
          (streamSnap.connectionState == ConnectionState.waiting &&
              !streamSnap.hasData)) {
        final synthetic = MembersDirectorySnapshotService.toMergedQuerySnapshot(
          _effectiveTenantId,
          dir,
        );
        return AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>.withData(
          ConnectionState.done,
          synthetic,
        );
      }
    }

    if (streamSnap.hasError) return streamSnap;

    final streamDocs = streamSnap.data?.docs ?? const [];
    if (streamDocs.isNotEmpty) return streamSnap;

    final synthetic = _syntheticMembersSnapFromDirectory();
    if (synthetic.hasData) return synthetic;

    return streamSnap;
  }

  Future<void> _attachPanelFeedStreams(String resolved) async {
    final op = ChurchRepository.churchId(resolved);
    if (op.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _avisosStream = FirestoreStreamUtils.oneShotQueryFromFuture(() async {
        final r = await ChurchAvisosLoadService.loadFeed(
          seedTenantId: op,
          limit: PanelFeedPostValidator.kPanelFeedPageSize,
        );
        return r.snapshot;
      });
      _noticiasPainelStream = FirestoreStreamUtils.oneShotQueryFromFuture(
        () async {
          final r = await ChurchEventosLoadService.loadFeed(
            seedTenantId: op,
            limit: PanelFeedPostValidator.kPanelFeedPageSize,
          );
          return r.snapshot;
        },
      );
    });
  }

  /// Cache Firestore local antes do bootstrap — evita skeleton prolongado na web.
  Future<void> _paintPanelFromLocalCacheFirst(String resolved) async {
    final tid = resolved.trim();
    if (tid.isEmpty) return;
    try {
      _bindDashboardMainCacheWatch(tid);
      final mainCache = await ChurchDashboardCacheService.load(churchIdHint: tid);
      if (!mounted) return;
      if (mainCache != null && mainCache.hasData) {
        _attachPanelFeedStreams(tid);
        _bindMembersDirectoryWatch(tid);
        setState(() {
          _effectiveTenantId = tid;
          _dashboardMainCache = mainCache;
        });
        if (mainCache.totalMembros > 0) {
          _scheduleHeavyDashboardStreams(
          ChurchRepository.churchId(tid).isNotEmpty
              ? ChurchRepository.churchId(tid)
              : tid,
          force: true,
        );
        }
      }
      final quick = await IndependentFutures.pair(
        PanelDashboardSnapshotService.readOnce(tid),
        ChurchDashboardCurrentService.readOnceFromLocalCache(tid),
      );
      if (!mounted) return;
      final quickPanel = quick.$1;
      _attachPanelFeedStreams(tid);
      _bindMembersDirectoryWatch(tid);
      setState(() {
        _effectiveTenantId = tid;
        if (quickPanel != null) _panelCache = quickPanel;
        if (quick.$2 != null) _dashboardKpis = quick.$2!;
        if (mainCache != null && mainCache.hasData) {
          _dashboardMainCache = mainCache;
        }
      });
      if (quickPanel != null &&
          (quickPanel.hasHomeLeaders ||
              quickPanel.homeCorpoAdmin.isNotEmpty ||
              quickPanel.birthdaysToday.isNotEmpty)) {
        unawaited(
          ChurchGalleryPhotoWarmup.warmBytesForPanel(
            tenantId: tid,
            panel: quickPanel,
          ),
        );
      }
      unawaited(_hydrateMembersDirectory(tid));
      if (quickPanel != null && !quickPanel.isFreshForInstantPanel) {
        if (quickPanel.membersTotalCount > 0) {
          _scheduleHeavyDashboardStreams(
          ChurchRepository.churchId(tid).isNotEmpty
              ? ChurchRepository.churchId(tid)
              : tid,
          force: true,
        );
        }
      }
    } catch (e, st) {
      debugPrint('Dashboard _paintPanelFromLocalCacheFirst: $e\n$st');
    }
  }

  Future<void> _loadStreams() async {
    var resolved = widget.tenantId.trim();
    try {
      final op = await _resolveEffectiveTenantId()
          .timeout(const Duration(seconds: 10));
      if (op.trim().isNotEmpty) resolved = op.trim();
    } catch (e, st) {
      debugPrint('Dashboard _loadStreams resolve tenant: $e\n$st');
    }

    if (resolved.isNotEmpty) {
      unawaited(_paintPanelFromLocalCacheFirst(resolved));
    }

    unawaited(
      ensureFirebaseReadyForPanelRead().catchError((e, st) {
        if (mounted) {
          debugPrint('Painel: Firebase indisponível: $e\n$st');
        }
      }),
    );
    if (!mounted) return;
    if (resolved.isNotEmpty && !_panelCanPaintWithoutSkeleton) {
      final quick = await IndependentFutures.pair(
        PanelDashboardSnapshotService.readOnce(resolved),
        ChurchDashboardCurrentService.readOnce(resolved),
      );
      if (mounted) {
        final quickPanel = quick.$1;
        _attachPanelFeedStreams(resolved);
        _bindMembersDirectoryWatch(resolved);
        setState(() {
          _effectiveTenantId = resolved;
          if (quickPanel != null) _panelCache = quickPanel;
          if (quick.$2 != null) _dashboardKpis = quick.$2!;
        });
        if (quickPanel != null &&
            (quickPanel.hasHomeLeaders ||
                quickPanel.homeCorpoAdmin.isNotEmpty ||
                quickPanel.birthdaysToday.isNotEmpty)) {
          unawaited(
            ChurchGalleryPhotoWarmup.warmBytesForPanel(
              tenantId: resolved,
              panel: quickPanel,
            ),
          );
        }
      }
    } else if (resolved.isNotEmpty && _panelCanPaintWithoutSkeleton) {
      final kpis = await ChurchDashboardCurrentService.readOnce(resolved);
      if (mounted) {
        setState(() => _dashboardKpis = kpis);
      }
    }

    final forceToken = !_initialAuthTokenForced;
    if (forceToken) _initialAuthTokenForced = true;
    unawaited(FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: forceToken));
    if (!mounted) return;
    final churchId = ChurchRepository.churchId(resolved);
    var effectiveChurchId =
        churchId.isNotEmpty ? churchId : resolved.trim();
    var churchSlug = '';
    var churchNome = '';
    DocumentSnapshot<Map<String, dynamic>>? igSnap;
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((e, st) {
          debugPrint('Dashboard _boot ensurePanelReadReady: $e\n$st');
        });
      }
      Future<DocumentSnapshot<Map<String, dynamic>>> readChurchDoc() =>
          ChurchRepository.churchDoc(effectiveChurchId).get();
      igSnap = kIsWeb
          ? await FirestoreWebGuard.runWithWebRecovery(
              readChurchDoc,
              maxAttempts: 4,
            ).timeout(PanelResilientLoad.queryCap)
          : await readChurchDoc();
      final id = igSnap.data() ?? {};
      churchSlug = _slugFromTenantData(id);
      churchNome = (id['name'] ?? id['nome'] ?? '').toString();
      if (churchSlug.isEmpty) {
        churchSlug = TenantResolverService.knownPublicSlugForChurchDocId(
          effectiveChurchId,
        );
      }
      if (churchNome.trim().isEmpty || churchSlug.isEmpty) {
        try {
          final panelSite =
              await PanelPublicSiteSnapshotService.readOnce(effectiveChurchId)
                  .timeout(const Duration(seconds: 2));
          if (churchSlug.isEmpty) {
            churchSlug = panelSite.churchSlug.trim();
          }
          if (churchNome.trim().isEmpty) {
            churchNome = panelSite.churchName.trim();
          }
        } catch (_) {}
      }
      if (churchSlug.isEmpty) {
        churchSlug = TenantResolverService.knownPublicSlugForChurchDocId(
          effectiveChurchId,
        );
      }
      if (churchNome.trim().isEmpty || churchSlug.isEmpty) {
        try {
          final loaded = await ChurchRepository.loadByChurchId(
            effectiveChurchId,
            seedTenantId: resolved,
          );
          if (loaded.data.isNotEmpty) {
            if (churchSlug.isEmpty) {
              churchSlug = _slugFromTenantData(loaded.data);
            }
            if (churchNome.trim().isEmpty) {
              churchNome =
                  (loaded.data['name'] ?? loaded.data['nome'] ?? '').toString();
            }
          }
        } catch (e, st) {
          debugPrint('Dashboard _loadStreams loadByChurchId fallback: $e\n$st');
        }
      }
      if (churchSlug.isEmpty) {
        try {
          churchSlug = await TenantResolverService.resolveChurchPublicSlug(
            effectiveChurchId,
          );
        } catch (e, st) {
          debugPrint('Dashboard _loadStreams resolveChurchPublicSlug: $e\n$st');
        }
      }
      _corpoAdminRoles = ChurchCorpoAdminRoles.configuredRolesFromTenant(id);
    } catch (e, st) {
      debugPrint('Dashboard _loadStreams churchDoc fallback: $e\n$st');
      effectiveChurchId = ChurchRepository.churchId(resolved).isNotEmpty
          ? ChurchRepository.churchId(resolved)
          : resolved;
    }
    if (!mounted) return;
    unawaited(_attachPanelFeedStreams(resolved));
    final results = await IndependentFutures.pair(
      PanelDashboardSnapshotService.readOnce(resolved),
      ChurchDashboardCurrentService.readOnce(resolved),
    );
    if (!mounted) return;
    unawaited(
      PanelPreheatCoordinator.preheatOnce(tenantIdHint: resolved),
    );
    final igSnapData = igSnap?.data();
    YahwehPerformanceMonitor.markScreenReady('igreja_dashboard');
    final skipHeavyMemberStream = _dashboardMainCache?.hasData == true;
    setState(() {
      _effectiveTenantId = resolved;
      _churchSlug = churchSlug;
      _churchNome = churchNome;
      if (results.$1 != null) _panelCache = results.$1!;
      if (results.$2 != null) _dashboardKpis = results.$2!;
      if (skipHeavyMemberStream) {
        _heavyDashboardStreamsScheduled = true;
        _membersStream = null;
        _deptStream = _createDepartmentsOneShotStream(effectiveChurchId);
      } else {
        _attachHeavyDashboardStreamsInline(effectiveChurchId);
      }
    });
    final panelSnap = results.$1;
    if (panelSnap != null) {
      unawaited(
        ChurchGalleryPhotoWarmup.warmBytesForPanel(
          tenantId: resolved,
          panel: panelSnap,
        ),
      );
    }
    unawaited(() async {
      final prefetchRaw = await PanelMediaPrefetchService.readOnce(resolved);
      if (!mounted) return;
      await PanelMediaPrefetchService.applyToUrlCaches(
        resolved,
        raw: prefetchRaw,
        tenantData: igSnapData,
      );
      if (prefetchRaw != null && prefetchRaw.isNotEmpty) {
        await ChurchGalleryPhotoWarmup.warmBytesFromMediaPrefetch(
          resolved,
          prefetchRaw,
        );
      }
    }());
    if (panelSnap != null &&
        panelSnap.membersTotalCount == 0 &&
        panelSnap.pendingMembersCount == 0) {
      unawaited(() async {
        final warmed =
            await PanelDashboardSnapshotService.warmFromCallableIfStale(
          resolved,
        );
        if (!mounted) return;
        if (warmed.membersTotalCount > 0 ||
            warmed.isFreshForInstantPanel) {
          setState(() => _panelCache = warmed);
        }
      }());
    }
    _bindMembersDirectoryWatch(resolved);
    unawaited(_hydrateMembersDirectory(resolved));
    _prewarmPanelProgramacao(resolved);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ChurchGalleryPhotoWarmup.schedulePanelHome(
        context: context,
        tenantId: resolved,
        panel: _panelCache,
      );
      unawaited(scheduleYahwehPanelImageWarmup(
        context,
        resolved,
        resolvedTenantId: resolved,
        force: true,
      ));
    });
  }

  static const int _dashboardMembersLimit = 220;
  static const int _dashboardDepartmentsLimit = 80;

  /// Um snapshot ou merge de várias coleções `membros` (mesmo slug). Cancela ouvintes ao cancelar o stream.
  static Stream<QuerySnapshot<Map<String, dynamic>>> _createMembersSnapshotStream(
    List<String> allIds,
  ) {
    final db = firebaseDefaultFirestore;
    final lim = _dashboardMembersLimit;
    if (allIds.isEmpty) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.value(
        const MergedFirestoreQuerySnapshot([]),
      );
    }
    if (allIds.length == 1) {
      return _membersStreamForTenant(db, allIds.first, lim);
    }
    return Stream<QuerySnapshot<Map<String, dynamic>>>.multi((ctrl) {
      final latest = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emit() {
        final seen = <String>{};
        final merged = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in allIds) {
          for (final d in latest[id] ?? const []) {
            if (seen.add(d.id)) merged.add(d);
          }
        }
        ctrl.addSync(MergedFirestoreQuerySnapshot(merged));
      }

      for (final id in allIds) {
        subs.add(
          _membersStreamForTenant(db, id, lim).listen(
                (snap) {
                  latest[id] = snap.docs.toList();
                  emit();
                },
                onError: (Object _, StackTrace __) {
                  latest[id] = [];
                  emit();
                },
              ),
        );
      }

      ctrl.onCancel = () {
        for (final s in subs) {
          s.cancel();
        }
      };
    });
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> _membersStreamForTenant(
    FirebaseFirestore db,
    String tenantId,
    int lim,
  ) {
    return         ChurchUiCollections.membros(tenantId)
        .limit(lim)
        .watchSafe();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> _createDepartmentsOneShotStream(
    String churchId,
  ) {
    return FirestoreStreamUtils.oneShotQueryFromFuture(() async {
      final id = churchId.trim();
      if (id.isEmpty) return const MergedFirestoreQuerySnapshot([]);
      try {
        final snap = await ChurchTenantResilientReads.departamentos(
          id,
          limit: _dashboardDepartmentsLimit,
        ).timeout(
          const Duration(seconds: 6),
          onTimeout: () => const MergedFirestoreQuerySnapshot([]),
        );
        return MergedFirestoreQuerySnapshot(snap.docs);
      } catch (e, st) {
        debugPrint('Dashboard _createDepartmentsOneShotStream: $e\n$st');
        return const MergedFirestoreQuerySnapshot([]);
      }
    });
  }

  /// Mesmo padrão de [membros]: slug/alias pode ter vários docs em `igrejas/` — departamentos devem agregar todos.
  static Stream<QuerySnapshot<Map<String, dynamic>>> _createDepartmentsSnapshotStream(
    List<String> allIds,
  ) {
    final db = firebaseDefaultFirestore;
    if (allIds.isEmpty) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.value(
        const MergedFirestoreQuerySnapshot([]),
      );
    }
    if (allIds.length == 1) {
      return           ChurchUiCollections.departamentos(allIds.first)
          .limit(_dashboardDepartmentsLimit)
          .watchSafe();
    }
    return Stream<QuerySnapshot<Map<String, dynamic>>>.multi((ctrl) {
      final latest = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

      void emit() {
        final seen = <String>{};
        final merged = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        for (final id in allIds) {
          for (final d in latest[id] ?? const []) {
            if (seen.add(d.id)) merged.add(d);
          }
        }
        ctrl.addSync(MergedFirestoreQuerySnapshot(merged));
      }

      for (final id in allIds) {
        subs.add(
                        ChurchUiCollections.departamentos(id)
              .limit(_dashboardDepartmentsLimit)
              .watchSafe()
              .listen(
                (snap) {
                  latest[id] = snap.docs.toList();
                  emit();
                },
                onError: (Object _, StackTrace __) {
                  latest[id] = [];
                  emit();
                },
              ),
        );
      }

      ctrl.onCancel = () {
        for (final s in subs) {
          s.cancel();
        }
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final tenantReady =
        ChurchPanelTenant.resolve(widget.tenantId).trim().isNotEmpty;
    if (!tenantReady) {
      return SafeArea(
        child: Container(
          color: ThemeCleanPremium.surfaceVariant,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: YahwehSkeletonLoading.dashboardHome(),
          ),
        ),
      );
    }
    final membersStream = _membersStream;
    if (membersStream == null) {
      final mergedSnap = _resolvedMembersAsyncSnap(
        _syntheticMembersSnapFromDirectory(),
      );
      return SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow =
                constraints.maxWidth < ThemeCleanPremium.breakpointMobile;
            return _buildDashboardScroll(
              context: context,
              isNarrow: isNarrow,
              mergedSnap: mergedSnap,
            );
          },
        ),
      );
    }
    return SafeArea(child: LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < ThemeCleanPremium.breakpointMobile;
        return RefreshIndicator(
          onRefresh: _loadStreams,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: membersStream,
            builder: (context, membersResult) {
              final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> mergedSnap;
              if (membersResult.hasError) {
                mergedSnap = AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>.withError(
                  membersResult.connectionState,
                  membersResult.error ?? Object(),
                  membersResult.stackTrace ?? StackTrace.current,
                );
              } else {
                mergedSnap = _resolvedMembersAsyncSnap(
                  membersResult.hasData
                      ? AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>.withData(
                          membersResult.connectionState,
                          membersResult.data!,
                        )
                      : AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>.waiting(),
                );
              }
              return _buildDashboardScroll(
                context: context,
                isNarrow: isNarrow,
                mergedSnap: mergedSnap,
              );
            },
          ),
        );
      },
    ));
  }

  Widget _buildDashboardScroll({
    required BuildContext context,
    required bool isNarrow,
    required AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> mergedSnap,
  }) {
    final deptStream = _deptStream ??
        Stream<QuerySnapshot<Map<String, dynamic>>>.value(
          const MergedFirestoreQuerySnapshot([]),
        );
    return RefreshIndicator(
      onRefresh: _loadStreams,
      child: SingleChildScrollView(
                    controller: _panelScroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: ThemeCleanPremium.pagePadding(context).copyWith(
                        top: ThemeCleanPremium.spaceSm,
                      ),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StreamBuilder<PanelDashboardSnapshot>(
                          stream: PanelDashboardSnapshotService.watch(
                            _effectiveTenantId,
                          ),
                          initialData: _panelCache,
                          builder: (context, panelSnap) {
                            final panel =
                                panelSnap.data ?? const PanelDashboardSnapshot();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PanelHomeWelcomeBanner(
                                  churchName: _churchNome,
                                  subtitle:
                                      'Atalhos, links públicos e resumo ministerial',
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceMd),
                                PanelQuickShortcuts(
                                  onOpenAniversariantesAno:
                                      _openAniversariantesAnoPage,
                                  onOpenGaleriaEventos: () =>
                                      widget.onNavigateToShellModule(7),
                                  onOpenOrganograma: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => LiderancaPage(
                                          tenantId: _effectiveTenantId,
                                          role: widget.role,
                                          viewerCpfDigits: widget.cpf
                                              .replaceAll(RegExp(r'\D'), ''),
                                        ),
                                      ),
                                    );
                                  },
                                  onOpenPainelCorpoAdmin:
                                      _scrollToCorpoAdministrativo,
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceMd),
                                _LinksPublicosStrip(
                                  tenantId: _effectiveTenantId.isNotEmpty
                                      ? _effectiveTenantId
                                      : widget.tenantId,
                                  role: widget.role,
                                  churchSlug: _churchSlug,
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceMd),
                                PanelCollapsibleSection(
                                  sectionKey: 'aniversariantes',
                                  title: 'Aniversariantes',
                                  icon: Icons.cake_rounded,
                                  accent: const Color(0xFFDB2777),
                                  child: _AniversariantesCard(
                                  snap: mergedSnap,
                                  panelCache: panel,
                                  tenantId: _effectiveTenantId,
                                  role: widget.role,
                                  memberCpfDigits: widget.cpf
                                      .replaceAll(RegExp(r'\D'), ''),
                                  engagement: _engagementCtrl,
                                  onRetry: _loadStreams,
                                  ),
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceLg),
                                PastoralInboxHomeCard(
                                  tenantId: _effectiveTenantId,
                                  cpfDigits: widget.cpf
                                      .replaceAll(RegExp(r'\D'), ''),
                                  memberDocs:
                                      mergedSnap.data?.docs ?? const [],
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceLg),
                                PanelCollapsibleSection(
                                  sectionKey: 'lideres_departamento',
                                  title: 'Líderes de departamento',
                                  icon: Icons.leaderboard_rounded,
                                  accent: const Color(0xFF6366F1),
                                  child: ChurchPanelLeadershipCardSection(
                                    tenantId: _effectiveTenantId,
                                    role: widget.role,
                                    viewerCpfDigits: widget.cpf
                                        .replaceAll(RegExp(r'\D'), ''),
                                    section: ChurchPanelLeadershipSection
                                        .departmentLeaders,
                                    panelCache: panel,
                                    membersDirectory:
                                        _bestMembersDirectory(),
                                    onRetry: _loadStreams,
                                  ),
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceLg),
                                KeyedSubtree(
                                  key: _corpoAdminSectionKey,
                                  child: PanelCollapsibleSection(
                                    sectionKey: 'corpo_administrativo',
                                    title: 'Corpo administrativo',
                                    icon: Icons.groups_rounded,
                                    accent: const Color(0xFF10B981),
                                    child: ChurchPanelLeadershipCardSection(
                                      tenantId: _effectiveTenantId,
                                      role: widget.role,
                                      viewerCpfDigits: widget.cpf
                                          .replaceAll(RegExp(r'\D'), ''),
                                      section: ChurchPanelLeadershipSection
                                          .corpoAdmin,
                                      panelCache: panel,
                                      membersDirectory:
                                          _bestMembersDirectory(),
                                      corpoAdminRoles: _corpoAdminRoles,
                                      onRetry: _loadStreams,
                                    ),
                                  ),
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceLg),
                                _DestaqueEventosEspeciaisPainel(
                                  tenantId: _effectiveTenantId,
                                  role: widget.role,
                                  churchSlug: _churchSlug,
                                  nomeIgreja: _churchNome,
                                  stream: _noticiasPainelStream ??
                                      _emptyQueryStream(),
                                  onRetryStream: _loadStreams,
                                ),
                                const SizedBox(
                                    height: ThemeCleanPremium.spaceLg),
                                _DestaqueAvisos(
                                  tenantId: _effectiveTenantId,
                                  role: widget.role,
                                  churchSlug: _churchSlug,
                                  nomeIgreja: _churchNome,
                                  stream:
                                      _avisosStream ?? _emptyQueryStream(),
                                  panelCache: panel,
                                  onRetryStream: _loadStreams,
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                        if (!AppPermissions.isRestrictedMember(widget.role)) ...[
                          ChurchMinistryHealthPanel(
                            key: _ministryHealthKey,
                            tenantId: _effectiveTenantId,
                            role: widget.role,
                            memberDocs: mergedSnap.data?.docs ?? const [],
                            canViewFinance: _dashCanFinance,
                            financePeriodRange: _dashCanFinance
                                ? _resolvedDashFinanceRange
                                : ChurchDashboardFinancePeriod.resolve(
                                    preset:
                                        ChurchDashboardFinancePreset.currentMonth,
                                  ),
                            financePeriodPreset: _dashCanFinance
                                ? _dashFinancePreset
                                : ChurchDashboardFinancePreset.currentMonth,
                            financeStream: null,
                            deferFinanceBlock: _dashCanFinance,
                            onDeferredFinanceReady: () {
                              if (mounted) setState(() {});
                            },
                            onNavigateToMembers: widget.onNavigateToMembers,
                            onRefreshDashboard: _loadStreams,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                        ],
                        if (ChurchRolePermissions.shellAllowsNavIndex(
                          widget.role,
                          kChurchShellIndexMySchedules,
                          memberCanViewFinance: widget.podeVerFinanceiro,
                          memberCanViewPatrimonio: widget.podeVerPatrimonio,
                          permissions: widget.permissions,
                        )) ...[
                          _DashboardLiderOnboardingBanner(
                            role: widget.role,
                            podeVerFinanceiro: widget.podeVerFinanceiro,
                            podeVerPatrimonio: widget.podeVerPatrimonio,
                            permissions: widget.permissions,
                            onNavigateToShellModule: widget.onNavigateToShellModule,
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          _DashboardVoluntariadoAtalhoCard(
                            tenantId: _effectiveTenantId,
                            cpf: widget.cpf,
                            role: widget.role,
                            podeVerFinanceiro: widget.podeVerFinanceiro,
                            podeVerPatrimonio: widget.podeVerPatrimonio,
                            permissions: widget.permissions,
                            onOpenMinhaEscala: () => widget.onNavigateToShellModule(
                              kChurchShellIndexMySchedules,
                            ),
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceLg),
                        ],
                        _DashboardInstitutionalVideoStrip(tenantId: _effectiveTenantId),
                        const SizedBox(height: ThemeCleanPremium.spaceSm),
                        _ProgramacaoDiasCard(tenantId: _effectiveTenantId, role: widget.role),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                        _StatsCards(
                          snap: mergedSnap,
                          tenantId: _effectiveTenantId,
                          role: widget.role,
                          cachedTotalMembers: _effectiveCachedMemberTotal(),
                        ),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                        _GraficosMembrosPizza(snap: mergedSnap, isNarrow: isNarrow),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                        _TarefasPendentes(
                            tenantId: _effectiveTenantId,
                            role: widget.role,
                            permissions: widget.permissions,
                            initialPanelCache: _panelCache),
                        const SizedBox(height: ThemeCleanPremium.spaceXl),
                        SizedBox(
                          width: isNarrow ? double.infinity : 380,
                          child: _GraficoMembros(snap: mergedSnap),
                        ),
                        if (_dashCanFinance) ...[
                          const SizedBox(height: ThemeCleanPremium.spaceXl),
                          _DashboardFinancePeriodStrip(
                            resolvedRange: _resolvedDashFinanceRange,
                            preset: _dashFinancePreset,
                            isNarrow: isNarrow,
                            onSelect: (p) {
                              unawaited(_onDashFinancePresetTap(p));
                            },
                          ),
                          const SizedBox(height: ThemeCleanPremium.spaceMd),
                          if (!AppPermissions.isRestrictedMember(widget.role))
                            Builder(
                              builder: (context) {
                                final extra = _ministryHealthKey.currentState
                                    ?.buildDeferredFinanceSection(context);
                                if (extra == null) {
                                  return const SizedBox.shrink();
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    extra,
                                    SizedBox(
                                        height:
                                            ThemeCleanPremium.spaceLg),
                                  ],
                                );
                              },
                            ),
                          if (_dashCanFinance) ...[
                            SizedBox(
                              width: isNarrow ? double.infinity : double.infinity,
                              child: DashboardFinanceHub(
                                tenantId: _effectiveTenantId,
                                range: _resolvedDashFinanceRange,
                                preset: _dashFinancePreset,
                                role: widget.role,
                                cpf: widget.cpf,
                                podeVerFinanceiro: widget.podeVerFinanceiro,
                                permissions: widget.permissions,
                                financeRefreshTick: _financeDashTick,
                                isNarrow: isNarrow,
                              ),
                            ),
                            const SizedBox(height: ThemeCleanPremium.spaceLg),
                            SizedBox(
                              width: isNarrow ? double.infinity : 380,
                              child: _PainelDespesasDashboard(
                                tenantId: _effectiveTenantId,
                                range: _resolvedDashFinanceRange,
                                preset: _dashFinancePreset,
                                role: widget.role,
                                cpf: widget.cpf,
                                podeVerFinanceiro: widget.podeVerFinanceiro,
                                permissions: widget.permissions,
                                isNarrow: isNarrow,
                                financeRefreshTick: _financeDashTick,
                              ),
                            ),
                          ],
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// Botão com animação de scale no toque (feedback tátil).
class _TapScaleTile extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TapScaleTile({required this.child, required this.onTap});

  @override
  State<_TapScaleTile> createState() => _TapScaleTileState();
}

class _TapScaleTileState extends State<_TapScaleTile> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) => Transform.scale(
          scale: _scale.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Skeleton com efeito shimmer (carregamento moderno).
class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _SkeletonBox({this.width = double.infinity, this.height = 80, this.borderRadius = 12});

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 0,
              maxWidth: widget.width * 3,
              child: Transform.translate(
                offset: Offset(widget.width * _animation.value, 0),
                child: Container(
                  width: widget.width * 0.6,
                  height: widget.height,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.4),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Set<(int, int)> _anivWeekMdSet(DateTime now) {
  final set = <(int, int)>{};
  for (var i = 0; i < 7; i++) {
    final d = now.add(Duration(days: i));
    set.add((d.month, d.day));
  }
  return set;
}

String _anivNomeCompleto(Map<String, dynamic> d) =>
    (d['NOME_COMPLETO'] ?? d['nome'] ?? d['name'] ?? '').toString();

String _anivPrimeiroNome(Map<String, dynamic> d) {
  final full = _anivNomeCompleto(d).trim();
  if (full.isEmpty) return '';
  return full.split(RegExp(r'\s+')).first;
}

String? _anivFotoUrl(Map<String, dynamic> d) {
  final s = imageUrlFromMap(d);
  return s.isNotEmpty ? s : null;
}

Color _anivAvatarColor(Map<String, dynamic> d) =>
    avatarColorForMember(d, hasPhoto: _anivFotoUrl(d) != null) ??
    Colors.grey.shade600;

/// Decode proporcional à tela — fotos nítidas sem exagerar na memória.
int _anivMemCachePx(BuildContext context, double logicalDiameter) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return (logicalDiameter * dpr).round().clamp(120, 360);
}

String _anivDiaLabel(DateTime? dt, {required bool isToday}) {
  if (dt == null) return '';
  if (isToday) return 'Hoje';
  const dias = ['dom', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb'];
  final w = dias[dt.weekday % 7];
  return '$w ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
}

String _anivPhoneDigits(Map<String, dynamic> d) {
  for (final k in [
    'whatsapp',
    'WHATSAPP',
    'whatsappIgreja',
    'TELEFONES',
    'telefones',
    'celular',
    'CELULAR',
    'telefone',
    'TELEFONE',
    'fone',
    'phone',
  ]) {
    final s = (d[k] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (s.length >= 10) return s;
  }
  for (final e in d.entries) {
    final key = e.key.toString().toLowerCase();
    if (!key.contains('tel') &&
        !key.contains('fone') &&
        !key.contains('zap') &&
        !key.contains('whats')) {
      continue;
    }
    final s = (e.value ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    if (s.length >= 10) return s;
  }
  return '';
}

String _anivEmail(Map<String, dynamic> d) =>
    (d['EMAIL'] ?? d['email'] ?? '').toString().trim();

String _mesAniversarioPt(int month) {
  const meses = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];
  if (month < 1 || month > 12) return '';
  return meses[month - 1];
}

/// Bottom sheet premium: foto grande + dados do aniversariante.
void _openAniversarianteDetalheSheet(
  BuildContext context, {
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  required String tenantId,
  required String memberRole,
  required String memberCpfDigits,
  required bool isToday,
}) {
  _openAniversarianteDetalheSheetCore(
    context,
    memberDocId: doc.id,
    data: doc.data(),
    tenantId: tenantId,
    memberRole: memberRole,
    memberCpfDigits: memberCpfDigits,
    isToday: isToday,
  );
}

void _openAniversarianteDetalheSheetCore(
  BuildContext context, {
  required String memberDocId,
  required Map<String, dynamic> data,
  required String tenantId,
  required String memberRole,
  required String memberCpfDigits,
  required bool isToday,
}) {
  final dt = birthDateFromMemberData(data);
  final cpf = (data['CPF'] ?? data['cpf'] ?? '')
      .toString()
      .replaceAll(RegExp(r'[^0-9]'), '');
  final nomeCompleto = _anivNomeCompleto(data).trim();
  final titulo = nomeCompleto.isEmpty ? 'Aniversariante' : nomeCompleto;
  final primeiro = _anivPrimeiroNome(data);
  final fone = _anivPhoneDigits(data);
  final email = _anivEmail(data);
  final cargo = (data['CARGO'] ?? data['FUNCAO'] ?? data['role'] ?? '')
      .toString()
      .trim();
  final letterFallback = Container(
    color: _anivAvatarColor(data),
    alignment: Alignment.center,
    child: Text(
      primeiro.isNotEmpty ? primeiro[0].toUpperCase() : '?',
      style: const TextStyle(
        fontSize: 40,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.4),
    builder: (ctx) {
      final bottom = MediaQuery.viewPaddingOf(ctx).bottom;
      final bigCache = _anivMemCachePx(ctx, 112);
      final bigPhoto = SafeMemberProfilePhoto(
        imageUrl: _anivFotoUrl(data),
        tenantId: tenantId,
        memberId: memberDocId,
        cpfDigits: cpf.length >= 9 ? cpf : null,
        authUid: _dashboardMemberAuthUid(data),
        nomeCompleto: nomeCompleto.isNotEmpty ? nomeCompleto : null,
        memberFirestoreHint: data,
        imageCacheRevision: memberPhotoDisplayCacheRevision(data) ?? 0,
        width: 112,
        height: 112,
        circular: true,
        fit: BoxFit.cover,
        memCacheWidth: bigCache,
        memCacheHeight: bigCache,
        placeholder: letterFallback,
        errorChild: letterFallback,
      );
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _StoryRingBirthdayAvatar(
                  radius: 58,
                  isToday: isToday,
                  child: bigPhoto,
                ),
                const SizedBox(height: 18),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (dt != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isToday
                              ? const Color(0xFFFDF2F8)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isToday
                                ? const Color(0xFFFBCFE8)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cake_rounded,
                              size: 18,
                              color: isToday
                                  ? const Color(0xFFDB2777)
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isToday
                                  ? 'Aniversário hoje'
                                  : '${dt.day} de ${_mesAniversarioPt(dt.month)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: isToday
                                    ? const Color(0xFF9D174D)
                                    : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (cargo.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    cargo,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _AnivDetalheLinha(
                    icon: Icons.mail_outline_rounded,
                    texto: email,
                  ),
                ],
                if (fone.length >= 10) ...[
                  const SizedBox(height: 10),
                  _AnivDetalheLinha(
                    icon: Icons.phone_iphone_rounded,
                    texto: fone,
                  ),
                ],
                const SizedBox(height: 28),
                YahwehSuperPremiumActionButton.chat(
                  label: 'Parabenizar no chat da igreja',
                  onPressed: () => ChurchBirthdayParabenizar.openChatUnawaited(
                    context: ctx,
                    tenantId: tenantId,
                    memberRole: memberRole,
                    memberCpfDigits: memberCpfDigits,
                    memberData: data,
                    displayName: titulo,
                    primeiroNome: primeiro,
                    memberDocId: memberDocId,
                    popSheetBeforeNavigate: true,
                  ),
                ),
                const SizedBox(height: 10),
                YahwehSuperPremiumActionButton.whatsapp(
                  label: 'Parabenizar no WhatsApp',
                  onPressed: () {
                    Navigator.pop(ctx);
                    YahwehWhatsAppService.openBirthdayWish(
                      context,
                      firstName: primeiro,
                      phoneDigits: fone,
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      double.infinity,
                      ThemeCleanPremium.minTouchTarget,
                    ),
                  ),
                  child: Text(
                    'Fechar',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _AnivDetalheLinha extends StatelessWidget {
  final IconData icon;
  final String texto;

  const _AnivDetalheLinha({required this.icon, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              texto,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar com anel em gradiente (estilo Stories premium) + selo de bolo no aniversário do dia.
class _StoryRingBirthdayAvatar extends StatelessWidget {
  final double radius;
  final Widget child;
  final bool isToday;

  const _StoryRingBirthdayAvatar({
    required this.radius,
    required this.child,
    this.isToday = false,
  });

  @override
  Widget build(BuildContext context) {
    const ringColors = [
      Color(0xFF38BDF8),
      Color(0xFFF97316),
      Color(0xFFEC4899),
      Color(0xFF8B5CF6),
    ];
    const ringColorsToday = [
      Color(0xFFFBBF24),
      Color(0xFFF97316),
      Color(0xFFEC4899),
      Color(0xFFA855F7),
    ];
    final ring = 3.5;
    final glow = isToday ? 10.0 : 0.0;
    return Container(
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: isToday ? ringColorsToday : ringColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: const Color(0xFFEC4899).withValues(alpha: 0.42),
                  blurRadius: glow,
                  spreadRadius: 0.5,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.07),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
          if (isToday)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFCE7F3), width: 1.5),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: const Text('ðŸŽ‚', style: TextStyle(fontSize: 15)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Lembrete: push diário às 8h (Brasília) no tópico `igreja_{tenantId}` — [dailyBirthdayTopicPush].
class _AniversariantesPushInfoBanner extends StatelessWidget {
  final int count;
  final List<String> previewNames;

  const _AniversariantesPushInfoBanner({
    required this.count,
    required this.previewNames,
  });

  @override
  Widget build(BuildContext context) {
    final parts = previewNames.where((s) => s.isNotEmpty).take(4).toList();
    final preview = parts.join(', ');
    final more = count > parts.length ? '…' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFFFDBA74).withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withValues(alpha: 0.14),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              color: Colors.orange.shade800,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count == 1
                      ? 'Aniversariante de hoje'
                      : '$count aniversariantes hoje',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Color(0xFF9A3412),
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quem usa o app nesta igreja recebe um aviso por volta das 8h '
                  '(horário de Brasília). '
                  '${preview.isNotEmpty ? 'Inclui: $preview$more.' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.38,
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Falha ao ler Firestore no painel — permite religar streams sem sair da tela.
class _DashboardPanelLoadError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _DashboardPanelLoadError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.cloud_off_rounded,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.88),
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: () => unawaited(onRetry()),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar novamente'),
                style: FilledButton.styleFrom(
                  foregroundColor: ThemeCleanPremium.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Aniversariantes sem `_panel_cache` — queries indexadas (`birthMonth`/`birthDay`), sem scan da coleção.
class _AniversariantesBirthdayIndexedLoader extends StatefulWidget {
  const _AniversariantesBirthdayIndexedLoader({
    required this.tenantId,
    required this.engagement,
    required this.onRetry,
    required this.builder,
  });

  final String tenantId;
  final ChurchDashboardEngagementController engagement;
  final Future<void> Function() onRetry;
  final Widget Function(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs)
      builder;

  @override
  State<_AniversariantesBirthdayIndexedLoader> createState() =>
      _AniversariantesBirthdayIndexedLoaderState();
}

class _AniversariantesBirthdayIndexedLoaderState
    extends State<_AniversariantesBirthdayIndexedLoader> {
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _future;
  int _loadedTab = -1;

  @override
  void initState() {
    super.initState();
    widget.engagement.addListener(_onTabChanged);
    _reloadForTab(widget.engagement.birthdayFilterTab);
  }

  @override
  void dispose() {
    widget.engagement.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    _reloadForTab(widget.engagement.birthdayFilterTab);
  }

  void _reloadForTab(int tab) {
    if (_loadedTab == tab && _future != null) return;
    _loadedTab = tab;
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      setState(() => _future = Future.value(const []));
      return;
    }
    setState(() {
      _future = switch (tab) {
        0 => ChurchDashboardPanelController.birthdaysToday(tid),
        1 => ChurchDashboardPanelController.birthdaysThisWeek(tid),
        _ => ChurchDashboardPanelController.birthdaysThisMonth(tid),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.engagement,
      builder: (context, _) {
        final future = _future;
        if (future == null) {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: YahwehPremiumFeedShimmer.birthdayStoriesSkeleton(
              listHeight: _AniversariantesCard.kRowHeight,
              avatarRingRadius: _AniversariantesCard.kAvatarRadius,
            ),
          );
        }
        return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return Padding(
                padding: const EdgeInsets.all(4),
                child: YahwehPremiumFeedShimmer.birthdayStoriesSkeleton(
                  listHeight: _AniversariantesCard.kRowHeight,
                  avatarRingRadius: _AniversariantesCard.kAvatarRadius,
                ),
              );
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: _DashboardPanelLoadError(
                  message:
                      'Não foi possível carregar aniversariantes. Verifique a conexão ou toque abaixo para recarregar.',
                  onRetry: widget.onRetry,
                ),
              );
            }
            return widget.builder(snap.data ?? const []);
          },
        );
      },
    );
  }
}

/// Card Aniversariantes: filtros Hoje / Semana / Mês + fileira estilo Stories + Parabenizar (chat / WhatsApp).
class _AniversariantesCard extends StatelessWidget {
  /// Raio do círculo interno da foto (anel +3.5px — visual ~93px).
  static const double kAvatarRadius = 43;
  static const double kRowHeight = 232;
  static const double kColWidth = 116;

  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap;
  final PanelDashboardSnapshot panelCache;
  final String tenantId;
  final String role;
  final String memberCpfDigits;
  final ChurchDashboardEngagementController engagement;
  final Future<void> Function() onRetry;

  const _AniversariantesCard({
    required this.snap,
    required this.panelCache,
    required this.tenantId,
    required this.role,
    required this.memberCpfDigits,
    required this.engagement,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engagement,
      builder: (context, _) => _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      if (panelCache.hasBirthdayData) {
        return _premiumContainer(child: _buildContentFromCache(context));
      }
      return _premiumContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ChurchWisdomBirthdayPanelHeader(),
            const SizedBox(height: 14),
            YahwehPremiumFeedShimmer.segmentedBarSkeleton(height: 50),
            const SizedBox(height: 16),
            YahwehPremiumFeedShimmer.birthdayStoriesSkeleton(
              listHeight: kRowHeight,
              avatarRingRadius: kAvatarRadius,
            ),
          ],
        ),
      );
    }
    if (snap.hasError) {
      return _premiumContainer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _DashboardPanelLoadError(
            message:
                'Não foi possível carregar aniversariantes. Verifique a conexão ou toque abaixo para recarregar.',
            onRetry: onRetry,
          ),
        ),
      );
    }
    if (!snap.hasData) {
      if (panelCache.hasBirthdayData) {
        return _premiumContainer(child: _buildContentFromCache(context));
      }
      return const SizedBox.shrink();
    }
    if (panelCache.hasBirthdayData) {
      return _premiumContainer(child: _buildContentFromCache(context));
    }
    return _premiumContainer(
      child: _AniversariantesBirthdayIndexedLoader(
        tenantId: tenantId,
        engagement: engagement,
        onRetry: onRetry,
        builder: (docs) => _buildContentFromDocs(context, docs),
      ),
    );
  }

  DateTime? _birthDateFromLite(PanelHomeMemberLite m) {
    final mo = m.birthMonth;
    final da = m.birthDay;
    if (mo == null || da == null || mo < 1 || mo > 12 || da < 1 || da > 31) {
      return null;
    }
    final y = DateTime.now().year;
    return DateTime(y, mo, da);
  }

  Widget _buildContentFromCache(BuildContext context) {
    final now = DateTime.now();
    final hoje = panelCache.birthdaysToday;
    final semana = panelCache.birthdaysWeek;
    final mes = panelCache.birthdaysMonth;
    final tab = engagement.birthdayFilterTab;
    List<PanelHomeMemberLite> lista;
    String emptyMsg;
    if (tab == 0) {
      lista = hoje;
      emptyMsg = 'Nenhum aniversariante hoje.';
    } else if (tab == 1) {
      lista = semana;
      emptyMsg = 'Nenhum aniversariante nesta semana.';
    } else {
      lista = mes;
      emptyMsg = 'Nenhum aniversariante neste mês.';
    }

    final preloadUrls = lista
        .map((m) => m.photoUrl ?? '')
        .where((u) => u.trim().isNotEmpty)
        .take(24)
        .toList();
    ChurchGalleryPhotoWarmup.schedule(
      context: context,
      tenantId: tenantId,
      members: lista.map((lite) {
        final data = lite.toMemberDataMap();
        return ChurchGalleryMemberPhotoRef(
          memberDocId: lite.memberDocId,
          memberData: data,
          cpfDigits: lite.cpfDigits,
          authUid: lite.authUid ?? _dashboardMemberAuthUid(data),
        );
      }),
      maxMembers: 24,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      preloadNetworkImages(context, preloadUrls, maxItems: 16);
    });

    final cachePx = _anivMemCachePx(context, kAvatarRadius * 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ChurchWisdomBirthdayPanelHeader(),
        const SizedBox(height: 14),
        if (hoje.isNotEmpty)
          _AniversariantesPushInfoBanner(
            count: hoje.length,
            previewNames: hoje
                .map((m) => _anivPrimeiroNome(m.toMemberDataMap()))
                .toList(),
          ),
        ChurchWisdomBirthdayFilterChips(
          selectedTab: tab,
          onSelected: engagement.setBirthdayTab,
        ),
        const SizedBox(height: 18),
        if (lista.isEmpty)
          ChurchWisdomBirthdayEmptyRow(message: emptyMsg)
        else
          SizedBox(
            height: kRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final lite = lista[i];
                final data = lite.toMemberDataMap();
                final dt = _birthDateFromLite(lite);
                final cpf = (lite.cpfDigits ?? '')
                    .replaceAll(RegExp(r'[^0-9]'), '');
                final primeiro = _anivPrimeiroNome(data);
                final isToday = dt != null &&
                    dt.month == now.month &&
                    dt.day == now.day;
                final letterFallback = Container(
                  color: _anivAvatarColor(data),
                  alignment: Alignment.center,
                  child: Text(
                    primeiro.isNotEmpty ? primeiro[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                );
                final inner = SafeMemberProfilePhoto(
                  imageUrl: lite.photoUrl ?? _anivFotoUrl(data),
                  tenantId: tenantId,
                  memberId: lite.memberDocId,
                  cpfDigits: cpf.length >= 9 ? cpf : null,
                  authUid: lite.authUid ?? _dashboardMemberAuthUid(data),
                  nomeCompleto: lite.displayName.trim().isEmpty
                      ? null
                      : lite.displayName.trim(),
                  memberFirestoreHint: data,
                  imageCacheRevision: memberPhotoDisplayCacheRevision(data) ?? 0,
                  width: kAvatarRadius * 2,
                  height: kAvatarRadius * 2,
                  circular: true,
                  fit: BoxFit.cover,
                  memCacheWidth: cachePx,
                  memCacheHeight: cachePx,
                  preferListThumbnail: true,
                  placeholder: letterFallback,
                  errorChild: letterFallback,
                );
                final fone = _anivPhoneDigits(data);
                return RepaintBoundary(
                  child: SizedBox(
                    width: kColWidth,
                    child: Column(
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _openAniversarianteDetalheSheetCore(
                              context,
                              memberDocId: lite.memberDocId,
                              data: data,
                              tenantId: tenantId,
                              memberRole: role,
                              memberCpfDigits: memberCpfDigits,
                              isToday: isToday,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            splashColor: ThemeCleanPremium.primary
                                .withValues(alpha: 0.12),
                            highlightColor: ThemeCleanPremium.primary
                                .withValues(alpha: 0.06),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                              child: Column(
                                children: [
                                  _StoryRingBirthdayAvatar(
                                    radius: kAvatarRadius,
                                    isToday: isToday,
                                    child: inner,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    primeiro.isNotEmpty ? primeiro : '?',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _anivDiaLabel(dt, isToday: isToday),
                                    maxLines: 1,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isToday
                                          ? const Color(0xFFDB2777)
                                          : const Color(0xFF64748B),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: YahwehSuperPremiumActionButton.chat(
                            compact: true,
                            label: 'Chat',
                            onPressed: () =>
                                ChurchBirthdayParabenizar.openChatUnawaited(
                              context: context,
                              tenantId: tenantId,
                              memberRole: role,
                              memberCpfDigits: memberCpfDigits,
                              memberData: data,
                              displayName: lite.displayName.trim().isEmpty
                                  ? primeiro
                                  : lite.displayName.trim(),
                              primeiroNome: primeiro,
                              memberDocId: lite.memberDocId,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: YahwehSuperPremiumActionButton.whatsapp(
                            compact: true,
                            label: 'WhatsApp',
                            onPressed: () => YahwehWhatsAppService.openBirthdayWish(
                              context,
                              firstName: primeiro,
                              phoneDigits: fone,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _premiumHeaderPlaceholder() => Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 18,
                  width: 160,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 220,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _premiumContainer({required Widget child}) {
    return ChurchWisdomBirthdayPanelShell(child: child);
  }

  Widget _buildContentFromDocs(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final preloadUrls = docs
        .map((d) => _anivFotoUrl(d.data()) ?? '')
        .where((u) => u.trim().isNotEmpty)
        .take(24)
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      preloadNetworkImages(context, preloadUrls, maxItems: 16);
    });

    final now = DateTime.now();
    final hojeMd = (now.month, now.day);
    final semanaSet = _anivWeekMdSet(now);

    final hoje = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final semanaExcHoje = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final mesAtual = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in docs) {
      final dt = birthDateFromMemberData(d.data());
      if (dt == null) continue;
      final key = (dt.month, dt.day);
      if (key == hojeMd) {
        hoje.add(d);
      } else if (semanaSet.contains(key)) {
        semanaExcHoje.add(d);
      }
      if (dt.month == now.month) {
        mesAtual.add(d);
      }
    }
    int ordMd(QueryDocumentSnapshot<Map<String, dynamic>> a,
        QueryDocumentSnapshot<Map<String, dynamic>> b) {
      final da = birthDateFromMemberData(a.data());
      final db = birthDateFromMemberData(b.data());
      if (da == null || db == null) return 0;
      return (da.day + da.month * 32).compareTo(db.day + db.month * 32);
    }

    semanaExcHoje.sort(ordMd);
    mesAtual.sort(ordMd);

    final tab = engagement.birthdayFilterTab;
    List<QueryDocumentSnapshot<Map<String, dynamic>>> lista;
    String emptyMsg;
    if (tab == 0) {
      lista = hoje;
      emptyMsg = 'Nenhum aniversariante hoje.';
    } else if (tab == 1) {
      lista = [...hoje, ...semanaExcHoje];
      emptyMsg = 'Nenhum aniversariante nesta semana.';
    } else {
      lista = mesAtual;
      emptyMsg = 'Nenhum aniversariante neste mês.';
    }

    final cachePx = _anivMemCachePx(context, kAvatarRadius * 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ChurchWisdomBirthdayPanelHeader(),
        const SizedBox(height: 14),
        if (hoje.isNotEmpty)
          _AniversariantesPushInfoBanner(
            count: hoje.length,
            previewNames:
                hoje.map((d) => _anivPrimeiroNome(d.data())).toList(),
          ),
        ChurchWisdomBirthdayFilterChips(
          selectedTab: tab,
          onSelected: engagement.setBirthdayTab,
        ),
        const SizedBox(height: 18),
        if (lista.isEmpty)
          ChurchWisdomBirthdayEmptyRow(message: emptyMsg)
        else
          SizedBox(
            height: kRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              itemCount: lista.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final d = lista[i];
                final data = d.data();
                final dt = birthDateFromMemberData(data);
                final cpf = (data['CPF'] ?? data['cpf'] ?? '')
                    .toString()
                    .replaceAll(RegExp(r'[^0-9]'), '');
                final primeiro = _anivPrimeiroNome(data);
                final isToday = dt != null &&
                    dt.month == now.month &&
                    dt.day == now.day;
                final letterFallback = Container(
                  color: _anivAvatarColor(data),
                  alignment: Alignment.center,
                  child: Text(
                    primeiro.isNotEmpty ? primeiro[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                );
                final inner = SafeMemberProfilePhoto(
                  imageUrl: _anivFotoUrl(data),
                  tenantId: tenantId,
                  memberId: d.id,
                  cpfDigits: cpf.length >= 9 ? cpf : null,
                  authUid: _dashboardMemberAuthUid(data),
                  nomeCompleto: _anivNomeCompleto(data).trim().isEmpty
                      ? null
                      : _anivNomeCompleto(data).trim(),
                  memberFirestoreHint: data,
                  imageCacheRevision: memberPhotoDisplayCacheRevision(data) ?? 0,
                  width: kAvatarRadius * 2,
                  height: kAvatarRadius * 2,
                  circular: true,
                  fit: BoxFit.cover,
                  memCacheWidth: cachePx,
                  memCacheHeight: cachePx,
                  preferListThumbnail: true,
                  placeholder: letterFallback,
                  errorChild: letterFallback,
                );
                final fone = _anivPhoneDigits(data);
                return RepaintBoundary(
                  child: SizedBox(
                  width: kColWidth,
                  child: Column(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openAniversarianteDetalheSheet(
                            context,
                            doc: d,
                            tenantId: tenantId,
                            memberRole: role,
                            memberCpfDigits: memberCpfDigits,
                            isToday: isToday,
                          ),
                          borderRadius: BorderRadius.circular(24),
                          splashColor: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                          highlightColor: ThemeCleanPremium.primary.withValues(alpha: 0.06),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                            child: Column(
                              children: [
                                _StoryRingBirthdayAvatar(
                                  radius: kAvatarRadius,
                                  isToday: isToday,
                                  child: inner,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  primeiro.isNotEmpty ? primeiro : '?',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.2,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _anivDiaLabel(dt, isToday: isToday),
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isToday
                                        ? const Color(0xFFDB2777)
                                        : const Color(0xFF64748B),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: YahwehSuperPremiumActionButton.chat(
                          compact: true,
                          label: 'Chat',
                          onPressed: () =>
                              ChurchBirthdayParabenizar.openChatUnawaited(
                            context: context,
                            tenantId: tenantId,
                            memberRole: role,
                            memberCpfDigits: memberCpfDigits,
                            memberData: data,
                            displayName: _anivNomeCompleto(data).trim().isEmpty
                                ? primeiro
                                : _anivNomeCompleto(data).trim(),
                            primeiroNome: primeiro,
                            memberDocId: d.id,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: double.infinity,
                        child: YahwehSuperPremiumActionButton.whatsapp(
                          compact: true,
                          label: 'WhatsApp',
                          onPressed: () => YahwehWhatsAppService.openBirthdayWish(
                            context,
                            firstName: primeiro,
                            phoneDigits: fone,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        Center(
          child: FilledButton.tonal(
            onPressed: () {
              Navigator.of(context).push(
                ThemeCleanPremium.fadeSlideRoute(
                  AniversariantesAnoPage(
                    tenantId: tenantId,
                    memberRole: role,
                    viewerCpfDigits: memberCpfDigits,
                  ),
                ),
              );
            },
            style: FilledButton.styleFrom(
              foregroundColor: ThemeCleanPremium.primary,
              backgroundColor: Colors.white.withValues(alpha: 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
                ),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_month_rounded,
                    size: 20, color: ThemeCleanPremium.primary),
                const SizedBox(width: 8),
                Text(
                  'Ver ano todo (mês a mês)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: ThemeCleanPremium.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Textura sutil no fundo do card de aniversariantes.
/// Vídeo institucional (Firestore: `institutionalVideoUrl` ou `institutionalVideoStoragePath`) — mesmo padrão EcoFire na web.
class _DashboardInstitutionalVideoStrip extends StatelessWidget {
  final String tenantId;

  const _DashboardInstitutionalVideoStrip({required this.tenantId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ChurchUiCollections.churchDoc(tenantId).watchSafe(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null || !mapHasInstitutionalVideo(data)) {
          return const SizedBox.shrink();
        }
        return PremiumInstitutionalVideoCard.fromChurchDoc(
          data,
          height: MediaQuery.sizeOf(context).width < ThemeCleanPremium.breakpointMobile ? 200 : 260,
          caption: 'VÍDEO INSTITUCIONAL',
          hintBelow: 'Toque para reproduzir. Na web: PiP, velocidade e download no menu do vídeo.',
          // Sem autoplay: libera CPU/rede para fotos (aniversariantes, líderes, destaques) no primeiro scroll.
          heroAutoplay: false,
        );
      },
    );
  }
}

/// Links do site público e cadastro público — exibidos no dashboard quando a igreja tem slug configurado.
/// O atalho «Cadastro da Igreja» só aparece se o cadastro raiz ainda não estiver concluído.
bool _isIgrejaCadastroConcluido(Map<String, dynamic>? data) {
  if (data == null || data.isEmpty) return false;
  if (data['registrationComplete'] == false) return false;
  if (data['registrationComplete'] == true) return true;
  return TenantResolverService.churchProfileRichnessScore(data) >=
      ChurchCadastroLoadService.kMinProfileScore;
}

class _LinksPublicosStrip extends StatefulWidget {
  final String tenantId;
  final String role;
  final String churchSlug;

  const _LinksPublicosStrip({
    required this.tenantId,
    required this.role,
    this.churchSlug = '',
  });

  @override
  State<_LinksPublicosStrip> createState() => _LinksPublicosStripState();
}

class _LinksPublicosStripState extends State<_LinksPublicosStrip> {
  String? _slug;
  bool _loading = false;
  bool _cadastroConcluido = true;

  String get _effectiveSlug {
    final fromParent = widget.churchSlug.trim();
    if (fromParent.isNotEmpty) return fromParent;
    final cached = (_slug ?? '').trim();
    if (cached.isNotEmpty) return cached;
    return _slugFromKnownMap() ?? '';
  }

  static String _slugFromData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return '';
    return (data['slug'] ?? data['slugId'] ?? data['alias'] ?? '')
        .toString()
        .trim();
  }

  String _resolveTenantHint() {
    final tid = widget.tenantId.trim();
    if (tid.isNotEmpty) return tid;
    final panel = ChurchContextService.panelChurchId('');
    if (panel.isNotEmpty) return panel;
    return ChurchContextService.currentChurchId ?? '';
  }

  String? _slugFromKnownMap([String? hint]) {
    final tid = (hint ?? _resolveTenantHint()).trim();
    if (tid.isEmpty) return null;
    final readId = ChurchRepository.churchId(tid);
    final known = TenantResolverService.knownPublicSlugForChurchDocId(
      readId.isNotEmpty ? readId : tid,
    );
    return known.isEmpty ? null : known;
  }

  @override
  void initState() {
    super.initState();
    final seed = widget.churchSlug.trim();
    if (seed.isNotEmpty) {
      _slug = seed;
      return;
    }
    final known = _slugFromKnownMap();
    if (known != null) {
      _slug = known;
      return;
    }
    _loading = true;
    unawaited(_loadSlug());
  }

  @override
  void didUpdateWidget(covariant _LinksPublicosStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seed = widget.churchSlug.trim();
    if (seed.isNotEmpty && seed != _slug) {
      setState(() {
        _slug = seed;
        _loading = false;
      });
      return;
    }
    if (_loading || _effectiveSlug.isEmpty) {
      final known = _slugFromKnownMap();
      if (known != null) {
        setState(() {
          _slug = known;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSlug() async {
    try {
      final tenantHint = _resolveTenantHint();
      final readId = ChurchRepository.churchId(tenantHint);
      final docKey = readId.isNotEmpty ? readId : tenantHint;

      var slug = TenantResolverService.knownPublicSlugForChurchDocId(docKey);
      Map<String, dynamic>? churchData;

      if (slug.isEmpty) {
        try {
          final panelSite = await PanelPublicSiteSnapshotService.readOnce(docKey)
              .timeout(const Duration(seconds: 2));
          slug = panelSite.churchSlug.trim();
        } catch (_) {}
      }

      if (slug.isNotEmpty) {
        if (readId.isNotEmpty) {
          try {
            final snap = await ChurchRepository.churchDoc(readId).get(
              const GetOptions(source: Source.cache),
            );
            churchData = snap.data();
          } catch (_) {}
        }
        if (mounted) {
          setState(() {
            _slug = slug;
            _cadastroConcluido = _isIgrejaCadastroConcluido(churchData);
            _loading = false;
          });
        }
        return;
      }

      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady()
            .timeout(const Duration(seconds: 2), onTimeout: () {})
            .catchError((_) {});
      }
      if (readId.isNotEmpty) {
        try {
          final loaded = await ChurchRepository.loadByChurchId(
            readId,
            seedTenantId: widget.tenantId,
          );
          churchData = loaded.data;
          slug = _slugFromData(loaded.data);
        } catch (e, st) {
          debugPrint('Dashboard _loadSlug loadByChurchId: $e\n$st');
        }
      }
      if (slug.isEmpty) {
        slug = await TenantResolverService.resolveChurchPublicSlug(
          readId.isNotEmpty ? readId : widget.tenantId,
        ).timeout(const Duration(seconds: 6), onTimeout: () => '');
      }
      if (churchData == null && readId.isNotEmpty) {
        try {
          final snap = await ChurchRepository.churchDoc(readId).get(
            const GetOptions(source: Source.cache),
          );
          churchData = snap.data();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _slug = slug.isEmpty ? null : slug;
          _cadastroConcluido = _isIgrejaCadastroConcluido(churchData);
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('Dashboard _loadSlug: $e\n$st');
      if (mounted) {
        final fallback = TenantResolverService.knownPublicSlugForChurchDocId(
          ChurchRepository.churchId(_resolveTenantHint()),
        );
        setState(() {
          _slug = fallback.isNotEmpty
              ? fallback
              : (widget.churchSlug.trim().isNotEmpty
                  ? widget.churchSlug.trim()
                  : null);
          _cadastroConcluido = true;
          _loading = false;
        });
      }
    }
  }

  void _openSitePublico() {
    final slug = _effectiveSlug;
    if (slug.isEmpty || !mounted) return;
    PublicMemberSignupNavigation.openChurchPublicSite(context, slug: slug);
  }

  void _openCadastroPublico() {
    final slug = _effectiveSlug;
    if (slug.isEmpty || !mounted) return;
    PublicMemberSignupNavigation.open(context, slug: slug, tenantId: widget.tenantId);
  }

  @override
  Widget build(BuildContext context) {
    final slug = _effectiveSlug;
    if (slug.isEmpty && _loading) {
      return const ChurchPublicLinksSkeleton();
    }

    if (slug.isEmpty) {
      return _LinksPublicosSetupCard(
        cadastroConcluido: _cadastroConcluido,
        tenantId: widget.tenantId,
        role: widget.role,
        onRefresh: _loadSlug,
      );
    }

    return ChurchPublicLinksCard(
      slug: slug,
      onOpenSite: _openSitePublico,
      onOpenCadastro: _openCadastroPublico,
    );
  }
}

class _LinksPublicosSetupCard extends StatelessWidget {
  const _LinksPublicosSetupCard({
    required this.cadastroConcluido,
    required this.tenantId,
    required this.role,
    required this.onRefresh,
  });

  final bool cadastroConcluido;
  final String tenantId;
  final String role;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF7ED), Color(0xFFFFFBEB)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                cadastroConcluido
                    ? Icons.refresh_rounded
                    : Icons.link_off_rounded,
                color: const Color(0xFFEA580C),
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cadastroConcluido
                      ? 'Não foi possível carregar os links públicos agora. Toque em Atualizar — o cadastro da igreja já está concluído.'
                      : 'Configure o slug no Cadastro da Igreja para exibir os links do site e do cadastro de membros.',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9A3412),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onRefresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Atualizar'),
                ),
              ),
              if (!cadastroConcluido) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => IgrejaCadastroPage(
                          tenantId: tenantId,
                          role: role,
                        ),
                      ),
                    ).then((_) => onRefresh()),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    child: const Text('Configurar'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// UID Firebase do membro (foto no Storage em `membros/{authUid}/…` quando o doc é CPF).
String? _dashboardMemberAuthUid(Map<String, dynamic>? data) {
  if (data == null) return null;
  for (final k in ['authUid', 'uid', 'userId', 'firebaseUid', 'USER_ID']) {
    final v = (data[k] ?? '').toString().trim();
    if (v.length >= 8) return v;
  }
  return null;
}

/// Stats: Membros, Homens, Mulheres, Crianças — recebe snapshot compartilhado; ao toque abre lista filtrada.
class _StatsCards extends StatelessWidget {
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap;
  final String tenantId;
  final String role;

  final int? cachedTotalMembers;

  const _StatsCards({
    required this.snap,
    required this.tenantId,
    required this.role,
    this.cachedTotalMembers,
  });

  @override
  Widget build(BuildContext context) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      final cached = cachedTotalMembers;
      if (cached != null && cached > 0) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 600;
            final membroRestrito = AppPermissions.isRestrictedMember(role);
            final onMembros = membroRestrito
                ? null
                : () => Navigator.push(
                      context,
                      ThemeCleanPremium.fadeSlideRoute(
                        MembersPage(tenantId: tenantId, role: role),
                      ),
                    );
            return isNarrow
                ? _StatCard(
                    label: 'Membros',
                    value: cached,
                    icon: Icons.people_rounded,
                    color: ThemeCleanPremium.primary,
                    onTap: onMembros,
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          label: 'Membros',
                          value: cached,
                          icon: Icons.people_rounded,
                          color: ThemeCleanPremium.primary,
                          onTap: onMembros,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: _SkeletonBox(height: 88)),
                      const SizedBox(width: 12),
                      const Expanded(child: _SkeletonBox(height: 88)),
                      const SizedBox(width: 12),
                      const Expanded(child: _SkeletonBox(height: 88)),
                    ],
                  );
          },
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: LayoutBuilder(
          builder: (context, c) {
            final isNarrow = c.maxWidth < 400;
            if (isNarrow) {
              return const Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _SkeletonBox(height: 88, width: 140),
                  _SkeletonBox(height: 88, width: 140),
                  _SkeletonBox(height: 88, width: 140),
                  _SkeletonBox(height: 88, width: 140),
                ],
              );
            }
            return const Row(
              children: [
                Expanded(child: _SkeletonBox(height: 88)),
                SizedBox(width: 12),
                Expanded(child: _SkeletonBox(height: 88)),
                SizedBox(width: 12),
                Expanded(child: _SkeletonBox(height: 88)),
                SizedBox(width: 12),
                Expanded(child: _SkeletonBox(height: 88)),
              ],
            );
          },
        ),
      );
    }
    if (snap.hasError) {
      return const SizedBox(height: 120, child: Center(child: Text('Não foi possível carregar estatísticas.')));
    }
    if (!snap.hasData) return const SizedBox(height: 120, child: Center(child: Text('0 membros')));
    final docs = snap.data!.docs;
    int homens = 0, mulheres = 0, criancas = 0;
    for (final d in docs) {
      final data = d.data();
      final idade = ageFromMemberData(data);
      final g = genderCategoryFromMemberData(data);
      if (idade != null && idade < 13) {
        criancas++;
      } else {
        if (g == 'M') homens++;
        else if (g == 'F') mulheres++;
      }
    }
    var total = docs.length;
    if (total == 0) {
      final cached = cachedTotalMembers;
      if (cached != null && cached > 0) total = cached;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final membroRestrito = AppPermissions.isRestrictedMember(role);
        final onMembros = membroRestrito ? null : () => Navigator.push(context, ThemeCleanPremium.fadeSlideRoute(MembersPage(tenantId: tenantId, role: role)));
        final onHomens = membroRestrito ? null : () => Navigator.push(context, ThemeCleanPremium.fadeSlideRoute(MembersPage(tenantId: tenantId, role: role, initialFiltroGenero: 'masculino')));
        final onMulheres = membroRestrito ? null : () => Navigator.push(context, ThemeCleanPremium.fadeSlideRoute(MembersPage(tenantId: tenantId, role: role, initialFiltroGenero: 'feminino')));
        final onCriancas = membroRestrito ? null : () => Navigator.push(context, ThemeCleanPremium.fadeSlideRoute(MembersPage(tenantId: tenantId, role: role, initialFiltroFaixaEtaria: 'criancas')));
        return isNarrow
            ? Column(
                children: [
                  _StatCard(label: 'Membros', value: total, icon: Icons.people_rounded, color: ThemeCleanPremium.primary, onTap: onMembros),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _StatCard(label: 'Homens', value: homens, icon: Icons.male_rounded, color: Colors.blue.shade700, onTap: onHomens)),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(label: 'Mulheres', value: mulheres, icon: Icons.female_rounded, color: Colors.pink.shade600, onTap: onMulheres)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _StatCard(label: 'Crianças', value: criancas, icon: Icons.child_care_rounded, color: Colors.amber.shade700, onTap: onCriancas),
                ],
              )
            : Row(
                children: [
                  Expanded(child: _StatCard(label: 'Membros', value: total, icon: Icons.people_rounded, color: ThemeCleanPremium.primary, onTap: onMembros)),
                  const SizedBox(width: 16),
                  Expanded(child: _StatCard(label: 'Homens', value: homens, icon: Icons.male_rounded, color: Colors.blue.shade700, onTap: onHomens)),
                  const SizedBox(width: 16),
                  Expanded(child: _StatCard(label: 'Mulheres', value: mulheres, icon: Icons.female_rounded, color: Colors.pink.shade600, onTap: onMulheres)),
                  const SizedBox(width: 16),
                  Expanded(child: _StatCard(label: 'Crianças', value: criancas, icon: Icons.child_care_rounded, color: Colors.amber.shade700, onTap: onCriancas)),
                ],
              );
      },
    );
  }
}

/// Card de estatística (Membros, Homens, Mulheres, Crianças) — Super Premium.
class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(color: color.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd)),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: ThemeCleanPremium.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: color, letterSpacing: -0.3)),
                Text(label, style: TextStyle(fontSize: 13, color: color.withOpacity(0.9), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        child: child,
      ),
    );
  }
}

/// Gráficos pizza membros: gênero (percentual) e faixa etária (percentual).
class _GraficosMembrosPizza extends StatelessWidget {
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap;
  final bool isNarrow;

  const _GraficosMembrosPizza({required this.snap, required this.isNarrow});

  @override
  Widget build(BuildContext context) {
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 600;
          return narrow
              ? Column(
                  children: [
                    _PieCard(title: 'Por gênero', icon: Icons.pie_chart_rounded, child: const _SkeletonBox(height: 200)),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    _PieCard(title: 'Por faixa etária', icon: Icons.people_rounded, child: const _SkeletonBox(height: 200)),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _PieCard(title: 'Por gênero', icon: Icons.pie_chart_rounded, child: const _SkeletonBox(height: 200))),
                    const SizedBox(width: ThemeCleanPremium.spaceMd),
                    Expanded(child: _PieCard(title: 'Por faixa etária', icon: Icons.people_rounded, child: const _SkeletonBox(height: 200))),
                  ],
                );
        },
      );
    }
    if (snap.hasError) {
      return _PieCard(
        title: 'Membros',
        icon: Icons.pie_chart_rounded,
        child: Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
      );
    }
    final docs = snap.data?.docs ?? [];
    int criSoc = 0,
        jovSoc = 0,
        homensAdulto = 0,
        mulheresAdulto = 0,
        semDadosOutros = 0;
    for (final d in docs) {
      final data = d.data();
      final idadeSoc = ageFromMemberData(data);
      final gSoc = genderCategoryFromMemberData(data);
      if (idadeSoc == null) {
        semDadosOutros++;
        continue;
      }
      if (idadeSoc < 13) {
        criSoc++;
      } else if (idadeSoc < 18) {
        jovSoc++;
      } else {
        if (gSoc == 'M') {
          homensAdulto++;
        } else if (gSoc == 'F') {
          mulheresAdulto++;
        } else {
          semDadosOutros++;
        }
      }
    }
    final demografiaTotal =
        criSoc + jovSoc + homensAdulto + mulheresAdulto + semDadosOutros;
    final demografiaEntries = <MapEntry<String, int>>[
      if (criSoc > 0) MapEntry('Crianças', criSoc),
      if (jovSoc > 0) MapEntry('Jovens', jovSoc),
      if (homensAdulto > 0) MapEntry('Homens (18+)', homensAdulto),
      if (mulheresAdulto > 0) MapEntry('Mulheres (18+)', mulheresAdulto),
      if (semDadosOutros > 0) MapEntry('Outros / sem dados', semDadosOutros),
    ];
    final pieDemografia = demografiaTotal > 0 && demografiaEntries.isNotEmpty
        ? _PieMembros(
            title: 'Demografia (visão social)',
            icon: Icons.donut_large_rounded,
            entries: demografiaEntries,
            total: demografiaTotal,
            cores: const [
              Color(0xFFF59E0B),
              Color(0xFF14B8A6),
              Color(0xFF2563EB),
              Color(0xFFDB2777),
              Color(0xFF94A3B8),
            ],
          )
        : null;

    int masculino = 0, feminino = 0, outros = 0, generoNaoInformado = 0;
    int criancas = 0, adolescentes = 0, adultos = 0, idosos = 0, semIdade = 0;
    for (final d in docs) {
      final data = d.data();
      final g = genderCategoryFromMemberData(data);
      if (g == 'M') {
        masculino++;
      } else if (g == 'F') {
        feminino++;
      } else {
        final rawSex =
            (data['SEXO'] ?? data['sexo'] ?? data['genero'] ?? data['gender'] ?? '')
                .toString()
                .trim();
        if (rawSex.isEmpty) {
          generoNaoInformado++;
        } else {
          outros++;
        }
      }

      final idade = ageFromMemberData(data);
      if (idade != null) {
        if (idade < 13) {
          criancas++;
        } else if (idade < 18) {
          adolescentes++;
        } else if (idade < 60) {
          adultos++;
        } else {
          idosos++;
        }
      } else {
        semIdade++;
      }
    }
    final total = docs.length;

    final generoEntries = <MapEntry<String, int>>[
      if (masculino > 0) MapEntry('Masculino', masculino),
      if (feminino > 0) MapEntry('Feminino', feminino),
      if (outros > 0) MapEntry('Outros', outros),
      if (generoNaoInformado > 0) MapEntry('Não informado', generoNaoInformado),
    ];
    final idadeEntries = <MapEntry<String, int>>[
      if (criancas > 0) MapEntry('Crianças (<13)', criancas),
      if (adolescentes > 0) MapEntry('Adolescentes (13-17)', adolescentes),
      if (adultos > 0) MapEntry('Adultos (18-59)', adultos),
      if (idosos > 0) MapEntry('Idosos (60+)', idosos),
      if (semIdade > 0) MapEntry('Sem idade informada', semIdade),
    ];

    final pieGenero = _PieMembros(
      title: 'Por gênero',
      icon: Icons.pie_chart_rounded,
      entries: generoEntries,
      total: total,
      cores: [
        const Color(0xFF2563EB),
        const Color(0xFFDB2777),
        const Color(0xFF7C3AED),
        const Color(0xFF94A3B8),
      ],
    );
    final pieIdade = _PieMembros(
      title: 'Por faixa etária',
      icon: Icons.people_rounded,
      entries: idadeEntries,
      total: total,
      cores: [
        const Color(0xFFF59E0B),
        const Color(0xFF14B8A6),
        const Color(0xFF2563EB),
        const Color(0xFF4F46E5),
        const Color(0xFFCBD5E1),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pieDemografia != null) ...[
            pieDemografia,
            const SizedBox(height: ThemeCleanPremium.spaceLg),
          ],
          pieGenero,
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          pieIdade,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pieDemografia != null) ...[
          pieDemografia,
          const SizedBox(height: ThemeCleanPremium.spaceLg),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: pieGenero),
            const SizedBox(width: ThemeCleanPremium.spaceLg),
            Expanded(child: pieIdade),
          ],
        ),
      ],
    );
  }
}

/// Card Super Premium para gráficos pizza — padrão moderno (radiusXl, sombras refinadas).
class _PieCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _PieCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceXl),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(color: ThemeCleanPremium.primary.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 6)),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(icon, color: ThemeCleanPremium.primary, size: 20),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceSm),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          child,
        ],
      ),
    );
  }
}

/// Pizza percentual com legenda — dados coerentes com o total, layout mobile em coluna, visual premium.
class _PieMembros extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<MapEntry<String, int>> entries;
  final int total;
  final List<Color> cores;

  const _PieMembros({required this.title, required this.icon, required this.entries, required this.total, required this.cores});

  LinearGradient _sliceGradient(Color base) {
    final lighter = Color.lerp(base, Colors.white, 0.38)!;
    final darker = Color.lerp(base, const Color(0xFF0F172A), 0.22)!;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lighter, base, darker],
      stops: const [0.0, 0.5, 1.0],
    );
  }

  Widget _legendItem(MapEntry<int, MapEntry<String, int>> e) {
    final idx = e.key;
    final label = e.value.key;
    final count = e.value.value;
    final pct = total > 0 ? (count / total * 100) : 0.0;
    final base = cores[idx % cores.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              gradient: _sliceGradient(base),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(color: base.withValues(alpha: 0.35), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13, height: 1.35, color: Color(0xFF475569)),
                children: [
                  TextSpan(
                    text: '$label\n',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  $count ${count == 1 ? 'membro' : 'membros'}',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartWithCenterTotal(List<PieChartSectionData> sections) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, c) {
          final side = c.maxWidth.clamp(160.0, 220.0);
          return Center(
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sections: sections,
                      sectionsSpace: 2.5,
                      centerSpaceRadius: side * 0.22,
                      pieTouchData: PieTouchData(enabled: false),
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 550),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.8,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'membros',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PieCard(
      title: title,
      icon: icon,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (total == 0 || entries.isEmpty) {
      return SizedBox(
        height: 220,
        child: Center(child: Text('Sem dados de membros.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
      );
    }

    final sections = entries.asMap().entries.map((e) {
      final idx = e.key;
      final count = e.value.value;
      final base = cores[idx % cores.length];
      final share = total > 0 ? count / total : 0.0;
      final showOnSlice = share >= 0.06 && count > 0;
      return PieChartSectionData(
        value: count.toDouble(),
        title: showOnSlice ? '${(share * 100).round()}%' : '',
        color: base,
        radius: 58,
        titleStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          shadows: const [
            Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black54),
          ],
        ),
        borderSide: const BorderSide(color: Color(0xFFF8FAFC), width: 2),
      );
    }).toList();

    final legend = entries.asMap().entries.map(_legendItem).toList();
    final narrow = MediaQuery.sizeOf(context).width < 520;

    if (narrow) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _chartWithCenterTotal(sections),
            const SizedBox(height: 20),
            ...legend,
          ],
        ),
      );
    }

    return SizedBox(
      height: 280,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 11,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: legend,
              ),
            ),
          ),
          Expanded(
            flex: 10,
            child: _chartWithCenterTotal(sections),
          ),
        ],
      ),
    );
  }
}

/// Gráfico de crescimento de membros — recebe snapshot compartilhado
class _GraficoMembros extends StatelessWidget {
  final AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap;

  const _GraficoMembros({required this.snap});

  @override
  Widget build(BuildContext context) {
    return _CleanCard(
      title: 'Crescimento de Membros',
      icon: Icons.trending_up_rounded,
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (snap.hasError) {
      return SizedBox(height: 180, child: Center(child: Text('Erro ao carregar dados.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))));
    }
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return SizedBox(
        height: 180,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: YahwehSkeletonLoading.panelList(itemCount: 3),
        ),
      );
    }
    final docs = snap.data?.docs ?? [];
    final now = DateTime.now();
    final byMonthKey = <String, int>{};
    final monthKeysOrdered = <String>[];
    for (var i = 11; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      final k =
          '${d.year}-${d.month.toString().padLeft(2, '0')}';
      byMonthKey[k] = 0;
      monthKeysOrdered.add(k);
    }
    for (final doc in docs) {
      final raw = doc.data()['CRIADO_EM'] ?? doc.data()['createdAt'];
      if (raw == null) continue;
      DateTime? dt;
      if (raw is Timestamp) {
        dt = raw.toDate();
      } else if (raw is Map) {
        final sec = raw['seconds'] ?? raw['_seconds'];
        if (sec != null) {
          dt = DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
        }
      }
      if (dt != null) {
        final k =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        if (byMonthKey.containsKey(k)) {
          byMonthKey[k] = (byMonthKey[k] ?? 0) + 1;
        }
      }
    }
    var acum = 0;
    final spots = monthKeysOrdered.asMap().entries.map((e) {
      acum += byMonthKey[e.value] ?? 0;
      return FlSpot(e.key.toDouble(), acum.toDouble());
    }).toList();
    if (spots.isEmpty) spots.add(const FlSpot(0, 0));

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: Colors.grey.shade200, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, _) => Text('${v.toInt()}',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600)))),
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i >= 0 && i < monthKeysOrdered.length) {
                        final parts = monthKeysOrdered[i].split('-');
                        final m =
                            parts.length >= 2 ? int.tryParse(parts[1]) ?? 1 : 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul',
                                    'Ago', 'Set', 'Out', 'Nov', 'Dez'][m - 1],
                            style: TextStyle(
                                fontSize: 9, color: Colors.grey.shade600),
                          ),
                        );
                      }
                      return const SizedBox();
                    })),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: ThemeCleanPremium.primary,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    ThemeCleanPremium.primary.withValues(alpha: 0.32),
                    ThemeCleanPremium.primary.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 800),
      ),
    );
  }
}

class _DashboardFinancePeriodStrip extends StatelessWidget {
  const _DashboardFinancePeriodStrip({
    required this.resolvedRange,
    required this.preset,
    required this.isNarrow,
    required this.onSelect,
  });

  final DateTimeRange resolvedRange;
  final ChurchDashboardFinancePreset preset;
  final bool isNarrow;
  final ValueChanged<ChurchDashboardFinancePreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = <({ChurchDashboardFinancePreset p, String label})>[
      (p: ChurchDashboardFinancePreset.previousMonth, label: 'Mês anterior'),
      (p: ChurchDashboardFinancePreset.currentMonth, label: 'Mês atual'),
      (p: ChurchDashboardFinancePreset.weekly, label: 'Semanal'),
      (p: ChurchDashboardFinancePreset.yearly, label: 'Anual'),
      (p: ChurchDashboardFinancePreset.custom, label: 'Período'),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeCleanPremium.primary.withValues(alpha: 0.09),
            const Color(0xFFECFDF5),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range_rounded,
                color: ThemeCleanPremium.primary,
                size: isNarrow ? 20 : 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Filtro financeiro do painel',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: isNarrow ? 14 : 15,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${resolvedRange.start.day.toString().padLeft(2, '0')}/${resolvedRange.start.month.toString().padLeft(2, '0')}/${resolvedRange.start.year} — '
            '${resolvedRange.end.day.toString().padLeft(2, '0')}/${resolvedRange.end.month.toString().padLeft(2, '0')}/${resolvedRange.end.year}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((e) {
              final selected = preset == e.p;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelect(e.p),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: selected
                          ? LinearGradient(
                              colors: [
                                ThemeCleanPremium.primary,
                                ThemeCleanPremium.primary
                                    .withValues(alpha: 0.88),
                              ],
                            )
                          : null,
                      color: selected ? null : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? ThemeCleanPremium.primary
                            : const Color(0xFFE2E8F0),
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: ThemeCleanPremium.primary
                                    .withValues(alpha: 0.32),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      e.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color:
                            selected ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

DateTime? _dashboardFinanceDocDate(Map<String, dynamic> data) {
  final raw = data['createdAt'] ?? data['date'] ?? data['data'];
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is Map) {
    final sec = raw['seconds'] ?? raw['_seconds'];
    if (sec != null) {
      return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
    }
  }
  return null;
}

bool _dashboardDateInRange(DateTime? dt, DateTimeRange range) {
  if (dt == null) return false;
  return !dt.isBefore(range.start) && !dt.isAfter(range.end);
}

class _DashFinanceBuckets {
  _DashFinanceBuckets({
    required this.labels,
    required this.bucketStarts,
    required this.monthlyMode,
  });

  final List<String> labels;
  final List<DateTime> bucketStarts;
  final bool monthlyMode;
}

_DashFinanceBuckets _dashboardFinanceBuckets(
  DateTimeRange range,
  ChurchDashboardFinancePreset preset,
) {
  const meses = [
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ];
  final d0 = DateTime(range.start.year, range.start.month, range.start.day);
  final d1 = DateTime(range.end.year, range.end.month, range.end.day);
  final nDays = d1.difference(d0).inDays + 1;

  if (preset == ChurchDashboardFinancePreset.yearly) {
    final y = range.start.year;
    final labels = <String>[];
    final starts = <DateTime>[];
    for (var m = 1; m <= 12; m++) {
      labels.add(meses[m - 1]);
      starts.add(DateTime(y, m, 1));
    }
    return _DashFinanceBuckets(
      labels: labels,
      bucketStarts: starts,
      monthlyMode: true,
    );
  }

  if (preset == ChurchDashboardFinancePreset.weekly ||
      preset == ChurchDashboardFinancePreset.currentMonth ||
      preset == ChurchDashboardFinancePreset.previousMonth ||
      (preset == ChurchDashboardFinancePreset.custom && nDays <= 40)) {
    final labels = <String>[];
    final starts = <DateTime>[];
    for (var i = 0; i < nDays; i++) {
      final day = d0.add(Duration(days: i));
      labels.add(
        '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
      );
      starts.add(day);
    }
    return _DashFinanceBuckets(
      labels: labels,
      bucketStarts: starts,
      monthlyMode: false,
    );
  }

  final labels = <String>[];
  final starts = <DateTime>[];
  var y = range.start.year;
  var m = range.start.month;
  final endY = range.end.year;
  final endM = range.end.month;
  while (y < endY || (y == endY && m <= endM)) {
    final first = DateTime(y, m, 1);
    labels.add('${meses[m - 1]}/$y');
    starts.add(first);
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return _DashFinanceBuckets(
    labels: labels,
    bucketStarts: starts,
    monthlyMode: true,
  );
}

int? _dashboardBucketIndexForDate(
  DateTime dt,
  _DashFinanceBuckets b,
) {
  if (b.monthlyMode) {
    for (var i = 0; i < b.bucketStarts.length; i++) {
      final s = b.bucketStarts[i];
      final e = DateTime(s.year, s.month + 1, 0, 23, 59, 59, 999);
      if (!dt.isBefore(s) && !dt.isAfter(e)) return i;
    }
    return null;
  }
  final day = DateTime(dt.year, dt.month, dt.day);
  for (var i = 0; i < b.bucketStarts.length; i++) {
    final s = b.bucketStarts[i];
    if (day == DateTime(s.year, s.month, s.day)) return i;
  }
  return null;
}

List<double> _dashboardSaidasFromFinanceDocs({
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  required _DashFinanceBuckets buckets,
  required bool Function(Map<String, dynamic>) isDespesa,
  required double Function(Map<String, dynamic>) valorAbs,
  required DateTime? Function(Map<String, dynamic>) dataDoc,
}) {
  final out = List<double>.filled(buckets.labels.length, 0);
  for (final doc in docs) {
    final data = doc.data();
    if (!isDespesa(data)) continue;
    final dt = dataDoc(data);
    if (dt == null) continue;
    final idx = _dashboardBucketIndexForDate(dt, buckets);
    if (idx == null) continue;
    out[idx] += valorAbs(data);
  }
  return out;
}

/// Barras horizontais — legível no telemóvel (sem sobrepor eixos do fl_chart).
class _HorizontalDespesasBarChart extends StatelessWidget {
  const _HorizontalDespesasBarChart({
    required this.labels,
    required this.values,
    this.maxHeight = 240,
  });

  final List<String> labels;
  final List<double> values;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final nfCompact = NumberFormat.compactCurrency(
      locale: 'pt_BR',
      symbol: r'R$',
      decimalDigits: 0,
    );
    final entries = <({String label, double value})>[];
    for (var i = 0; i < labels.length; i++) {
      final v = i < values.length ? values[i] : 0.0;
      if (v > 0) entries.add((label: labels[i], value: v));
    }
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          'Sem despesas no período selecionado.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }
    entries.sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.fold<double>(0, (a, e) => e.value > a ? e.value : a);
    final barMax = maxVal <= 0 ? 1.0 : maxVal;
    const rowH = 34.0;
    final listH = (entries.length * rowH).clamp(80.0, maxHeight);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Total',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
            const Spacer(),
            Text(
              nf.format(entries.fold<double>(0, (s, e) => s + e.value)),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFFDC2626),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: listH,
          child: ListView.separated(
            physics: entries.length > 6
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final e = entries[i];
              final frac = (e.value / barMax).clamp(0.06, 1.0);
              final money = e.value >= 1000
                  ? nfCompact.format(e.value)
                  : nf.format(e.value);
              return Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      e.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        return Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 22,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 380),
                              curve: Curves.easeOutCubic,
                              width: c.maxWidth * frac,
                              height: 22,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFF87171),
                                    Color(0xFFDC2626),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFDC2626)
                                        .withValues(alpha: 0.18),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 72,
                    child: Text(
                      money,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Gráfico fluxo financeiro — cache `finance_summary` + refresh após lançamento.
class _GraficoFinanceiro extends StatefulWidget {
  final String tenantId;
  final DateTimeRange range;
  final ChurchDashboardFinancePreset preset;
  final int financeRefreshTick;

  const _GraficoFinanceiro({
    required this.tenantId,
    required this.range,
    required this.preset,
    this.financeRefreshTick = 0,
  });

  @override
  State<_GraficoFinanceiro> createState() => _GraficoFinanceiroState();
}

class _GraficoFinanceiroState extends State<_GraficoFinanceiro> {
  PanelFinanceChartData? _chartData;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadChart());
  }

  @override
  void didUpdateWidget(covariant _GraficoFinanceiro oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.financeRefreshTick != widget.financeRefreshTick ||
        !ChurchDashboardFinancePeriod.sameRange(oldWidget.range, widget.range) ||
        oldWidget.preset != widget.preset) {
      unawaited(_loadChart());
    }
  }

  Future<void> _loadChart() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _chartData = null;
        });
      }
      return;
    }

    final buckets = _dashboardFinanceBuckets(widget.range, widget.preset);
    final peek = ChurchFinanceLoadService.peekLancamentosRam(tid, limit: 400);
    if (peek != null && peek.isNotEmpty && mounted) {
      setState(() {
        _chartData = PanelFinanceChartService.fromFinanceDocs(
          docs: peek,
          bucketStarts: buckets.bucketStarts,
          monthlyMode: buckets.monthlyMode,
          clipRange: widget.range,
        );
        _loading = false;
        _loadError = null;
      });
    } else if (mounted && _chartData == null) {
      setState(() => _loading = true);
    }

    try {
      final data = await PanelFinanceChartService.load(
        tenantId: tid,
        bucketStarts: buckets.bucketStarts,
        monthlyMode: buckets.monthlyMode,
        clipRange: widget.range,
      ).timeout(PanelResilientLoad.queryCap);
      if (!mounted) return;
      setState(() {
        _chartData = data;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_chartData == null) {
        setState(() => _loadError = '$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _CleanCard(
      title: 'Fluxo Financeiro',
      icon: Icons.account_balance_wallet_rounded,
      child: _buildChartBody(),
    );
  }

  Widget _buildChartBody() {
    if (_loading && (_chartData == null || !_chartData!.hasValues)) {
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_chartData == null && _loadError != null) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Sem dados financeiros no período.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
      );
    }
    return _buildChartFromData(_chartData ?? PanelFinanceChartData(
      netByBucket: const [0],
      entradasByBucket: const [0],
      saidasByBucket: const [0],
      totalEntradas: 0,
      totalSaidas: 0,
    ));
  }

  Widget _buildChartFromData(PanelFinanceChartData data) {
    final buckets = _dashboardFinanceBuckets(widget.range, widget.preset);
    final byBucket = data.netByBucket;
    final spots = byBucket
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();
    if (spots.isEmpty) spots.add(const FlSpot(0, 0));

    final nf = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    const lineColor = Color(0xFF16A34A);
    final nLabels = buckets.labels.length;
    final bottomInterval = nLabels > 28
        ? 5.0
        : nLabels > 18
            ? 3.0
            : (nLabels > 12 ? 2.0 : 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${ChurchDashboardFinancePeriod.presetLabel(widget.preset)} · '
          '${widget.range.start.day.toString().padLeft(2, '0')}/${widget.range.start.month.toString().padLeft(2, '0')} '
          '— ${widget.range.end.day.toString().padLeft(2, '0')}/${widget.range.end.month.toString().padLeft(2, '0')}/${widget.range.end.year}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: Colors.grey.shade200, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, _) => Text(
                      'R\$${v.toInt()}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: nLabels > 22 ? 30 : 24,
                    interval: bottomInterval,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i >= 0 && i < buckets.labels.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            buckets.labels[i],
                            style: TextStyle(
                              fontSize: nLabels > 22 ? 8 : 9,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        );
                      }
                      return const SizedBox();
                    },
                  ),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchSpotThreshold: 22,
                mouseCursorResolver: (_, __) => SystemMouseCursors.click,
                getTouchedSpotIndicator: (barData, spotIndexes) {
                  return spotIndexes.map((index) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: const Color(0xFF64748B).withValues(alpha: 0.65),
                        strokeWidth: 1.5,
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, ix) =>
                            FlDotCirclePainter(
                          radius: 7,
                          color: lineColor,
                          strokeWidth: 2.5,
                          strokeColor: Colors.white,
                        ),
                      ),
                    );
                  }).toList();
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF0F172A),
                  tooltipBorderRadius: BorderRadius.circular(12),
                  tooltipPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  tooltipMargin: 10,
                  maxContentWidth: 240,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  tooltipBorder: BorderSide(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map<LineTooltipItem?>((t) {
                      final i = t.x.toInt();
                      if (i < 0 || i >= buckets.labels.length) {
                        return null;
                      }
                      final label = buckets.labels[i];
                      final money = nf.format(t.y);
                      return LineTooltipItem(
                        '',
                        const TextStyle(fontSize: 0),
                        textAlign: TextAlign.center,
                        children: [
                          TextSpan(
                            text: '$label\n',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                          TextSpan(
                            text: money,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              height: 1.25,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.28,
                  color: lineColor,
                  barWidth: 3,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, ix) =>
                        FlDotCirclePainter(
                      radius: 3.5,
                      color: lineColor,
                      strokeWidth: 1.5,
                      strokeColor: Colors.white,
                    ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        lineColor.withValues(alpha: 0.22),
                        lineColor.withValues(alpha: 0.03),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
          ),
        ),
      ],
    );
  }
}

/// Gráfico de barras (despesas via `finance_summary`) + últimas saídas (fetch leve).
class _PainelDespesasDashboard extends StatefulWidget {
  final DateTimeRange range;
  final ChurchDashboardFinancePreset preset;
  final String tenantId;
  final String role;
  final String cpf;
  final bool? podeVerFinanceiro;
  final List<String>? permissions;
  final bool isNarrow;
  final int financeRefreshTick;

  const _PainelDespesasDashboard({
    required this.range,
    required this.preset,
    required this.tenantId,
    required this.role,
    required this.cpf,
    this.podeVerFinanceiro,
    this.permissions,
    required this.isNarrow,
    this.financeRefreshTick = 0,
  });

  @override
  State<_PainelDespesasDashboard> createState() => _PainelDespesasDashboardState();
}

class _PainelDespesasDashboardState extends State<_PainelDespesasDashboard> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _recentDespesasFuture;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _seedDocs;

  @override
  void initState() {
    super.initState();
    _reloadRecentDespesas();
  }

  @override
  void didUpdateWidget(covariant _PainelDespesasDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.financeRefreshTick != widget.financeRefreshTick ||
        !ChurchDashboardFinancePeriod.sameRange(
          oldWidget.range,
          widget.range,
        ) ||
        oldWidget.preset != widget.preset) {
      _reloadRecentDespesas(forceFresh: true);
    }
  }

  void _reloadRecentDespesas({bool forceFresh = false}) {
    final tid = ChurchRepository.churchId(widget.tenantId);
    if (tid.isEmpty) {
      _seedDocs = const [];
      _recentDespesasFuture = Future.value(MergedFirestoreQuerySnapshot(const []));
      return;
    }
    if (!forceFresh) {
      _seedDocs =
          ChurchFinanceLoadService.peekLancamentosRam(tid, limit: 180) ??
              const [];
    } else {
      _seedDocs ??= const [];
    }
    _recentDespesasFuture = Future.value(
      MergedFirestoreQuerySnapshot(_seedDocs!),
    );
    unawaited(
      ChurchFinanceLoadService.loadLancamentos(
        seedTenantId: tid,
        limit: 180,
        forceRefresh: forceFresh,
        forceServer: forceFresh,
      )
          .timeout(PanelResilientLoad.queryCap)
          .then((r) {
        if (!mounted) return;
        setState(() {
          _seedDocs = r.docs;
          _recentDespesasFuture = Future.value(r.snapshot);
        });
      }).catchError((e, st) {
        debugPrint('Dashboard _warmRecentDespesas loadLancamentos: $e\n$st');
      }),
    );
  }

  static bool _ehDespesa(Map<String, dynamic> data) =>
      financeIsSaida(data);

  static DateTime? _dataDoc(Map<String, dynamic> data) {
    final raw = data['createdAt'] ?? data['date'] ?? data['data'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is Map) {
      final sec = raw['seconds'] ?? raw['_seconds'];
      if (sec != null) {
        return DateTime.fromMillisecondsSinceEpoch((sec as num).toInt() * 1000);
      }
    }
    return null;
  }

  static double _valorAbs(Map<String, dynamic> data) {
    final valor = data['amount'] ?? data['valor'] ?? data['value'] ?? 0;
    final v = valor is num
        ? valor.toDouble()
        : double.tryParse(valor.toString()) ?? 0;
    return v.abs();
  }

  @override
  Widget build(BuildContext context) {
    void openFinanceiro({String? openId, int? tab}) {
      Navigator.push(
        context,
        ThemeCleanPremium.fadeSlideRoute(
          FinancePage(
            tenantId: widget.tenantId,
            role: widget.role,
            cpf: widget.cpf,
            podeVerFinanceiro: widget.podeVerFinanceiro,
            permissions: widget.permissions,
            initialTabIndex: tab,
            openLancamentoId: openId,
          ),
        ),
      );
    }

    final buckets = _dashboardFinanceBuckets(widget.range, widget.preset);
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _recentDespesasFuture,
      builder: (context, recentSnap) {
        final allDocs =
            recentSnap.data?.docs ?? _seedDocs ?? const [];
        var despesasDocs =
            allDocs.where((d) => _ehDespesa(d.data())).toList();
        despesasDocs = despesasDocs.where((d) {
          final dt = _dataDoc(d.data());
          return _dashboardDateInRange(dt, widget.range);
        }).toList();
        final byBucket = _dashboardSaidasFromFinanceDocs(
          docs: allDocs,
          buckets: buckets,
          isDespesa: _ehDespesa,
          valorAbs: _valorAbs,
          dataDoc: _dataDoc,
        );
        final chartHasData = byBucket.any((v) => v > 0);
        despesasDocs.sort((a, b) {
          final da = _dataDoc(a.data());
          final db = _dataDoc(b.data());
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
        final recent = despesasDocs.take(8).toList();
        if (!chartHasData && recent.isEmpty) {
          return const SizedBox.shrink();
        }

        return _CleanCard(
          title: 'Despesas (painel)',
          icon: Icons.trending_down_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${ChurchDashboardFinancePeriod.presetLabel(widget.preset)} · mesmo período do fluxo',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              if (chartHasData)
                _HorizontalDespesasBarChart(
                  labels: buckets.labels,
                  values: byBucket,
                  maxHeight: widget.isNarrow ? 220 : 260,
                ),
              if (chartHasData) const SizedBox(height: 12),
              if (recent.isNotEmpty) ...[
              Text(
                'Últimas despesas — toque para editar ou anexar comprovante',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              ...recent.map((doc) {
                final data = doc.data();
                final desc = (data['descricao'] ??
                        data['anotacoes'] ??
                        data['categoria'] ??
                        'Despesa')
                    .toString();
                final val = _valorAbs(data);
                final dt = _dataDoc(data);
                final ds = dt != null
                    ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => openFinanceiro(openId: doc.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long_rounded,
                                color: Colors.red.shade700, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    desc,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (ds.isNotEmpty)
                                    Text(
                                      ds,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              'R\$ ${val.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => openFinanceiro(tab: 1),
                icon: const Icon(Icons.list_alt_rounded, size: 20),
                label: const Text('Ver todos os lançamentos'),
              ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TarefasPendentes extends StatelessWidget {
  final String tenantId;
  final String role;
  final List<String>? permissions;
  final PanelDashboardSnapshot initialPanelCache;
  const _TarefasPendentes({
    required this.tenantId,
    required this.role,
    this.permissions,
    this.initialPanelCache = const PanelDashboardSnapshot(),
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PanelDashboardSnapshot>(
      stream: PanelDashboardSnapshotService.watch(tenantId),
      initialData: initialPanelCache,
      builder: (context, cacheSnap) {
        final summary = cacheSnap.data ?? initialPanelCache;
        final cacheReady = cacheSnap.hasData;
        return _CleanCard(
          title: 'Tarefas Pendentes',
          icon: Icons.checklist_rounded,
          child: Column(
            children: [
              if (AppPermissions.canApprovePendingMemberSignups(role,
                  permissions: permissions)) ...[
                _PendingRow(
                  icon: Icons.person_add_rounded,
                  color: const Color(0xFFE11D48),
                  label: 'Membros pendentes de aprovação',
                  count: cacheReady ? summary.pendingMembersCount : null,
                  fallbackStream:                       ChurchUiCollections.membros(tenantId)
                      .where('status', isEqualTo: 'pendente')
                      .limit(40)
                      .watchSafe(),
                  onTap: () => Navigator.push(
                      context,
                      ThemeCleanPremium.fadeSlideRoute(AprovarMembrosPendentesPage(
                          tenantId: tenantId,
                          gestorRole: role,
                          permissions: permissions))),
                ),
                const SizedBox(height: 10),
              ],
              _PendingRow(
                icon: Icons.people_outline_rounded,
                color: const Color(0xFF0891B2),
                label: 'Visitantes aguardando follow-up',
                count: cacheReady ? summary.newVisitorsCount : null,
                fallbackStream:                     ChurchUiCollections.visitantes(tenantId)
                    .where('status', isEqualTo: 'Novo')
                    .limit(40)
                    .watchSafe(),
                onTap: () => Navigator.push(
                    context,
                    ThemeCleanPremium.fadeSlideRoute(
                        VisitorsPage(tenantId: tenantId, role: role))),
              ),
              const SizedBox(height: 10),
              _PendingRow(
                icon: Icons.volunteer_activism_rounded,
                color: const Color(0xFF7C3AED),
                label: 'Pedidos de oração ativos',
                count: cacheReady ? summary.openPrayerRequestsCount : null,
                fallbackStream:                     ChurchUiCollections.pedidosOracao(tenantId)
                    .where('respondida', isEqualTo: false)
                    .limit(40)
                    .watchSafe(),
                onTap: () => Navigator.push(
                    context,
                    ThemeCleanPremium.fadeSlideRoute(
                        PrayerRequestsPage(tenantId: tenantId, role: role))),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PendingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int? count;
  final Stream<QuerySnapshot>? fallbackStream;
  final VoidCallback? onTap;
  const _PendingRow({
    required this.icon,
    required this.color,
    required this.label,
    this.count,
    this.fallbackStream,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (count != null) {
      return _pendingRowBody(context, count!, loading: false);
    }
    return StreamBuilder<QuerySnapshot>(
      stream: fallbackStream,
      builder: (context, snap) {
        final c = snap.hasData ? snap.data!.docs.length : 0;
        final loading =
            snap.connectionState == ConnectionState.waiting && !snap.hasData;
        return _pendingRowBody(context, c, loading: loading);
      },
    );
  }

  Widget _pendingRowBody(BuildContext context, int count, {required bool loading}) {
        final child = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: count > 0 ? color.withOpacity(0.06) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
            border: Border.all(color: count > 0 ? color.withOpacity(0.15) : Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(icon, color: count > 0 ? color : Colors.grey.shade400, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: ThemeCleanPremium.onSurface))),
              if (loading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: count > 0 ? color : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
            ],
          ),
        );
        if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
        child: child,
      ),
    );
  }
}

/// Card Super Premium — gráficos e seções do painel (padrão moderno).
class _CleanCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  /// Seções tipo feed (Eventos/Avisos): padding menor e mais compacto.
  final bool compact;

  const _CleanCard({
    required this.title,
    required this.icon,
    required this.child,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 12.0 : ThemeCleanPremium.spaceXl;
    final gapAfterTitle = compact ? 10.0 : ThemeCleanPremium.spaceLg;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(
          compact ? ThemeCleanPremium.radiusLg : ThemeCleanPremium.radiusXl,
        ),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(color: ThemeCleanPremium.primary.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 6)),
        ],
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 7 : 8),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                ),
                child: Icon(icon, color: ThemeCleanPremium.primary, size: compact ? 18 : 20),
              ),
              const SizedBox(width: ThemeCleanPremium.spaceSm),
              Text(
                title,
                style: TextStyle(
                  fontSize: compact ? 16 : 17,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          SizedBox(height: gapAfterTitle),
          child,
        ],
      ),
    );
  }
}

/// Parâmetros para [StableStorageImage] (URL https, `gs://` ou path `igrejas/...`).
({String? storagePath, String? imageUrl, String? gsUrl}) _painelDestaqueStableParamsFromRef(
    String raw) {
  final s = sanitizeImageUrl(raw);
  if (s.isEmpty) return (storagePath: null, imageUrl: null, gsUrl: null);
  if (s.toLowerCase().startsWith('gs://')) {
    return (storagePath: null, imageUrl: null, gsUrl: s);
  }
  if (!s.startsWith('http://') &&
      !s.startsWith('https://') &&
      firebaseStorageMediaUrlLooksLike(s)) {
    final p =
        normalizeFirebaseStorageObjectPath(s.replaceFirst(RegExp(r'^/+'), ''));
    return (storagePath: p, imageUrl: null, gsUrl: null);
  }
  return (storagePath: null, imageUrl: s, gsUrl: null);
}

/// Legenda do post no painel — trunca com "Veja mais" (estilo feed).
class _PainelDestaqueExpandableText extends StatefulWidget {
  final String text;
  final int maxLines;
  const _PainelDestaqueExpandableText({
    required this.text,
    this.maxLines = 3,
  });

  @override
  State<_PainelDestaqueExpandableText> createState() =>
      _PainelDestaqueExpandableTextState();
}

class _PainelDestaqueExpandableTextState
    extends State<_PainelDestaqueExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.text.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    final style = TextStyle(
      fontSize: 14,
      height: 1.45,
      color: Colors.grey.shade800,
    );
    final hasLink =
        RegExp(r'https?://|www\.', caseSensitive: false).hasMatch(t);
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final tp = TextPainter(
          text: TextSpan(text: t, style: style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: maxW);
        final overflow = tp.didExceedMaxLines || t.length > 180;
        final showButton = _expanded || overflow;
        final linkStyle = style.copyWith(
          color: ThemeCleanPremium.primary,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationColor: ThemeCleanPremium.primary,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasLink)
              SelectableLinkify(
                text: t,
                maxLines: _expanded ? null : widget.maxLines,
                onOpen: (link) => openHttpsUrlInBrowser(context, link.url),
                style: style,
                linkStyle: linkStyle,
                options: const LinkifyOptions(humanize: false),
              )
            else
              Text(
                t,
                style: style,
                maxLines: _expanded ? null : widget.maxLines,
                overflow:
                    _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              ),
            if (showButton)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    minimumSize: const Size(
                      ThemeCleanPremium.minTouchTarget,
                      40,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: ThemeCleanPremium.primary,
                  ),
                  child: Text(
                    _expanded ? 'Mostrar menos' : 'Veja mais',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Card de aviso a partir do cache `_panel_cache` (1 leitura, sem stream).
class _DestaqueAvisoCacheCard extends StatelessWidget {
  final PanelHomeAvisoLite aviso;
  final String tenantId;
  final String role;
  final String churchSlug;
  final String nomeIgreja;

  const _DestaqueAvisoCacheCard({
    required this.aviso,
    required this.tenantId,
    required this.role,
    required this.churchSlug,
    required this.nomeIgreja,
  });

  @override
  Widget build(BuildContext context) {
    final title = aviso.title.trim().isEmpty ? 'Aviso' : aviso.title.trim();
    final cover = (aviso.coverPhotoUrl ?? '').trim();
    final stable = _painelDestaqueStableParamsFromRef(cover);
    final gradient = _DestaqueCard._gradientBanner(title, false);
    final imageH = 160.0;
    Widget imageArea;
    if (cover.isNotEmpty &&
        (stable.imageUrl != null ||
            stable.storagePath != null ||
            stable.gsUrl != null)) {
      imageArea = SizedBox(
        height: imageH,
        width: double.infinity,
        child: _DestaqueCard._DestaqueCardImage(
          displayImageUrl: stable.imageUrl ?? '',
          storagePath: stable.storagePath,
          gsUrl: stable.gsUrl,
          videoThumbUrl: null,
          hasVideo: false,
          firstImgEmpty: false,
          title: title,
          isEvento: false,
        ),
      );
    } else {
      imageArea = SizedBox(height: imageH, width: double.infinity, child: gradient);
    }
    final preview = aviso.textPreview.trim();
    return Material(
      color: ThemeCleanPremium.cardBackground,
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            ThemeCleanPremium.fadeSlideRoute(
              MuralPage(tenantId: tenantId, role: role),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            imageArea,
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Destaques de avisos (feed vertical). Eventos com mídia / galeria ficam no módulo Eventos e no site.
class _DestaqueAvisos extends StatelessWidget {
  final String tenantId;
  final String role;
  final String churchSlug;
  final String nomeIgreja;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final PanelDashboardSnapshot panelCache;
  final VoidCallback? onRetryStream;
  const _DestaqueAvisos({
    required this.tenantId,
    required this.role,
    required this.churchSlug,
    required this.nomeIgreja,
    required this.stream,
    required this.panelCache,
    this.onRetryStream,
  });

  Widget _buildFromCacheAvisos(BuildContext context) {
    final avisos = panelCache.homeAvisos.where((a) {
      return PanelFeedPostValidator.isRenderableForPanelFeed(
        {
          'title': a.title,
          'coverPhotoUrl': a.coverPhotoUrl,
          'textPreview': a.textPreview,
        },
        docId: a.id,
        churchId: tenantId,
      );
    }).toList();
    if (avisos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.campaign_outlined,
                  size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text(
                'Nenhum aviso recente.',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: avisos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _DestaqueAvisoCacheCard(
        aviso: avisos[i],
        tenantId: tenantId,
        role: role,
        churchSlug: churchSlug,
        nomeIgreja: nomeIgreja,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CleanCard(
      title: 'Avisos',
      icon: Icons.campaign_rounded,
      compact: false,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            final hasLocal = panelCache.hasHomeAvisos;
            if (hasLocal) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ChurchPanelResilientLoadBanner(
                    hasLocalData: true,
                    isSyncing: false,
                    showStaleCache: true,
                    errorTitle: 'Não foi possível carregar os avisos',
                    error: snap.error,
                    onRetry: onRetryStream,
                  ),
                  _buildFromCacheAvisos(context),
                ],
              );
            }
            return ChurchPanelResilientLoadBanner(
              hasLocalData: false,
              isSyncing: false,
              errorTitle: 'Não foi possível carregar os avisos',
              error: snap.error,
              onRetry: onRetryStream,
            );
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            if (panelCache.hasHomeAvisos) {
              return _buildFromCacheAvisos(context);
            }
            return SizedBox(
              height: 104,
              child: Row(children: List.generate(3, (_) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SkeletonBox(width: 128, height: 104, borderRadius: 12),
              ))),
            );
          }
          final now = DateTime.now();
          final docs = (snap.data?.docs ?? []).where((d) {
            final data = d.data();
            final type = (data['type'] ?? '').toString().toLowerCase();
            if (type == 'evento') return false;
            if (data['ativo'] == false) return false;
            if (data['publicado'] == false) return false;
            if ((data['status'] ?? '').toString().trim() == 'erro') {
              return false;
            }
            final v = data['validUntil'];
            if (v != null) {
              if (v is Timestamp && !v.toDate().isAfter(now)) return false;
            }
            return PanelFeedPostValidator.isRenderableForPanelFeed(
              data,
              docId: d.id,
              churchId: tenantId,
            );
          }).take(PanelFeedPostValidator.kPanelFeedPageSize).toList();
          if (docs.isEmpty) {
            return Center(child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.campaign_outlined, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text(
                  'Nenhum aviso recente.',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                ),
              ]),
            ));
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _DestaqueCard(
              doc: docs[i],
              tenantId: tenantId,
              role: role,
              churchSlug: churchSlug,
              nomeIgreja: nomeIgreja,
            ),
          );
        },
      ),
    );
  }
}

/// Eventos especiais da coleção [noticias] — **só** os que ainda estão no Feed (data não passou;
/// os demais ficam na Galeria de Eventos no módulo Mural).
class _DestaqueEventosEspeciaisPainel extends StatelessWidget {
  final String tenantId;
  final String role;
  final String churchSlug;
  final String nomeIgreja;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  final VoidCallback? onRetryStream;

  const _DestaqueEventosEspeciaisPainel({
    required this.tenantId,
    required this.role,
    required this.churchSlug,
    required this.nomeIgreja,
    required this.stream,
    this.onRetryStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.hasError) {
          final now = DateTime.now();
          final cachedDocs = (snap.data?.docs ?? [])
              .where(
                (d) =>
                    noticiaDocEhEventoSpecialFeed(d) &&
                    !noticiaEventoEspecialCaiuDoFeedParaGaleria(d.data(), now),
              )
              .where((d) {
                final v = d.data()['validUntil'];
                if (v == null) return true;
                if (v is Timestamp) return v.toDate().isAfter(now);
                return true;
              })
              .toList();
          if (cachedDocs.isNotEmpty) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChurchPanelResilientLoadBanner(
                  hasLocalData: true,
                  isSyncing: false,
                  showStaleCache: true,
                  errorTitle:
                      'Não foi possível carregar os eventos em destaque',
                  error: snap.error,
                  onRetry: onRetryStream,
                ),
                _CleanCard(
                  title: 'Eventos em destaque',
                  icon: Icons.event_rounded,
                  compact: false,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cachedDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _DestaqueCard(
                      doc: cachedDocs[i],
                      tenantId: tenantId,
                      role: role,
                      churchSlug: churchSlug,
                      nomeIgreja: nomeIgreja,
                    ),
                  ),
                ),
              ],
            );
          }
          return ChurchPanelResilientLoadBanner(
            hasLocalData: false,
            isSyncing: false,
            errorTitle: 'Não foi possível carregar os eventos em destaque',
            error: snap.error,
            onRetry: onRetryStream,
          );
        }
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SizedBox.shrink();
        }
        final now = DateTime.now();
        final docs = (snap.data?.docs ?? [])
            .where(
              (d) =>
                  noticiaDocEhEventoSpecialFeed(d) &&
                  !noticiaEventoEspecialCaiuDoFeedParaGaleria(d.data(), now),
            )
            .where((d) {
              final v = d.data()['validUntil'];
              if (v != null) {
                if (v is Timestamp && !v.toDate().isAfter(now)) return false;
              }
              return PanelFeedPostValidator.isRenderableForPanelFeed(
                d.data(),
                docId: d.id,
                churchId: tenantId,
              );
            })
            .take(PanelFeedPostValidator.kPanelFeedPageSize)
            .toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          unawaited(
            scheduleFeedMediaWarmup(
              context,
              docs.take(6).map((d) => d.data()).toList(),
              maxDocs: 6,
            ),
          );
        });
        return _CleanCard(
          title: 'Eventos em destaque',
          icon: Icons.event_rounded,
          compact: false,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _DestaqueCard(
              doc: docs[i],
              tenantId: tenantId,
              role: role,
              churchSlug: churchSlug,
              nomeIgreja: nomeIgreja,
            ),
          ),
        );
      },
    );
  }
}

/// Tamanho base da mídia no painel (cartão lateral em desktop/tablet).
/// Valor maior para evitar miniatura "achatada" no web.
const double _kPainelDestaqueThumbSide = 220;

/// Largura mínima para dividir mídia (esq.) e texto (dir.) no painel — web.
/// Reduzido para ativar mais cedo no dashboard com sidebar.
const double _kPainelDestaqueWebSplitMinWidth = 620;

/// Mesmo critério do site público / mural: [churchMuralCarouselClipHeight] +
/// [postFeedCarouselAspectRatioForIndex] (incl. [media_info.aspect_ratio]).
double _painelDestaqueMediaClipHeight(
  BuildContext context,
  double width,
  Map<String, dynamic> postData, {
  required int nPhotosForAr,
  int carouselIndex = 0,
}) {
  final w = width > 0 ? width : 360.0;
  final denom = nPhotosForAr > 0 ? nPhotosForAr : 1;
  final safeIdx = carouselIndex.clamp(0, denom - 1);
  final ar = postFeedCarouselAspectRatioForIndex(postData, safeIdx, denom);
  return churchMuralCarouselClipHeight(context, w, ar);
}

/// Retorna datas expandidas de um template (evento fixo) dentro do intervalo.
List<DateTime> _expandTemplateDates(Map<String, dynamic> data, DateTime rangeStart, DateTime rangeEnd) {
  final weekday = (data['weekday'] ?? 7) as int;
  final time = (data['time'] ?? '19:30').toString();
  final recurrence = (data['recurrence'] ?? 'weekly').toString();
  final parts = time.split(':');
  final hour = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 19;
  final min = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 30;
  DateTime nextWeekday(DateTime from) {
    var d = DateTime(from.year, from.month, from.day);
    while (d.weekday != weekday) d = d.add(const Duration(days: 1));
    return d;
  }
  final dates = <DateTime>[];
  var cursor = nextWeekday(DateTime(rangeStart.year, rangeStart.month, rangeStart.day));
  final rangeEndDate = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
  final lastDay = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  while (!cursor.isAfter(lastDay)) {
    final dt = DateTime(cursor.year, cursor.month, cursor.day, hour, min);
    if (!dt.isBefore(rangeStart) && !dt.isAfter(rangeEndDate)) dates.add(dt);
    if (recurrence == 'biweekly') cursor = cursor.add(const Duration(days: 14));
    else if (recurrence == 'monthly') cursor = DateTime(cursor.year, cursor.month + 1, cursor.day);
    else cursor = cursor.add(const Duration(days: 7));
  }
  return dates;
}

/// Carrega eventos do Firestore + expande eventos fixos (templates) no intervalo; retorna lista unificada ordenada por startAt.
///
/// [apenasRotinaGerada] `true` = lista abaixo do painel (só programação fixa / gerada por template).
/// `false` = comportamento legado (inclui posts do Feed na mesma lista) — não usado no dashboard atual.
Future<List<Map<String, dynamic>>> _loadEventosComFixos(
  String tenantId,
  DateTime rangeStart,
  DateTime rangeEnd, {
  bool apenasRotinaGerada = false,
}) async {
  var tid = ChurchRepository.churchId(tenantId);
  if (tid.isEmpty) tid = tenantId.trim();
  if (tid.isEmpty) return const [];

  final churchRef = ChurchUiCollections.churchDoc(tid);
  final noticiasRef = churchRef.collection('eventos');
  final templatesRef = churchRef.collection('event_templates');

  List<QueryDocumentSnapshot<Map<String, dynamic>>> realDocs = const [];
  try {
    final snap =
        await ChurchTenantResilientReads.noticiasByStartAt(tid, limit: 120);
    realDocs = snap.docs
        .where((d) => (d.data()['type'] ?? '').toString() == 'evento')
        .where((d) {
          final ts = d.data()['startAt'];
          if (ts is! Timestamp) return false;
          final dt = ts.toDate();
          return !dt.isBefore(rangeStart) && !dt.isAfter(rangeEnd);
        })
        .toList();
    realDocs.sort((a, b) {
      final tsa = a.data()['startAt'];
      final tsb = b.data()['startAt'];
      if (tsa is! Timestamp || tsb is! Timestamp) return 0;
      return tsa.toDate().compareTo(tsb.toDate());
    });
  } catch (e, st) {
    debugPrint('Dashboard _loadEventosComFixos noticiasByStartAt: $e\n$st');
    try {
      final snap = await PanelProgramacaoLoader.queryCacheFirst(
        noticiasRef.limit(80),
        cacheKey: 'panel_${tid}_noticias_plain',
      );
      realDocs = snap.docs
          .where((d) => (d.data()['type'] ?? '').toString() == 'evento')
          .where((d) {
            final ts = d.data()['startAt'];
            if (ts is! Timestamp) return false;
            final dt = ts.toDate();
            return !dt.isBefore(rangeStart) && !dt.isAfter(rangeEnd);
          })
          .toList();
      realDocs.sort((a, b) {
        final tsa = a.data()['startAt'];
        final tsb = b.data()['startAt'];
        if (tsa is! Timestamp || tsb is! Timestamp) return 0;
        return tsa.toDate().compareTo(tsb.toDate());
      });
    } catch (e2, st2) {
      debugPrint('Dashboard _loadEventosComFixos noticias cache fallback: $e2\n$st2');
    }
  }

  if (apenasRotinaGerada) {
    realDocs = realDocs.where((d) {
      final data = d.data();
      if ((data['type'] ?? '').toString() != 'evento') return false;
      return noticiaEventoEhRotinaOuGeradoAutomatico(data, d.id);
    }).toList();
  }

  // Extrai foto do evento: mesma lógica do feed (evita tratar URL de vídeo como imagem).
  final realMaps = realDocs.map((d) {
    final data = d.data();
    final urls = eventNoticiaPhotoUrls(data);
    final url = urls.isNotEmpty ? urls.first : '';
    final vids = eventNoticiaVideosFromDoc(data);
    final videoUrl =
        vids.isNotEmpty ? (vids.first['videoUrl'] ?? '').toString().trim() : '';
    final storagePath =
        eventNoticiaPhotoStoragePathAt(data, 0, docIdHint: d.id)?.trim() ?? '';
    return <String, dynamic>{
      'title': data['title'],
      'startAt': data['startAt'],
      '_doc': d,
      'imageUrl': url,
      'text': (data['text'] ?? data['body'] ?? '').toString(),
      'location': (data['location'] ?? data['local'] ?? '').toString().trim(),
      'videoUrl': videoUrl,
      'photoStoragePath': storagePath,
      'docId': d.id,
    };
  }).toList();

  final realSet = <String>{};
  for (final d in realDocs) {
    final data = d.data();
    final templateId = (data['templateId'] ?? '').toString();
    if (templateId.isEmpty) continue;
    final ts = data['startAt'];
    if (ts is Timestamp) {
      final dt = ts.toDate();
      realSet.add('$templateId|${dt.millisecondsSinceEpoch}');
    }
  }

  QuerySnapshot<Map<String, dynamic>> templatesSnap =
      const MergedFirestoreQuerySnapshot([]);
  try {
    templatesSnap = await ChurchTenantResilientReads.eventTemplates(tid);
  } catch (e, st) {
    debugPrint('Dashboard _loadEventosComFixos eventTemplates: $e\n$st');
    try {
      templatesSnap = await PanelProgramacaoLoader.queryCacheFirst(
        templatesRef,
        cacheKey: 'panel_${tid}_event_templates_all',
      );
    } catch (e2, st2) {
      debugPrint('Dashboard _loadEventosComFixos eventTemplates cache fallback: $e2\n$st2');
    }
  }
  final templates = templatesSnap.docs.where((d) => d.data()['active'] != false).toList();

  final virtual = <Map<String, dynamic>>[];
  for (final t in templates) {
    final id = t.id;
    final data = t.data();
    if (!eventTemplateIncludeInAgenda(data)) continue;
    final title = (data['title'] ?? '').toString();
    if (title.isEmpty) continue;
    final photoUrls = eventNoticiaPhotoUrls(data);
    final imageUrl = photoUrls.isNotEmpty ? photoUrls.first : '';
    final vidsTpl = eventNoticiaVideosFromDoc(data);
    final videoUrlTpl =
        vidsTpl.isNotEmpty ? (vidsTpl.first['videoUrl'] ?? '').toString().trim() : '';
    final storagePathTpl = eventNoticiaPhotoStoragePathAt(data, 0)?.trim() ?? '';
    for (final dt in _expandTemplateDates(data, rangeStart, rangeEnd)) {
      final key = '$id|${dt.millisecondsSinceEpoch}';
      if (realSet.contains(key)) continue;
      virtual.add({
        'title': title,
        'startAt': Timestamp.fromDate(dt),
        'imageUrl': imageUrl,
        'text': (data['text'] ?? '').toString(),
        'location': (data['location'] ?? '').toString().trim(),
        'videoUrl': videoUrlTpl,
        'photoStoragePath': storagePathTpl,
      });
    }
  }

  final merged = <Map<String, dynamic>>[...realMaps, ...virtual];

  try {
    final agSnap = await PanelProgramacaoLoader.queryCacheFirst(
      churchRef
          .collection('agenda')
          .where('startTime',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
          .where('startTime', isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd)),
      cacheKey: 'panel_${tid}_agenda_range',
    );
    for (final d in agSnap.docs) {
      final m = d.data();
      final ts = m['startTime'];
      if (ts is! Timestamp) continue;
      merged.add({
        'title': (m['title'] ?? '').toString(),
        'startAt': ts,
        'imageUrl': '',
        'text': '',
        'location': '',
        'videoUrl': '',
        'photoStoragePath': '',
      });
    }
  } catch (e, st) {
    debugPrint('Dashboard _loadEventosComFixos agenda range: $e\n$st');
  }

  merged.sort((a, b) {
    final ta = a['startAt'] as Timestamp?;
    final tb = b['startAt'] as Timestamp?;
    if (ta == null && tb == null) return 0;
    if (ta == null) return 1;
    if (tb == null) return -1;
    return ta.compareTo(tb);
  });

  // Evita repetir o mesmo horário: um slot (ex.: domingo 09h, sexta 19h30) só aparece uma vez.
  final seenSlot = <int>{};
  final deduped = <Map<String, dynamic>>[];
  for (final m in merged) {
    final startAt = m['startAt'] as Timestamp?;
    if (startAt == null) continue;
    final ms = startAt.millisecondsSinceEpoch;
    if (seenSlot.contains(ms)) continue;
    seenSlot.add(ms);
    deduped.add({
      'title': m['title'] ?? '',
      'startAt': m['startAt'],
      'imageUrl': (m['imageUrl'] ?? '').toString().trim(),
      'text': (m['text'] ?? '').toString(),
      'location': (m['location'] ?? '').toString().trim(),
      'videoUrl': (m['videoUrl'] ?? '').toString().trim(),
      'photoStoragePath': (m['photoStoragePath'] ?? '').toString().trim(),
    });
  }
  return deduped;
}

/// Pré-aquece programação no painel (RAM + Firestore cache) — menos cartão de erro na web.
void _prewarmPanelProgramacao(String tenantId) {
  final tid = tenantId.trim();
  if (tid.isEmpty) return;
  for (final days in const [7, 15, 30]) {
    unawaited(PanelProgramacaoLoader.hydrateRamFromDisk(tid, days));
  }
  final now = DateTime.now();
  for (final days in const [7, 15, 30]) {
    unawaited(
      PanelProgramacaoLoader.loadResilient(
        tenantId: tid,
        rangeDays: days,
        loader: () => _loadEventosComFixos(
          tid,
          now,
          now.add(Duration(days: days)),
          apenasRotinaGerada: true,
        ),
      ),
    );
  }
}

void _showPainelProgramacaoEventoPreview(
  BuildContext context,
  Map<String, dynamic> data, {
  Color? accentColor,
}) {
  final accent = accentColor ?? ThemeCleanPremium.primary;
  final title = (data['title'] ?? '').toString().trim();
  final tsStartAt = data['startAt'];
  final DateTime? dt = tsStartAt is Timestamp ? tsStartAt.toDate() : null;
  const wdFull = [
    'Segunda-feira',
    'Terça-feira',
    'Quarta-feira',
    'Quinta-feira',
    'Sexta-feira',
    'Sábado',
    'Domingo',
  ];
  String two(int n) => n.toString().padLeft(2, '0');
  final dayName = (dt != null && dt.weekday >= 1 && dt.weekday <= 7)
      ? wdFull[dt.weekday - 1]
      : '';
  final time = dt != null ? '${two(dt.hour)}:${two(dt.minute)}' : '';
  final dateStr =
      dt != null ? '${two(dt.day)}/${two(dt.month)}/${dt.year}' : '';
  final loc = (data['location'] ?? '').toString().trim();
  final hasSchedule = dayName.isNotEmpty ||
      dateStr.isNotEmpty ||
      time.isNotEmpty ||
      loc.isNotEmpty;

  var imageUrl = '';
  final evUrls = eventNoticiaPhotoUrls(data);
  if (evUrls.isNotEmpty) imageUrl = evUrls.first;
  if (imageUrl.isEmpty) {
    imageUrl = sanitizeImageUrl((data['imageUrl'] ?? '').toString().trim());
  }

  var path0 = (data['photoStoragePath'] ?? '').toString().trim();
  if (path0.isEmpty) {
    path0 = eventNoticiaPhotoStoragePathAt(data, 0)?.trim() ?? '';
  }

  final body = (data['text'] ?? data['body'] ?? '').toString();
  final videoUrl = (data['videoUrl'] ?? '').toString().trim();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChurchPublicEventDetailSheet(
      title: title.isEmpty ? 'Evento' : title,
      subtitle: hasSchedule ? '' : '—',
      weekdayLabel: dayName.isEmpty ? null : dayName,
      dateLabel: dateStr.isEmpty ? null : dateStr,
      timeLabel: time.isEmpty ? null : time,
      locationLine: loc.isEmpty ? null : loc,
      body: body,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      photoStoragePath: path0.isNotEmpty ? path0 : null,
      accentColor: accent,
    ),
  );
}

/// Linha premium para programação no painel (próximos dias / eventos da semana).
class _PainelAgendaEventoRow extends StatelessWidget {
  final String title;
  final String dateStr;
  final Widget leading;
  final VoidCallback onTap;

  const _PainelAgendaEventoRow({
    required this.title,
    required this.dateStr,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  ThemeCleanPremium.primary.withValues(alpha: 0.04),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: SizedBox(width: 48, height: 48, child: leading),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          letterSpacing: -0.2,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Eventos da semana (próximos 7 dias) — cultos, atividades e eventos fixos expandidos.
/// "Ver mais" apenas estende a lista no próprio card; "Recolher" recolhe.
class _EventosSemanalCard extends StatefulWidget {
  final String tenantId;
  final String role;
  const _EventosSemanalCard({required this.tenantId, required this.role});

  static String _wd(int w) => const ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][w.clamp(0, 7)];

  @override
  State<_EventosSemanalCard> createState() => _EventosSemanalCardState();
}

class _EventosSemanalCardState extends State<_EventosSemanalCard> {
  bool _expanded = false;
  late Future<PanelProgramacaoLoadOutcome> _outcomeFuture;

  @override
  void initState() {
    super.initState();
    unawaited(PanelProgramacaoLoader.hydrateRamFromDisk(widget.tenantId, 7));
    _outcomeFuture = _loadOutcome();
  }

  void _reloadSemanal() {
    setState(() => _outcomeFuture = _loadOutcome());
  }

  Future<PanelProgramacaoLoadOutcome> _loadOutcome() {
    return PanelProgramacaoLoader.loadResilient(
      tenantId: widget.tenantId,
      rangeDays: 7,
      loader: () async {
        final now = DateTime.now();
        final end = now.add(const Duration(days: 7));
        return _loadEventosComFixos(
          widget.tenantId,
          now,
          end,
          apenasRotinaGerada: true,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CleanCard(
      title: 'Eventos',
      icon: Icons.date_range_rounded,
      child: FutureBuilder<PanelProgramacaoLoadOutcome>(
        future: _outcomeFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done || !snap.hasData) {
            final warm = PanelProgramacaoLoader.peekRam(widget.tenantId, 7);
            if (warm != null && warm.isNotEmpty) {
              return _buildEventosSemanalList(
                warm,
                staleHint: true,
                onRetry: _reloadSemanal,
              );
            }
            return const SizedBox(
              height: 120,
              child: ChurchPanelLoadingBody(),
            );
          }
          final outcome = snap.data!;
          if (outcome.showHardError) {
            return ChurchPanelResilientLoadBanner(
              hasLocalData: false,
              isSyncing: false,
              errorTitle: 'Não foi possível carregar a programação da semana',
              error: outcome.error,
              onRetry: _reloadSemanal,
            );
          }
          final items = outcome.items;
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Text('Nenhum evento nos próximos 7 dias.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            );
          }
          return _buildEventosSemanalList(
            items,
            staleHint: outcome.showSoftStaleHint,
            onRetry: _reloadSemanal,
          );
        },
      ),
    );
  }

  Widget _buildEventosSemanalList(
    List<Map<String, dynamic>> items, {
    required bool staleHint,
    required VoidCallback onRetry,
  }) {
    const int maxMostrar = 4;
    final temMais = items.length > maxMostrar;
    final mostrar = (_expanded || !temMais) ? items : items.take(maxMostrar).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (staleHint) _ProgramacaoStaleHint(onRetry: onRetry),
        ...mostrar.map((data) {
          final title = (data['title'] ?? '').toString();
          final tsStartAt = data['startAt'];
          final DateTime? dt =
              tsStartAt is Timestamp ? tsStartAt.toDate() : null;
          final dateStr = dt != null
              ? '${_EventosSemanalCard._wd(dt.weekday)} ${dt.day.toString().padLeft(2, '0')}/${dt.month} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
              : '';
          return _PainelAgendaEventoRow(
            title: title.isEmpty ? 'Evento' : title,
            dateStr: dateStr,
            leading: ColoredBox(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
              child: Icon(Icons.event_rounded, color: ThemeCleanPremium.primary, size: 22),
            ),
            onTap: () => _showPainelProgramacaoEventoPreview(context, data),
          );
        }),
        if (temMais) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.unfold_less_rounded : Icons.expand_more_rounded, size: 20),
              label: Text(_expanded ? 'Recolher' : 'Ver mais (${items.length} eventos)'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Lista em cache enquanto a rede atualiza — evita cartão vermelho no painel (estilo CT).
class _ProgramacaoStaleHint extends StatelessWidget {
  final VoidCallback onRetry;
  const _ProgramacaoStaleHint({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 18, color: Colors.blue.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sem rede agora — mostrando a última programação salva. Toque para atualizar.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade900, height: 1.25),
                  ),
                ),
                Icon(Icons.refresh_rounded, size: 18, color: Colors.blue.shade700),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Onboarding curto para quem lidera departamentos / escalas (uma vez, dispensável).
/// Visual Super Premium (gradiente + cartão sólido) — sem ActionChip «claro».
class _DashboardLiderOnboardingBanner extends StatefulWidget {
  final String role;
  final bool? podeVerFinanceiro;
  final bool? podeVerPatrimonio;
  final List<String>? permissions;
  final ValueChanged<int> onNavigateToShellModule;

  const _DashboardLiderOnboardingBanner({
    required this.role,
    required this.podeVerFinanceiro,
    required this.podeVerPatrimonio,
    required this.permissions,
    required this.onNavigateToShellModule,
  });

  @override
  State<_DashboardLiderOnboardingBanner> createState() =>
      _DashboardLiderOnboardingBannerState();
}

class _DashboardLiderOnboardingBannerState
    extends State<_DashboardLiderOnboardingBanner> {
  static const _prefKey = 'church_dashboard_lider_onboarding_v1_dismissed';
  bool _loading = true;
  bool _dismissed = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _dismissed = p.getBool(_prefKey) == true;
        _loading = false;
      });
    });
  }

  bool get _eligible {
    if (AppPermissions.isRestrictedMember(widget.role)) return false;
    final s = ChurchRolePermissions.snapshotFor(widget.role);
    return s.editDepartments || s.editSchedulesAll;
  }

  Future<void> _dismiss() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefKey, true);
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _dismissed || !_eligible) return const SizedBox.shrink();

    Widget premiumStep({
      required IconData icon,
      required String label,
      required int shellIndex,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => widget.onNavigateToShellModule(shellIndex),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: churchChatWhatsPremiumLinearGradient,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Colors.white,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final steps = <Widget>[];
    if (ChurchRolePermissions.shellAllowsNavIndex(
      widget.role,
      3,
      memberCanViewFinance: widget.podeVerFinanceiro,
      memberCanViewPatrimonio: widget.podeVerPatrimonio,
      permissions: widget.permissions,
    )) {
      steps.add(
        premiumStep(
          icon: Icons.groups_rounded,
          label: '1. Departamentos',
          shellIndex: 3,
        ),
      );
    }
    if (ChurchRolePermissions.shellAllowsNavIndex(
      widget.role,
      11,
      memberCanViewFinance: widget.podeVerFinanceiro,
      memberCanViewPatrimonio: widget.podeVerPatrimonio,
      permissions: widget.permissions,
    )) {
      steps.add(
        premiumStep(
          icon: Icons.event_available_rounded,
          label: '2. Escala geral',
          shellIndex: 11,
        ),
      );
    }
    if (ChurchRolePermissions.shellAllowsNavIndex(
      widget.role,
      2,
      memberCanViewFinance: widget.podeVerFinanceiro,
      memberCanViewPatrimonio: widget.podeVerPatrimonio,
      permissions: widget.permissions,
    )) {
      steps.add(
        premiumStep(
          icon: Icons.people_rounded,
          label: '3. Membros / convites',
          shellIndex: ChurchShellIndices.membros,
        ),
      );
    }
    if (steps.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
          width: 1.15,
        ),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: churchChatWhatsPremiumLinearGradient,
                  boxShadow: [
                    BoxShadow(
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.flag_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Primeiros passos na gestão',
                      style: TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.35,
                        color: ThemeCleanPremium.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Atalhos rápidos para o gestor e a equipa organizarem ministério e escala.',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Não mostrar de novo',
                onPressed: _dismiss,
                icon: Icon(
                  Icons.close_rounded,
                  color: ThemeCleanPremium.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: steps,
          ),
        ],
      ),
    );
  }
}

/// Atalho para Minha escala + destaque de convites de troca pendentes.
class _DashboardVoluntariadoAtalhoCard extends StatelessWidget {
  final String tenantId;
  final String cpf;
  final String role;
  final bool? podeVerFinanceiro;
  final bool? podeVerPatrimonio;
  final List<String>? permissions;
  final VoidCallback onOpenMinhaEscala;

  const _DashboardVoluntariadoAtalhoCard({
    required this.tenantId,
    required this.cpf,
    required this.role,
    required this.podeVerFinanceiro,
    required this.podeVerPatrimonio,
    required this.permissions,
    required this.onOpenMinhaEscala,
  });

  String get _cpfDigits {
    var d = cpf.replaceAll(RegExp(r'\D'), '');
    if (d.length == 10) d = '0$d';
    return d;
  }

  @override
  Widget build(BuildContext context) {
    if (!ChurchRolePermissions.shellAllowsNavIndex(
      role,
      kChurchShellIndexMySchedules,
      memberCanViewFinance: podeVerFinanceiro,
      memberCanViewPatrimonio: podeVerPatrimonio,
      permissions: permissions,
    )) {
      return const SizedBox.shrink();
    }
    final tid = tenantId.trim();
    if (tid.isEmpty) return const SizedBox.shrink();

    Widget incomingBadge = const SizedBox.shrink();
    if (_cpfDigits.length == 11) {
      incomingBadge = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream:             ChurchUiCollections.churchDoc(tid)
            .collection('escala_trocas')
            .where('alvoCpf', isEqualTo: _cpfDigits)
            .watchSafe(),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final n = snap.data!.docs
              .where((d) => (d.data()['status'] ?? '').toString() == 'pendente_alvo')
              .length;
          if (n == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(Icons.mail_outline_rounded, size: 18, color: Colors.deepPurple.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$n convite(s) de troca aguardando sua resposta',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.deepPurple.shade900,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(color: Color(0x0A000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.calendar_today_rounded, color: ThemeCleanPremium.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Minha escala — hoje e próximos dias',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.blueGrey.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Confirme presença, peça troca e responda convites em um só lugar.',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            incomingBadge,
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onOpenMinhaEscala,
                icon: const Icon(Icons.touch_app_rounded, size: 20),
                label: const Text('Abrir Minha escala'),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusSm),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Programação por período (7, 15 e 30 dias), com lista clicável.
class _ProgramacaoDiasCard extends StatefulWidget {
  final String tenantId;
  final String role;
  const _ProgramacaoDiasCard({required this.tenantId, required this.role});

  static String _wd(int w) => const ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'][w.clamp(0, 7)];

  @override
  State<_ProgramacaoDiasCard> createState() => _ProgramacaoDiasCardState();
}

class _ProgramacaoDiasCardState extends State<_ProgramacaoDiasCard> {
  bool _expanded = false;
  int _selectedDays = 7;
  late Future<PanelProgramacaoLoadOutcome> _outcomeFuture;

  @override
  void initState() {
    super.initState();
    unawaited(PanelProgramacaoLoader.hydrateRamFromDisk(widget.tenantId, 7));
    _outcomeFuture = _loadOutcome();
  }

  @override
  void didUpdateWidget(covariant _ProgramacaoDiasCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      unawaited(PanelProgramacaoLoader.hydrateRamFromDisk(widget.tenantId, _selectedDays));
      _outcomeFuture = _loadOutcome();
    }
  }

  void _reloadProgramacao() {
    setState(() => _outcomeFuture = _loadOutcome());
  }

  Future<PanelProgramacaoLoadOutcome> _loadOutcome() {
    return PanelProgramacaoLoader.loadResilient(
      tenantId: widget.tenantId,
      rangeDays: _selectedDays,
      loader: () async {
        final now = DateTime.now();
        final end = now.add(Duration(days: _selectedDays));
        return _loadEventosComFixos(
          widget.tenantId,
          now,
          end,
          apenasRotinaGerada: true,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _CleanCard(
      title: 'Próximos dias (agenda + cultos)',
      icon: Icons.calendar_month_rounded,
      child: FutureBuilder<PanelProgramacaoLoadOutcome>(
        future: _outcomeFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done || !snap.hasData) {
            final warm =
                PanelProgramacaoLoader.peekRam(widget.tenantId, _selectedDays);
            if (warm != null && warm.isNotEmpty) {
              return _buildProgramacaoDiasBody(
                warm,
                staleHint: true,
                onRetry: _reloadProgramacao,
              );
            }
            return const SizedBox(
              height: 120,
              child: ChurchPanelLoadingBody(),
            );
          }
          final outcome = snap.data!;
          if (outcome.showHardError) {
            return ChurchPanelResilientLoadBanner(
              hasLocalData: false,
              isSyncing: false,
              errorTitle: 'Não foi possível carregar a programação',
              error: outcome.error,
              onRetry: _reloadProgramacao,
            );
          }
          final items = outcome.items;
          if (items.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [7, 15, 30].map((days) {
                    final selected = _selectedDays == days;
                    return ChurchPanelPeriodDaysChip(
                      days: days,
                      selected: selected,
                      onTap: () {
                        unawaited(
                          PanelProgramacaoLoader.hydrateRamFromDisk(
                            widget.tenantId,
                            days,
                          ),
                        );
                        setState(() {
                          _selectedDays = days;
                          _outcomeFuture = _loadOutcome();
                        });
                      },
                    );
                  }).toList(),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Nenhum evento nos próximos $_selectedDays dias.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                ),
              ],
            );
          }
          return _buildProgramacaoDiasBody(
            items,
            staleHint: outcome.showSoftStaleHint,
            onRetry: _reloadProgramacao,
          );
        },
      ),
    );
  }

  Widget _buildProgramacaoDiasBody(
    List<Map<String, dynamic>> items, {
    required bool staleHint,
    required VoidCallback onRetry,
  }) {
    const int maxMostrar = 4;
    final temMais = items.length > maxMostrar;
    final mostrar = (_expanded || !temMais) ? items : items.take(maxMostrar).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [7, 15, 30].map((days) {
              final selected = _selectedDays == days;
              return ChurchPanelPeriodDaysChip(
                days: days,
                selected: selected,
                onTap: () {
                  unawaited(
                    PanelProgramacaoLoader.hydrateRamFromDisk(
                      widget.tenantId,
                      days,
                    ),
                  );
                  setState(() {
                    _selectedDays = days;
                    _outcomeFuture = _loadOutcome();
                  });
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        if (staleHint) _ProgramacaoStaleHint(onRetry: onRetry),
        ...mostrar.map((data) {
          final title = (data['title'] ?? '').toString();
          final evUrls = eventNoticiaPhotoUrls(data);
          var imageUrl = evUrls.isNotEmpty ? evUrls.first : '';
          if (imageUrl.isEmpty) {
            final u = (data['imageUrl'] ?? '').toString().trim();
            if (u.isNotEmpty) imageUrl = sanitizeImageUrl(u);
          }
          final path0 = () {
            final fromMap = (data['photoStoragePath'] ?? '').toString().trim();
            if (fromMap.isNotEmpty) return fromMap;
            final docId = (data['docId'] ?? '').toString().trim();
            return eventNoticiaPhotoStoragePathAt(
                  data,
                  0,
                  docIdHint: docId.isNotEmpty ? docId : null,
                )?.trim() ??
                '';
          }();
          final hasPhoto =
              imageUrl.isNotEmpty || path0.isNotEmpty;
          final tsStartAt = data['startAt'];
          final DateTime? dt =
              tsStartAt is Timestamp ? tsStartAt.toDate() : null;
          final dateStr = dt != null
              ? '${_ProgramacaoDiasCard._wd(dt.weekday)} ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
              : '';
          final leadingWidget = hasPhoto
              ? StableStorageImage(
                  storagePath: path0,
                  imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  placeholder: ColoredBox(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                    child: Icon(Icons.event_rounded, color: ThemeCleanPremium.primary, size: 22),
                  ),
                  errorWidget: ColoredBox(
                    color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                    child: Icon(Icons.event_rounded, color: ThemeCleanPremium.primary, size: 22),
                  ),
                )
              : ColoredBox(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.event_rounded, color: ThemeCleanPremium.primary, size: 22),
                );
          return _PainelAgendaEventoRow(
            title: title.isEmpty ? 'Evento' : title,
            dateStr: dateStr,
            leading: leadingWidget,
            onTap: () => _showPainelProgramacaoEventoPreview(context, data),
          );
        }),
        if (temMais) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.unfold_less_rounded : Icons.expand_more_rounded, size: 20),
              label: Text(_expanded ? 'Recolher' : 'Veja mais (${items.length} eventos)'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shadowColor: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Fotos reais no destaque do painel — não duplica a miniatura do vídeo como "foto" extra.
List<String> _painelDestaqueGalleryPhotos(Map<String, dynamic> d) {
  final raw = yahwehPostGalleryRefs(d);
  final t1 = sanitizeImageUrl(eventNoticiaDisplayVideoThumbnailUrl(d) ?? '');
  final t2 = sanitizeImageUrl(eventNoticiaVideoThumbUrl(d) ?? '');
  bool dup(String s) {
    final x = sanitizeImageUrl(s);
    if (x.isEmpty) return false;
    if (t1.isNotEmpty && x == t1) return true;
    if (t2.isNotEmpty && x == t2) return true;
    return false;
  }
  return raw.where((s) => !dup(s)).toList();
}

/// Carrossel estilo Instagram no Painel — fotos (paths Storage) + vídeo embutido (web) ou miniatura + play.
class _PainelDestaqueMediaCarousel extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;
  final bool isEvento;
  final String title;
  /// Toque numa foto: ampliar (site público), sem abrir tela cheia ao tocar no card inteiro.
  final void Function(int photoIndex)? onGalleryPhotoTap;
  /// Dois toques na foto: curtir (estilo Instagram).
  final Future<void> Function()? onLikeDoubleTap;
  /// Altura do cartão no painel segue o slide atual (site público).
  final ValueChanged<int>? onCarouselPageChanged;
  /// Ação rápida para abrir álbum completo (quando houver várias fotos).
  final VoidCallback? onOpenAlbumTap;

  const _PainelDestaqueMediaCarousel({
    required this.data,
    required this.docId,
    required this.isEvento,
    required this.title,
    this.onGalleryPhotoTap,
    this.onLikeDoubleTap,
    this.onCarouselPageChanged,
    this.onOpenAlbumTap,
  });

  @override
  State<_PainelDestaqueMediaCarousel> createState() =>
      _PainelDestaqueMediaCarouselState();
}

Widget _painelDestaqueVideoThumbWidget({
  required String thumb,
  required String title,
  required bool isEvento,
}) {
  final t = thumb;
  final ph = _DestaqueCard._gradientBanner(title, isEvento);
  final storageLike =
      isFirebaseStorageHttpUrl(t) || firebaseStorageMediaUrlLooksLike(t);
  if (storageLike) {
    return ColoredBox(
      color: const Color(0xFFF1F5F9),
      child: FreshFirebaseStorageImage(
        imageUrl: t,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: 520,
        memCacheHeight: 400,
        placeholder: ph,
        errorWidget: ph,
      ),
    );
  }
  return ColoredBox(
    color: const Color(0xFFF1F5F9),
    child: SafeNetworkImage(
      imageUrl: t,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: 520,
      memCacheHeight: 400,
      skipFreshDisplayUrl: false,
      placeholder: ph,
      errorWidget: ph,
    ),
  );
}

class _PainelDestaqueMediaCarouselState
    extends State<_PainelDestaqueMediaCarousel> {
  late final PageController _pageCtrl;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  static bool _isYoutubeVimeo(String u) {
    final low = u.toLowerCase();
    return low.contains('youtube.com') ||
        low.contains('youtu.be') ||
        low.contains('vimeo.com');
  }

  String? _panelVideoOpenUrl(Map<String, dynamic> d) {
    final hosted = sanitizeImageUrl(eventNoticiaHostedVideoPlayUrl(d) ?? '');
    if (hosted.isNotEmpty && eventNoticiaUrlEligibleForHostedInlinePlayer(hosted)) {
      return hosted;
    }
    final ext = eventNoticiaExternalVideoUrl(d);
    if (ext != null && ext.isNotEmpty) return ext;
    final leg = (d['videoUrl'] ?? '').toString().trim();
    if (leg.isNotEmpty) return leg;
    return null;
  }

  Future<void> _openVideo(String openUrl, String? thumb,
      {String title = ''}) async {
    if (openUrl.isEmpty) return;
    if (_isYoutubeVimeo(openUrl)) {
      final withScheme = openUrl.startsWith('http://') ||
              openUrl.startsWith('https://')
          ? openUrl
          : 'https://$openUrl';
      final uri = Uri.tryParse(withScheme);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final hosted = looksLikeHostedVideoFileUrl(openUrl) ||
        openUrl.contains('firebasestorage.googleapis.com') ||
        openUrl.contains('.firebasestorage.app');
    if (hosted) {
      if (!mounted) return;
      final th = thumb != null && isValidImageUrl(thumb) ? thumb : null;
      await showChurchHostedVideoDialog(
        context,
        videoUrl: openUrl,
        thumbnailUrl: th,
        autoPlay: true,
        title: title,
      );
      return;
    }
    final withScheme =
        openUrl.startsWith('http://') || openUrl.startsWith('https://')
            ? openUrl
            : 'https://$openUrl';
    final uri = Uri.tryParse(withScheme);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final refs = _painelDestaqueGalleryPhotos(d);
    final vOpen = _panelVideoOpenUrl(d);
    // Vídeo como último slide do carrossel (fotos + vídeo — igual ao feed de eventos).
    final videoSlide = vOpen != null && vOpen.isNotEmpty;
    final n = refs.length + (videoSlide ? 1 : 0);
    if (n == 0) {
      return _DestaqueCard._gradientBanner(widget.title, widget.isEvento);
    }

    final thumbRaw = eventNoticiaDisplayVideoThumbnailUrl(d) ?? '';
    var thumb = sanitizeImageUrl(thumbRaw);
    if (!isValidImageUrl(thumb)) {
      final yt = _DestaqueCard._videoThumbnailUrl(d);
      thumb = yt != null ? sanitizeImageUrl(yt) : '';
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageCtrl,
          onPageChanged: (p) {
            setState(() => _page = p);
            widget.onCarouselPageChanged?.call(p);
          },
          itemCount: n,
          itemBuilder: (ctx, idx) {
            if (idx < refs.length) {
              return LayoutBuilder(
                builder: (ctx2, bc) {
                  final w = bc.maxWidth.isFinite && bc.maxWidth > 0
                      ? bc.maxWidth
                      : 400.0;
                  final h = bc.maxHeight.isFinite && bc.maxHeight > 0
                      ? bc.maxHeight
                      : 400.0;
                  final dpr = MediaQuery.devicePixelRatioOf(ctx2);
                  final memW = (w * dpr).round().clamp(64, 1200);
                  final memH = (h * dpr).round().clamp(64, 1200);
                  final pathFs = eventNoticiaPhotoStoragePathAt(
                    d,
                    idx,
                    docIdHint: widget.docId,
                  );
                  final ps = _painelDestaqueStableParamsFromRef(refs[idx]);
                  // Path derivado do próprio ref tem prioridade — evita misturar imageStoragePaths[0] com foto[1].
                  final spMerged = (ps.storagePath != null &&
                          ps.storagePath!.trim().isNotEmpty)
                      ? ps.storagePath
                      : pathFs;
                  final img = ColoredBox(
                    color: const Color(0xFFF1F5F9),
                    child: StableStorageImage(
                      key: ValueKey('painel_ph_${idx}_${refs[idx]}'),
                      storagePath: spMerged,
                      imageUrl: ps.imageUrl,
                      gsUrl: ps.gsUrl,
                      width: w,
                      height: h,
                      fit: BoxFit.contain,
                      memCacheWidth: memW,
                      memCacheHeight: memH,
                      skipFreshDisplayUrl: true,
                      placeholder: Center(
                        child: Icon(
                          Icons.photo_outlined,
                          size: 36,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      errorWidget: _DestaqueCard._gradientBanner(
                          widget.title, widget.isEvento),
                    ),
                  );
                  final tap = widget.onGalleryPhotoTap;
                  final like = widget.onLikeDoubleTap;
                  Widget wrapped = img;
                  if (tap != null) {
                    wrapped = GestureDetector(
                      onTap: () => tap(idx),
                      onDoubleTap:
                          like == null ? null : () => unawaited(like()),
                      behavior: HitTestBehavior.opaque,
                      child: img,
                    );
                  } else if (like != null) {
                    wrapped = GestureDetector(
                      onDoubleTap: () => unawaited(like()),
                      behavior: HitTestBehavior.opaque,
                      child: img,
                    );
                  }
                  return SizedBox(width: w, height: h, child: wrapped);
                },
              );
            }
            final vTap = vOpen;
            final inlineHosted = vTap != null &&
                vTap.isNotEmpty &&
                !_isYoutubeVimeo(vTap) &&
                eventNoticiaUrlEligibleForHostedInlinePlayer(vTap);
            if (inlineHosted) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: ColoredBox(
                  color: Colors.black,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ChurchHostedVideoSurface(
                      videoUrl: sanitizeImageUrl(vTap),
                      thumbnailUrl:
                          isValidImageUrl(thumb) ? thumb : null,
                      autoPlay: false,
                      showFullscreenOverlay: true,
                    ),
                  ),
                ),
              );
            }
            return GestureDetector(
              onTap: () {
                if (vTap == null) return;
                _openVideo(vTap, isValidImageUrl(thumb) ? thumb : null,
                    title: widget.title);
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (isValidImageUrl(thumb))
                    _painelDestaqueVideoThumbWidget(
                      thumb: thumb,
                      title: widget.title,
                      isEvento: widget.isEvento,
                    )
                  else
                    _DestaqueCard._gradientBanner(
                        widget.title, widget.isEvento),
                  Container(color: Colors.black26),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 36),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (n > 1) ...[
          Positioned(
            bottom: 6,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                n,
                (i) => Container(
                  width: i == _page ? 7 : 5,
                  height: i == _page ? 7 : 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i == _page ? Colors.white : Colors.white54,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                          color: Colors.black26, blurRadius: 2, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_page + 1}/$n',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (refs.length > 1 && widget.onOpenAlbumTap != null)
            Positioned(
              top: 34,
              right: 6,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onOpenAlbumTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: const Text(
                      'Ver todas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

Future<void> _painelDestaqueToggleLike(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  String tenantId,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.feedbackSnackBar('Entre na conta para curtir.'),
    );
    return;
  }
  final data = doc.data();
  final merged = NoticiaSocialService.mergedLikeUids(data);
  final liked = merged.contains(uid);
  try {
    var name = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    var photo = FirebaseAuth.instance.currentUser?.photoURL?.trim() ?? '';
    if (name.isEmpty) {
      try {
        if (kIsWeb) {
          await FirestoreWebGuard.ensurePanelReadReady().catchError((e, st) {
            debugPrint(
              'Dashboard _painelDestaqueToggleLike ensurePanelReadReady: $e\n$st',
            );
          });
        }
        Future<DocumentSnapshot<Map<String, dynamic>>> readUser() =>
            firebaseDefaultFirestore.collection('users').doc(uid).get();
        final uDoc = kIsWeb
            ? await FirestoreWebGuard.runWithWebRecovery(
                readUser,
                maxAttempts: 4,
              ).timeout(PanelResilientLoad.queryCap)
            : await readUser().timeout(PanelResilientLoad.queryCap);
        final u = uDoc.data() ?? {};
        name = (u['nome'] ?? u['name'] ?? 'Membro').toString();
        photo = (u['fotoUrl'] ?? u['photoUrl'] ?? photo).toString();
      } catch (e, st) {
        debugPrint('Dashboard _painelDestaqueToggleLike load user: $e\n$st');
        name = 'Membro';
      }
    }
    await NoticiaSocialService.toggleCurtida(
      tenantId: tenantId,
      postId: doc.id,
      uid: uid,
      memberName: name.isEmpty ? 'Membro' : name,
      photoUrl: photo,
      currentlyLiked: liked,
      parentCollection:
          ChurchTenantPostsCollections.segmentFromPostRef(doc.reference),
    );
  } catch (e, st) {
    debugPrint('Dashboard _painelDestaqueToggleLike: $e\n$st');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Não foi possível curtir agora.'),
      );
    }
  }
}

void _openPainelDestaqueFotoAmpliar(
  BuildContext context, {
  required List<String> galleryRefs,
  required Map<String, dynamic> data,
  required String title,
  required bool isEvento,
  required int photoIndex,
}) {
  if (photoIndex < 0 || photoIndex >= galleryRefs.length) return;
  final u = sanitizeImageUrl(galleryRefs[photoIndex]);
  if (isValidImageUrl(u)) {
    unawaited(showYahwehFullscreenZoomableImage(context, imageUrl: u));
    return;
  }
  Navigator.push(
    context,
    ThemeCleanPremium.fadeSlideRoute(
      NoticiaPhotoGalleryPage(
        imageRefs: galleryRefs,
        firestoreData: data,
        title: title,
        isEvento: isEvento,
        initialIndex: photoIndex,
      ),
    ),
  );
}

class _DestaqueCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String tenantId;
  final String role;
  final String churchSlug;
  final String nomeIgreja;
  const _DestaqueCard({
    required this.doc,
    required this.tenantId,
    required this.role,
    required this.churchSlug,
    required this.nomeIgreja,
  });

  @override
  State<_DestaqueCard> createState() => _DestaqueCardState();

  /// Área de imagem do card: [StableStorageImage] (path + URL renováveis), thumb de vídeo com token fresco, gradiente.
  static Widget _DestaqueCardImage({
    required String displayImageUrl,
    required String? storagePath,
    String? gsUrl,
    required String? videoThumbUrl,
    required bool hasVideo,
    required bool firstImgEmpty,
    required String title,
    required bool isEvento,
    VoidCallback? onMediaTap,
    VoidCallback? onDoubleTapMedia,
  }) {
    Widget wrapTap(Widget w) {
      if (onMediaTap == null && onDoubleTapMedia == null) return w;
      return GestureDetector(
        onTap: onMediaTap,
        onDoubleTap: onDoubleTapMedia,
        behavior: HitTestBehavior.opaque,
        child: w,
      );
    }
    final gradientFallback = _gradientBanner(title, isEvento);
    final ph = ColoredBox(
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ThemeCleanPremium.primary.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
    final g = gsUrl?.trim();
    final hasStableSource = displayImageUrl.isNotEmpty ||
        (storagePath?.trim().isNotEmpty ?? false) ||
        (g != null && g.isNotEmpty);

    if (hasStableSource) {
      return wrapTap(
        Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 320.0;
                final h = c.maxHeight.isFinite && c.maxHeight > 0 ? c.maxHeight : 160.0;
                final dpr = MediaQuery.devicePixelRatioOf(context);
                final memW = (w * dpr).round().clamp(64, 1024);
                final memH = (h * dpr).round().clamp(64, 640);
                final sp = storagePath?.trim();
                return ColoredBox(
                  color: const Color(0xFFF1F5F9),
                  child: StableStorageImage(
                    key: ValueKey('dest_${sp}_${g}_$displayImageUrl'),
                    storagePath: (sp != null && sp.isNotEmpty) ? sp : null,
                    imageUrl: displayImageUrl.isNotEmpty ? displayImageUrl : null,
                    gsUrl: (g != null && g.isNotEmpty) ? g : null,
                    width: w,
                    height: h,
                    fit: BoxFit.contain,
                    memCacheWidth: memW,
                    memCacheHeight: memH,
                    skipFreshDisplayUrl: true,
                    placeholder: ph,
                    errorWidget: videoThumbUrl != null && videoThumbUrl.isNotEmpty
                        ? FreshFirebaseStorageImage(
                            key: ValueKey('fallback_$videoThumbUrl'),
                            imageUrl: videoThumbUrl,
                            fit: BoxFit.contain,
                            width: w,
                            height: h,
                            memCacheWidth: memW,
                            memCacheHeight: memH,
                            placeholder: gradientFallback,
                            errorWidget: gradientFallback,
                          )
                        : gradientFallback,
                  ),
                );
              },
            ),
            if (hasVideo && firstImgEmpty)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                ),
              ),
          ],
        ),
      );
    }
    if (displayImageUrl.isEmpty) {
      return wrapTap(
        Stack(
          fit: StackFit.expand,
          children: [
            videoThumbUrl != null && videoThumbUrl.isNotEmpty
                ? LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth.isFinite && c.maxWidth > 0 ? c.maxWidth : 320.0;
                      final h = c.maxHeight.isFinite && c.maxHeight > 0 ? c.maxHeight : 160.0;
                      final dpr = MediaQuery.devicePixelRatioOf(context);
                      return ColoredBox(
                        color: const Color(0xFFF1F5F9),
                        child: FreshFirebaseStorageImage(
                          key: ValueKey(videoThumbUrl),
                          imageUrl: videoThumbUrl,
                          fit: BoxFit.contain,
                          width: w,
                          height: h,
                          memCacheWidth: (w * dpr).round().clamp(64, 1024),
                          memCacheHeight: (h * dpr).round().clamp(64, 640),
                          placeholder: ph,
                          errorWidget: gradientFallback,
                        ),
                      );
                    },
                  )
                : gradientFallback,
            if (hasVideo)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                ),
              ),
          ],
        ),
      );
    }
    return wrapTap(gradientFallback);
  }

  static Widget _gradientBanner(String title, bool isEvento) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEvento
              ? [
                  const Color(0xFF0C4A6E),
                  ThemeCleanPremium.primary,
                  const Color(0xFF38BDF8),
                ]
              : [
                  const Color(0xFF312E81),
                  const Color(0xFF4F46E5),
                  const Color(0xFF818CF8),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: -24,
            bottom: -40,
            child: Icon(
              isEvento ? Icons.event_rounded : Icons.campaign_rounded,
              size: 140,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isEvento
                      ? Icons.event_available_rounded
                      : Icons.notifications_active_rounded,
                  color: Colors.white.withValues(alpha: 0.92),
                  size: 38,
                ),
                if (title.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.96),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thumbnail para vídeo (YouTube ou Vimeo) quando não há imagem.
  static String? _videoThumbnailUrl(Map<String, dynamic> data) {
    final videoUrl = (data['videoUrl'] ?? '').toString().trim();
    if (videoUrl.isEmpty) return null;
    // YouTube: watch?v=ID ou youtu.be/ID
    final ytMatch = RegExp(r'(?:youtube\.com/watch\?v=|youtu\.be/)([a-zA-Z0-9_-]{11})').firstMatch(videoUrl);
    if (ytMatch != null) return 'https://img.youtube.com/vi/${ytMatch.group(1)}/mqdefault.jpg';
    // Vimeo: vimeo.com/ID
    final vimeoMatch = RegExp(r'vimeo\.com/(?:video/)?(\d+)').firstMatch(videoUrl);
    if (vimeoMatch != null) return 'https://vumbnail.com/${vimeoMatch.group(1)}.jpg';
    return null;
  }
}

class _DestaqueCardState extends State<_DestaqueCard> {
  int _carouselPage = 0;

  @override
  void didUpdateWidget(covariant _DestaqueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      _carouselPage = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    if (!PanelFeedPostValidator.isRenderableForPanelFeed(
      data,
      docId: widget.doc.id,
      churchId: widget.tenantId,
    )) {
      return const SizedBox.shrink();
    }
    final title = PanelFeedPostValidator.resolveTitle(data);
    final text = (data['text'] ?? '').toString();
    final type = (data['type'] ?? 'aviso').toString();
    final fromAvisosCol = ChurchTenantPostsCollections.segmentFromPostRef(
            widget.doc.reference) ==
        ChurchTenantPostsCollections.avisos;
    final galleryRefs = yahwehPostGalleryRefs(data);
    var galleryPhotos = _painelDestaqueGalleryPhotos(data);
    if (galleryPhotos.isEmpty) {
      final sp = eventNoticiaPhotoStoragePathAt(
        data,
        0,
        docIdHint: widget.doc.id,
        churchIdHint: widget.tenantId,
      );
      if (sp != null && sp.isNotEmpty) {
        galleryPhotos = [sp];
      }
    }
    var firstImg = '';
    for (final raw in galleryRefs) {
      final s = sanitizeImageUrl(raw);
      if (isValidImageUrl(s) ||
          s.toLowerCase().startsWith('gs://') ||
          firebaseStorageMediaUrlLooksLike(s)) {
        firstImg = s;
        break;
      }
    }
    if (firstImg.isEmpty && galleryRefs.isNotEmpty) {
      firstImg = sanitizeImageUrl(galleryRefs.first);
    }
    final youtubeThumb = _DestaqueCard._videoThumbnailUrl(data);
    final firebaseVideoThumb = eventNoticiaVideoThumbUrl(data);
    final displayThumbAll = eventNoticiaDisplayVideoThumbnailUrl(data);
    final videoThumbRaw = youtubeThumb ?? firebaseVideoThumb ?? displayThumbAll;
    final videoThumb = videoThumbRaw != null && videoThumbRaw.isNotEmpty ? sanitizeImageUrl(videoThumbRaw) : null;
    final videoUrl = (data['videoUrl'] ?? '').toString().trim();
    final vids = eventNoticiaVideosFromDoc(data);
    final primaryPhotoUrl = firstImg.isNotEmpty &&
            (isValidImageUrl(firstImg) ||
                firstImg.toLowerCase().startsWith('gs://') ||
                firebaseStorageMediaUrlLooksLike(firstImg))
        ? firstImg
        : '';
    final storagePathPrimary = eventNoticiaPhotoStoragePathAt(
          data,
          0,
          docIdHint: widget.doc.id,
          churchIdHint: widget.tenantId,
        ) ??
        eventNoticiaImageStoragePath(data);
    final hasVideo = vids.isNotEmpty ||
        videoUrl.isNotEmpty ||
        (displayThumbAll != null && displayThumbAll.isNotEmpty);
    final panelVideoUrl = () {
      final h = sanitizeImageUrl(eventNoticiaHostedVideoPlayUrl(data) ?? '');
      if (h.isNotEmpty && eventNoticiaUrlEligibleForHostedInlinePlayer(h)) return h;
      final ext = eventNoticiaExternalVideoUrl(data);
      if (ext != null && ext.isNotEmpty) return ext;
      if (videoUrl.isNotEmpty) return videoUrl;
      return '';
    }();
    final hasPanelVideoSlide = panelVideoUrl.isNotEmpty;
    final slideCount =
        galleryPhotos.length + (hasPanelVideoSlide ? 1 : 0);
    final showCarousel = slideCount > 0;
    DateTime? dt;
    final startAtTs = data['startAt'];
    if (startAtTs is Timestamp) {
      dt = startAtTs.toDate();
    } else {
      final createdAtTs = data['createdAt'];
      if (createdAtTs is Timestamp) {
        dt = createdAtTs.toDate();
      }
    }
    final dateStr = dt != null ? '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}' : '';
    final timeStr = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';
    final isEvento = !fromAvisosCol && type == 'evento';

    String? gsForStable;
    var pathForStable = storagePathPrimary;
    var urlForStable = primaryPhotoUrl;
    if (galleryRefs.isNotEmpty) {
      final r0 = sanitizeImageUrl(galleryRefs.first);
      if (r0.isNotEmpty) {
        if (r0.toLowerCase().startsWith('gs://')) {
          gsForStable = r0;
        } else if (!isValidImageUrl(r0) && firebaseStorageMediaUrlLooksLike(r0)) {
          pathForStable ??= normalizeFirebaseStorageObjectPath(
              r0.replaceFirst(RegExp(r'^/+'), ''));
        } else if (isValidImageUrl(r0) && urlForStable.isEmpty) {
          urlForStable = r0;
        }
      }
    }
    final openModulo = () {
      Navigator.push(
        context,
        ThemeCleanPremium.fadeSlideRoute(
          isEvento
              ? EventsManagerPage(tenantId: widget.tenantId, role: widget.role)
              : MuralPage(tenantId: widget.tenantId, role: widget.role),
        ),
      );
    };
    final tapMediaAmpliar = !showCarousel && !hasVideo
        ? () {
            final refs = galleryRefs.isNotEmpty
                ? List<String>.from(galleryRefs)
                : <String>[
                    if (primaryPhotoUrl.isNotEmpty) primaryPhotoUrl,
                  ];
            if (refs.isEmpty &&
                (storagePathPrimary == null ||
                    storagePathPrimary.trim().isEmpty)) {
              return;
            }
            if (refs.isEmpty) refs.add('');
            _openPainelDestaqueFotoAmpliar(
              context,
              galleryRefs: refs,
              data: data,
              title: title,
              isEvento: isEvento,
              photoIndex: 0,
            );
          }
        : null;

    final nPhotosForAr = showCarousel
        ? galleryPhotos.length
        : ((primaryPhotoUrl.isNotEmpty ||
                (storagePathPrimary?.trim().isNotEmpty ?? false))
            ? 1
            : 0);
    final denomPhotos = nPhotosForAr > 0 ? nPhotosForAr : 1;

    final panelW = MediaQuery.sizeOf(context).width;
    final useWebSplit =
        kIsWeb && panelW >= _kPainelDestaqueWebSplitMinWidth;
    final layoutWide = panelW >= 620;
    final carouselOrImage = showCarousel
        ? _PainelDestaqueMediaCarousel(
            data: data,
            docId: widget.doc.id,
            isEvento: isEvento,
            title: title,
            onGalleryPhotoTap: galleryPhotos.isEmpty
                ? null
                : (i) => _openPainelDestaqueFotoAmpliar(
                      context,
                      galleryRefs: galleryPhotos,
                      data: data,
                      title: title,
                      isEvento: isEvento,
                      photoIndex: i,
                    ),
            onLikeDoubleTap: () =>
                _painelDestaqueToggleLike(context, widget.doc, widget.tenantId),
            onCarouselPageChanged:
                (i) => setState(() => _carouselPage = i),
            onOpenAlbumTap: galleryPhotos.length > 1
                ? () => _openPainelDestaqueFotoAmpliar(
                      context,
                      galleryRefs: galleryPhotos,
                      data: data,
                      title: title,
                      isEvento: isEvento,
                      photoIndex: 0,
                    )
                : null,
          )
        : _DestaqueCard._DestaqueCardImage(
            displayImageUrl: urlForStable,
            storagePath: pathForStable,
            gsUrl: gsForStable,
            videoThumbUrl: videoThumb,
            hasVideo: hasVideo,
            firstImgEmpty: !isValidImageUrl(firstImg),
            title: title,
            isEvento: isEvento,
            onMediaTap: tapMediaAmpliar,
            onDoubleTapMedia: () => unawaited(
                _painelDestaqueToggleLike(
                    context, widget.doc, widget.tenantId)),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: [
            BoxShadow(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
              spreadRadius: -2,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
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
          mainAxisSize: MainAxisSize.min,
          children: [
            if (useWebSplit)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 48,
                      child: LayoutBuilder(
                        builder: (context, lc) {
                          final gw = lc.maxWidth;
                          if (gw <= 0) {
                            return const SizedBox.shrink();
                          }
                          final mh = _painelDestaqueMediaClipHeight(
                            context,
                            gw,
                            data,
                            nPhotosForAr: denomPhotos,
                            carouselIndex:
                                showCarousel ? _carouselPage : 0,
                          );
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              height: mh,
                              width: double.infinity,
                              child: carouselOrImage,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 52,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: openModulo,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isEvento
                                            ? const Color(0xFFFFF7ED)
                                            : const Color(0xFFEFF6FF),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isEvento ? 'Evento' : 'Aviso',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: isEvento
                                              ? const Color(0xFFD97706)
                                              : const Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                                    if (dateStr.isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.calendar_today_rounded,
                                              size: 14,
                                              color: Colors.grey.shade500),
                                          const SizedBox(width: 4),
                                          Text(
                                            dateStr,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (timeStr.isNotEmpty)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.schedule_rounded,
                                              size: 14,
                                              color: Colors.grey.shade500),
                                          const SizedBox(width: 4),
                                          Text(
                                            timeStr,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                                if (title.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    title,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      height: 1.25,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ],
                                if (text.trim().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: _PainelDestaqueExpandableText(
                                        text: text),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (layoutWide)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: (kIsWeb ? _kPainelDestaqueThumbSide : 180).toDouble(),
                      height: _painelDestaqueMediaClipHeight(
                        context,
                        (kIsWeb ? _kPainelDestaqueThumbSide : 180).toDouble(),
                        data,
                        nPhotosForAr: denomPhotos,
                        carouselIndex: showCarousel ? _carouselPage : 0,
                      ).clamp(170.0, 320.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: carouselOrImage,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isEvento ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isEvento ? 'Evento' : 'Aviso',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: isEvento ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                                    ),
                                  ),
                                ),
                                if (dateStr.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Text(
                                        dateStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (timeStr.isNotEmpty)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.schedule_rounded, size: 13, color: Colors.grey.shade500),
                                      const SizedBox(width: 4),
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            if (title.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  height: 1.25,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isEvento ? const Color(0xFFFFF7ED) : const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isEvento ? 'Evento' : 'Aviso',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isEvento ? const Color(0xFFD97706) : const Color(0xFF2563EB),
                            ),
                          ),
                        ),
                        if (dateStr.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        if (timeStr.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.schedule_rounded, size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (title.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.25,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final mw = c.maxWidth > 0 ? c.maxWidth : 360.0;
                  final mediaH = _painelDestaqueMediaClipHeight(
                    context,
                    mw,
                    data,
                    nPhotosForAr: denomPhotos,
                    carouselIndex: showCarousel ? _carouselPage : 0,
                  );
                  return SizedBox(
                    width: double.infinity,
                    height: mediaH,
                    child: carouselOrImage,
                  );
                },
              ),
            ],
            if (!useWebSplit)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: openModulo,
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(ThemeCleanPremium.radiusMd)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (text.trim().isNotEmpty)
                          _PainelDestaqueExpandableText(text: text),
                      ],
                    ),
                  ),
                ),
              ),
            _PainelDestaqueSocialBar(
              doc: widget.doc,
              tenantId: widget.tenantId,
              role: widget.role,
              churchSlug: widget.churchSlug,
              nomeIgreja: widget.nomeIgreja,
              isEvento: isEvento,
            ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Curtir, comentar, compartilhar (e RSVP em eventos) — mesmo fluxo do feed/mural.
class _PainelDestaqueSocialBar extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String tenantId;
  final String role;
  final String churchSlug;
  final String nomeIgreja;
  final bool isEvento;

  const _PainelDestaqueSocialBar({
    required this.doc,
    required this.tenantId,
    required this.role,
    required this.churchSlug,
    required this.nomeIgreja,
    required this.isEvento,
  });

  @override
  State<_PainelDestaqueSocialBar> createState() =>
      _PainelDestaqueSocialBarState();
}

class _PainelDestaqueSocialBarState extends State<_PainelDestaqueSocialBar> {
  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  Future<({String name, String photo})> _memberDisplay() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (name: 'Membro', photo: '');
    var name = user.displayName?.trim() ?? '';
    var photo = user.photoURL?.trim() ?? '';
    if (name.isEmpty) {
      try {
        if (kIsWeb) {
          await FirestoreWebGuard.ensurePanelReadReady().catchError((e, st) {
            debugPrint(
              'Dashboard _PainelDestaqueSocialBar._memberDisplay ensurePanelReadReady: $e\n$st',
            );
          });
        }
        Future<DocumentSnapshot<Map<String, dynamic>>> readUser() =>
            firebaseDefaultFirestore.collection('users').doc(user.uid).get();
        final uDoc = kIsWeb
            ? await FirestoreWebGuard.runWithWebRecovery(
                readUser,
                maxAttempts: 4,
              ).timeout(PanelResilientLoad.queryCap)
            : await readUser().timeout(PanelResilientLoad.queryCap);
        final d = uDoc.data() ?? {};
        name = (d['nome'] ?? d['name'] ?? 'Membro').toString();
        photo = (d['fotoUrl'] ?? d['photoUrl'] ?? photo).toString();
      } catch (e, st) {
        debugPrint('Dashboard _PainelDestaqueSocialBar._memberDisplay: $e\n$st');
        name = 'Membro';
      }
    }
    return (name: name.isEmpty ? 'Membro' : name, photo: photo);
  }

  Future<void> _toggleLike(Map<String, dynamic> data) async {
    if (_myUid == null) return;
    final merged = NoticiaSocialService.mergedLikeUids(data);
    final liked = merged.contains(_myUid!);
    try {
      final m = await _memberDisplay();
      await NoticiaSocialService.toggleCurtida(
        tenantId: widget.tenantId,
        postId: widget.doc.id,
        uid: _myUid!,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyLiked: liked,
        parentCollection:
            ChurchTenantPostsCollections.segmentFromPostRef(widget.doc.reference),
      );
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('Dashboard _PainelDestaqueSocialBar._toggleLike: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Não foi possível curtir agora.'),
        );
      }
    }
  }

  Future<void> _toggleRsvp(Map<String, dynamic> data) async {
    if (_myUid == null) return;
    final rsvpList = List<String>.from(
      ((data['rsvp'] as List?) ?? []).map((e) => e.toString()),
    );
    final rsvp = rsvpList.contains(_myUid!);
    try {
      final m = await _memberDisplay();
      await NoticiaSocialService.toggleConfirmacaoPresenca(
        tenantId: widget.tenantId,
        postId: widget.doc.id,
        uid: _myUid!,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyConfirmed: rsvp,
        parentCollection:
            ChurchTenantPostsCollections.segmentFromPostRef(widget.doc.reference),
      );
      if (mounted) setState(() {});
    } catch (e, st) {
      debugPrint('Dashboard _PainelDestaqueSocialBar._toggleRsvp: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Não foi possível atualizar a confirmação.',
          ),
        );
      }
    }
  }

  void _openComments() {
    final canDelete = !AppPermissions.isRestrictedMember(widget.role);
    showNoticiaCommentsBottomSheet(
      context,
      commentsRef: widget.doc.reference.collection('comentarios'),
      tenantId: widget.tenantId,
      canDelete: canDelete,
    );
  }

  Future<void> _openShareSheet(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final title = (data['title'] ?? '').toString();
    final text = churchPostPlainText(Map<String, dynamic>.from(data));
    final loc = (data['location'] ?? '').toString();
    final tsStartAt = data['startAt'];
    final DateTime? dt = tsStartAt is Timestamp ? tsStartAt.toDate() : null;
    final churchName = widget.nomeIgreja.trim().isNotEmpty
        ? widget.nomeIgreja.trim()
        : 'Nossa igreja';
    final links = resolveNoticiaShareLinks(
      tenantId: widget.tenantId.trim(),
      noticiaId: widget.doc.id,
      churchSlug: widget.churchSlug,
    );
    final lat = data['locationLat'];
    final lng = data['locationLng'];
    final msg = buildNoticiaInviteShareMessage(
      churchName: churchName,
      noticiaKind: widget.isEvento ? 'evento' : 'aviso',
      title: title,
      bodyText: text,
      startAt: dt,
      location: loc.isNotEmpty ? loc : null,
      locationLat: lat is num
          ? lat.toDouble()
          : (lat != null ? double.tryParse(lat.toString()) : null),
      locationLng: lng is num
          ? lng.toDouble()
          : (lng != null ? double.tryParse(lng.toString()) : null),
      publicSiteUrl: links.publicSiteUrl,
      inviteCardUrl: links.eventPageUrl,
      tenantId: widget.tenantId.trim(),
      noticiaId: widget.doc.id,
      churchSlug: links.resolvedSlug,
    );
    if (!context.mounted) return;
    await showChurchNoticiaShareSheet(
      context,
      shareLink: links.eventPageUrl,
      shareMessage: msg,
      shareSubject: churchName,
      previewImageUrl: null,
      videoPlayUrl: null,
      noticiaDataForLazyMedia: data,
      sharePositionOrigin: shareRectFromContext(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minTouch = ThemeCleanPremium.isMobile(context)
        ? ThemeCleanPremium.minTouchTarget
        : 44.0;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: widget.doc.reference.watchSafe(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? widget.doc.data();
        final mergedLikes = NoticiaSocialService.mergedLikeUids(data);
        final liked = _myUid != null && mergedLikes.contains(_myUid!);
        final likeCount = NoticiaSocialService.likeDisplayCount(data, mergedLikes);
        final rsvpUids = List<String>.from(
          ((data['rsvp'] as List?) ?? []).map((e) => e.toString()),
        );
        final rsvp = _myUid != null && rsvpUids.contains(_myUid!);
        final rsvpCount = NoticiaSocialService.rsvpDisplayCount(data, rsvpUids);
        final tsStartAt = data['startAt'];
        final DateTime? eventDt =
            tsStartAt is Timestamp ? tsStartAt.toDate() : null;
        final isFuture =
            widget.isEvento && eventDt != null && eventDt.isAfter(DateTime.now());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 2,
                      runSpacing: 0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () => _toggleLike(data),
                          icon: Icon(
                            liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: liked
                                ? const Color(0xFFE11D48)
                                : Colors.grey.shade800,
                            size: 24,
                          ),
                          style: IconButton.styleFrom(
                            minimumSize: Size(minTouch, minTouch),
                          ),
                        ),
                        IconButton(
                          onPressed: _openComments,
                          icon: Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Colors.grey.shade800,
                            size: 22,
                          ),
                          style: IconButton.styleFrom(
                            minimumSize: Size(minTouch, minTouch),
                          ),
                        ),
                        if (kIsWeb && !ThemeCleanPremium.isMobile(context))
                          TextButton.icon(
                            onPressed: () => _openShareSheet(context, data),
                            icon: Icon(
                              Icons.share_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 22,
                            ),
                            label: const Text(
                              'Compartilhar',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: ThemeCleanPremium.primary,
                              minimumSize: Size(minTouch, minTouch),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                          )
                        else
                          IconButton(
                            onPressed: () => _openShareSheet(context, data),
                            tooltip: 'Compartilhar',
                            icon: Icon(
                              Icons.share_rounded,
                              color: ThemeCleanPremium.primary,
                              size: 22,
                            ),
                            style: IconButton.styleFrom(
                              minimumSize: Size(minTouch, minTouch),
                            ),
                          ),
                        YahwehNoticiaWhatsAppOneTapButton(
                          churchName: widget.nomeIgreja,
                          churchSlug: widget.churchSlug,
                          tenantId: widget.tenantId,
                          noticiaId: widget.doc.id,
                          postData: data,
                          noticiaKindOverride:
                              widget.isEvento ? 'evento' : 'aviso',
                        ),
                      ],
                    ),
                  ),
                  if (isFuture)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _toggleRsvp(data),
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: rsvp
                                ? ThemeCleanPremium.success
                                : ThemeCleanPremium.success.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: ThemeCleanPremium.success.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                rsvp
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 16,
                                color: rsvp
                                    ? Colors.white
                                    : ThemeCleanPremium.success,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rsvp ? 'Confirmado' : 'Participar',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: rsvp
                                      ? Colors.white
                                      : ThemeCleanPremium.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (likeCount > 0)
                    Text(
                      '$likeCount curtida${likeCount > 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  if (rsvpCount > 0 && isFuture)
                    Text(
                      '$rsvpCount pessoa${rsvpCount > 1 ? 's' : ''} confirmou presença',
                      style: TextStyle(
                        fontSize: 12,
                        color: ThemeCleanPremium.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: widget.doc.reference
                        .collection('comentarios')
                        .limit(40)
                        .watchSafe(),
                    builder: (context, cs) {
                      if (cs.hasError || !cs.hasData) {
                        return const SizedBox.shrink();
                      }
                      final raw = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(cs.data!.docs);
                      raw.sort((a, b) {
                        final ta = a.data()['createdAt'];
                        final tb = b.data()['createdAt'];
                        if (ta is Timestamp && tb is Timestamp) {
                          return tb.compareTo(ta);
                        }
                        return 0;
                      });
                      final cDocs = raw;
                      final nField = (data['commentsCount'] is num)
                          ? (data['commentsCount'] as num).toInt()
                          : 0;
                      final hasManyUnknown = nField <= 0 && cDocs.length >= 40;
                      final total = nField > 0
                          ? nField
                          : (hasManyUnknown ? cDocs.length : cDocs.length);
                      if (total == 0 && cDocs.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final previews = cDocs.take(2).toList();
                      final countTitle = hasManyUnknown
                          ? 'Comentários'
                          : '$total comentário${total > 1 ? 's' : ''}';
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              countTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            ...previews.map((cd) {
                              final m = cd.data();
                              final who =
                                  (m['authorName'] ?? 'Membro').toString();
                              final tx =
                                  (m['text'] ?? m['texto'] ?? '').toString();
                              final line = tx.length > 120
                                  ? '${tx.substring(0, 117)}…'
                                  : tx;
                              if (line.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.35,
                                      color: Colors.grey.shade800,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: '$who ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      TextSpan(text: line),
                                    ],
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                            if (total > previews.length)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Toque no ícone de comentários para ver todos',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

