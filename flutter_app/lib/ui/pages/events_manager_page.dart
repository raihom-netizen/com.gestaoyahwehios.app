import 'dart:async' show TimeoutException, Timer, unawaited;
import 'dart:convert';
import 'dart:io' show File;
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firestore_cursor_pagination.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/ui/widgets/lazy_load_more_footer.dart';
import 'package:gestao_yahweh/ui/widgets/church_post_rich_text_utils.dart';
import 'package:gestao_yahweh/ui/widgets/church_post_rich_text_viewer.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/core/tenant/church_panel_tenant.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/services/fast_media_publish_bootstrap.dart';
import 'package:gestao_yahweh/services/feed_post_media_upload.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/ui/widgets/async_upload_progress_strip.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/services/evento_create_publish_service.dart';
import 'package:gestao_yahweh/services/evento_publish_service.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:intl/intl.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/app_theme.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/services/church_eventos_load_service.dart';
import 'package:gestao_yahweh/services/church_tenant_resilient_reads.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';
import 'package:gestao_yahweh/utils/firestore_read_resilience.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/unified_upload_service.dart';
import 'package:gestao_yahweh/core/firebase_publish_guard.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/ui/widgets/feed_editor_local_photo_thumb.dart';
import 'package:gestao_yahweh/core/yahweh_module_analytics.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/app_resume_state_service.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show scheduleFeedMediaWarmup;
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:gestao_yahweh/services/crashlytics_service.dart';
import 'package:gestao_yahweh/services/performance_service.dart';
import 'package:gestao_yahweh/core/image_aspect_ratio_util.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/event_template_schedule.dart'
    show eventTemplateIncludeInAgenda;
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/core/noticia_event_feed.dart'
    show noticiaDocEhEventoSpecialFeed, noticiaEventoEhRotinaOuGeradoAutomatico;
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaPhotoUrls,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaImageStoragePath,
        eventNoticiaVideosFromDoc,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaExternalVideoUrl,
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaVideoThumbUrl,
        looksLikeHostedVideoFileUrl,
        postFeedCarouselAspectRatioForIndex,
        cacheBustImageUrl,
        eventNoticiaMediaCacheRevision;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show bytesLookLikeWebp, kEffectiveMuralFeedWebpQuality;
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/feed_editor_media_service.dart';
import 'package:gestao_yahweh/services/feed_media_publish_service.dart';
import 'package:gestao_yahweh/services/feed_publish_preflight.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/immediate_feed_photo_attach.dart';
import 'package:gestao_yahweh/services/ecofire_feed_publish_service.dart';
import 'package:gestao_yahweh/services/immediate_media_warm.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/utils/immediate_media_attach_feedback.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:gestao_yahweh/services/mural_publish_outbox_service.dart';
import 'package:gestao_yahweh/services/video_handler_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        SafeNetworkImage,
        SafeCircleAvatarImage,
        FreshFirebaseStorageImage,
        dedupeImageRefsByStorageIdentity,
        firebaseStorageMediaUrlLooksLike,
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlFromMap,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        preloadNetworkImages,
        sanitizeImageUrl;
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart'
    show
        showChurchHostedVideoTheater,
        showChurchHostedVideoDialog,
        openChurchHostedVideoImmersive;
import 'package:gestao_yahweh/ui/widgets/noticia_comments_bottom_sheet.dart';
import 'package:gestao_yahweh/core/church_shell_nav_config.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';
import 'package:gestao_yahweh/ui/widgets/church_noticia_share_sheet.dart'
    show showChurchNoticiaShareSheet, shareRectFromContext;
import 'package:gestao_yahweh/ui/widgets/yahweh_whatsapp_one_tap_button.dart';
import 'package:gestao_yahweh/core/noticia_share_links.dart';
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show buildNoticiaInviteShareMessage;
import 'package:image/image.dart' as img;
import 'package:gestao_yahweh/utils/br_input_formatters.dart'
    show
        BrDateDdMmYyyyInputFormatter,
        formatBrDateDdMmYyyy,
        parseBrDateDdMmYyyy;
import 'package:gestao_yahweh/core/event_gallery_archive.dart';
import 'package:gestao_yahweh/core/event_feed_mural_visibility.dart'
    show noticiaEventoEspecialCaiuDoFeedParaGaleria;
import 'package:gestao_yahweh/services/church_context_service.dart';

class EventsManagerPage extends StatefulWidget {
  final String tenantId;
  final String role;
  /// Permissões granulares (`igrejas/.../users/{uid}`) — ex.: `eventos` para publicar no feed.
  final List<String>? permissions;
  /// Dentro do shell: sem AppBar azul duplicada; abas compactas no corpo.
  final bool embeddedInShell;
  final VoidCallback? onShellBack;

  /// Pré-preenche a busca do feed (ex.: busca global).
  final String? initialFeedSearchQuery;
  /// Reabre o evento onde o utilizador parou ([AppResumeStateService]).
  final String? initialOpenEventDocId;
  /// Aba inicial (0=Feed, 1=Galeria Arquivo, demais conforme permissões).
  final int initialTabIndex;

  const EventsManagerPage({
    super.key,
    required this.tenantId,
    required this.role,
    this.permissions,
    this.embeddedInShell = false,
    this.onShellBack,
    this.initialFeedSearchQuery,
    this.initialOpenEventDocId,
    this.initialTabIndex = 0,
  });

  @override
  State<EventsManagerPage> createState() => _EventsManagerPageState();
}

/// Cache RAM — eventos/notícias instantâneo ao reabrir Feed/Galeria/Dashboard.
abstract final class _EventosNoticiasRamCache {
  _EventosNoticiasRamCache._();

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _byTenant = {};

  static const Duration _ttl = Duration(minutes: 20);

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peek(String tenantId) {
    final key = tenantId.trim();
    if (key.isEmpty) return null;
    final hit = _byTenant[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ttl) {
      _byTenant.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void put(
    String tenantId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final key = tenantId.trim();
    if (key.isEmpty || docs.isEmpty) return;
    _byTenant[key] = (docs: List.from(docs), at: DateTime.now());
  }
}

String _eventosNoticiasMemKey(String tenantId, int limit) =>
    '${tenantId.trim()}_noticias_start_$limit';

/// Cache RAM — modelos de culto fixo.
abstract final class _EventTemplatesRamCache {
  _EventTemplatesRamCache._();

  static final Map<
      String,
      ({
        List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
        DateTime at,
      })> _byTenant = {};

  static const Duration _ttl = Duration(minutes: 20);

  static List<QueryDocumentSnapshot<Map<String, dynamic>>>? peek(String tenantId) {
    final key = tenantId.trim();
    if (key.isEmpty) return null;
    final hit = _byTenant[key];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ttl) {
      _byTenant.remove(key);
      return null;
    }
    return hit.docs;
  }

  static void put(
    String tenantId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final key = tenantId.trim();
    if (key.isEmpty || docs.isEmpty) return;
    _byTenant[key] = (docs: List.from(docs), at: DateTime.now());
  }
}

String _eventTemplatesMemKey(String tenantId) =>
    '${tenantId.trim()}_event_templates_all';

class _EventsManagerPageState extends State<EventsManagerPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Map<String, dynamic>? _tenantData;
  /// Mesmo critério que Chat/Mural: ID em `users` ganha sobre doc “irmão” do resolver.
  String? _firestoreTenantId;
  String get _tid => (_firestoreTenantId ?? widget.tenantId).trim();
  final GlobalKey<_FeedTabState> _feedTabKey = GlobalKey<_FeedTabState>();
  final GlobalKey<_FixosTabState> _fixosTabKey = GlobalKey<_FixosTabState>();

  /// Alinhado às regras Firestore [canWriteMuralFeed]: gestor, pastoral, secretário, tesoureiro, líder depto.
  bool get _canWrite => AppPermissions.canManageChurchMuralEventsAgenda(
        widget.role,
        permissions: widget.permissions,
      );

  bool get _canManageAll {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  Future<void> _showEventosDiagnostic() async {
    if (!_canManageAll || !mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.all(20),
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ),
    );
    EventosDiagnosticReport report;
    try {
      report = await EventosDiagnosticService.run(
        seedTenantId: _tid,
        userUid: firebaseDefaultAuth.currentUser?.uid,
      );
    } catch (e) {
      report = EventosDiagnosticReport(
        tenantAtual: _tid,
        tenantResolvido: _tid,
        colecaoUtilizada:
            EventosPublishVerificationService.collectionPathFor(_tid),
        quantidadeEventos: 0,
        ultimoErro: e.toString(),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnóstico Eventos'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tenant atual: ${report.tenantAtual}'),
              const SizedBox(height: 8),
              Text('Tenant resolvido: ${report.tenantResolvido}'),
              const SizedBox(height: 8),
              Text('Coleção: ${report.colecaoUtilizada}'),
              const SizedBox(height: 8),
              Text('Quantidade de eventos: ${report.quantidadeEventos}'),
              const SizedBox(height: 8),
              Text('Fotos no último evento: ${report.fotosEncontradas}'),
              Text(
                'Vídeo no último evento: ${report.videoEncontrado ? 'sim' : 'não'}',
              ),
              if (report.ultimoEventoDocId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Último evento: ${report.ultimoEventoTitulo ?? '(sem título)'}',
                ),
                Text('Doc ID: ${report.ultimoEventoDocId}'),
                if (report.ultimoEventoCreatedAt != null)
                  Text(
                    'Criado: ${DateFormat('dd/MM/yyyy HH:mm').format(report.ultimoEventoCreatedAt!)}',
                  ),
              ],
              if (report.ultimoErro != null && report.ultimoErro!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Último erro:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ThemeCleanPremium.error,
                  ),
                ),
                Text(
                  report.ultimoErro!,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _feedTabKey.currentState?._refresh();
            },
            child: const Text('Recarregar feed'),
          ),
        ],
      ),
    );
  }

  String? _eventsModuleBarSubtitle() {
    final user = firebaseDefaultAuth.currentUser;
    final dn = (user?.displayName ?? '').trim();
    if (dn.isNotEmpty) return dn;
    final email = (user?.email ?? '').trim();
    return email.isNotEmpty ? email : null;
  }

  CollectionReference<Map<String, dynamic>> get _noticias =>
                ChurchUiCollections.eventos(_tid);
  CollectionReference<Map<String, dynamic>> get _templates =>
      ChurchUiCollections.eventTemplates(_tid);

  void _onMainTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    logYahwehModuleScreen('eventos');
    _firestoreTenantId = widget.tenantId;
    _tab = TabController(length: _canWrite ? 4 : 2, vsync: this);
    final startIndex =
        widget.initialTabIndex.clamp(0, (_tab.length - 1).clamp(0, 99)) as int;
    _tab.index = startIndex;
    _tab.addListener(_onMainTabChanged);
    unawaited(_bootstrapFirestoreTenant());
    final resumeId = widget.initialOpenEventDocId?.trim() ?? '';
    if (resumeId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openResumedEventDoc(resumeId));
      });
    }
  }

  Future<void> _openResumedEventDoc(String eventDocId) async {
    try {
      await _bootstrapFirestoreTenant();
      final snap = await _noticias.doc(eventDocId).get();
      if (!mounted || !snap.exists) return;
      unawaited(
        AppResumeStateService.saveOpenEvent(
          tenantId: _tid,
          eventDocId: eventDocId,
        ),
      );
      await _novoEvento(doc: snap);
    } catch (e, st) {
      YahwehFlowLog.error('EVENTOS', e, st);
    }
  }

  @override
  void didUpdateWidget(covariant EventsManagerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId) {
      _firestoreTenantId = null;
      unawaited(_bootstrapFirestoreTenant());
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_onMainTabChanged);
    _tab.dispose();
    super.dispose();
  }

  Future<void> _bootstrapFirestoreTenant() async {
    unawaited(ensureFirebaseReadyForPanelRead().catchError((_) {}));
    final initial = ChurchContextService.panelChurchId(widget.tenantId.trim());
    if (!mounted) return;
    if (initial.isNotEmpty) {
      setState(() => _firestoreTenantId = initial);
    }
    _warmEventosCacheFirst(_tid);
    unawaited(_loadTenantDoc());
    try {
      final tid = ChurchRepository.churchId(widget.tenantId);
      if (!mounted) return;
      if (tid.isNotEmpty && tid != _firestoreTenantId) {
        setState(() => _firestoreTenantId = tid);
        _fixosTabKey.currentState?._refresh();
        _feedTabKey.currentState?._refresh();
        _warmEventosCacheFirst(tid);
      }
    } catch (_) {}
  }

  void _warmEventosCacheFirst(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    unawaited(
      ChurchRepository.listCacheFirst(
        module: ChurchRepository.eventos,
        churchIdHint: tid,
        limit: YahwehPerformanceV4.adminExportBatchLimit,
      ),
    );
  }

  Future<void> _loadTenantDoc() async {
    try {
      final op = ChurchRepository.churchId(_tid.trim());
      final snap = await ChurchUiCollections.churchDoc(op)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));
      if (mounted) setState(() => _tenantData = snap.data());
    } catch (_) {}
  }

  String get _nomeIgreja =>
      (_tenantData?['name'] ?? _tenantData?['nome'] ?? '').toString();
  String get _logoUrl => imageUrlFromMap(_tenantData);

  Future<void> _novoEvento(
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    if (doc != null) {
      unawaited(
        AppResumeStateService.saveOpenEvent(
          tenantId: _tid,
          eventDocId: doc.id,
        ),
      );
    }
    await ensureFirebaseReadyForPublishUpload();
    final igrejaId = ChurchRepository.churchId(_tid);
    final noticias = ChurchUiCollections.eventos(igrejaId);
    if (!mounted) return;
    final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => _EventoFormPage(
                tenantId: _tid,
                resolvedTenantId: igrejaId,
                noticias: noticias,
                doc: doc)));
    if (result == true && mounted) {
      _feedTabKey.currentState?._refresh();
      setState(() {});
      _feedTabKey.currentState?._refresh();
    }
  }

  Future<void> _excluirEvento(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final nome = (doc.data()?['title'] ?? doc.id).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir evento'),
        content: Text('Deseja excluir "$nome"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await _noticias.doc(doc.id).delete();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Evento excluído.'));
    }
  }

  Future<void> _deleteTemplate(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final nome = (doc.data()?['title'] ?? doc.id).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir evento fixo'),
        content: Text(
            'Deseja excluir "$nome"? O evento fixo será removido e não aparecerá mais na lista.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (ok == true) {
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar('Evento fixo excluído.'));
        _fixosTabKey.currentState?._refresh();
      }
    }
  }

  Future<void> _editTemplate(
      {DocumentSnapshot<Map<String, dynamic>>? doc}) async {
    final data = doc?.data() ?? {};
    final titleCtrl =
        TextEditingController(text: (data['title'] ?? '').toString());
    final dow = ValueNotifier<int>((data['weekday'] ?? 7) as int);
    final timeCtrl =
        TextEditingController(text: (data['time'] ?? '19:30').toString());
    final locCtrl =
        TextEditingController(text: (data['location'] ?? '').toString());
    final recurrence =
        ValueNotifier<String>((data['recurrence'] ?? 'weekly').toString());
    final includeInAgenda =
        ValueNotifier<bool>(data['includeInAgenda'] != false);
    // Mesma extração do feed/eventos: imageUrls (lista ou mapas), imageUrl, defaultImageUrl, fotos, etc.
    final urls = _eventImageUrlsFromData(data);
    final initialPhoto = urls.isNotEmpty ? urls.first : '';
    final defaultPhotoUrl = ValueNotifier<String>(initialPhoto);
    final tenantId = _tid;

    Future<void> fillLocationFromCadastro() async {
      try {
        await ensureFirebaseReadyForPublishUpload();
        final op = ChurchRepository.churchId(tenantId.trim());
        final snap = await             ChurchUiCollections.churchDoc(op)
            .get();
        final d = snap.data() ?? {};
        final endereco = (d['endereco'] ?? '').toString().trim();
        if (endereco.isEmpty) {
          final rua = (d['rua'] ?? d['address'] ?? '').toString().trim();
          final bairro = (d['bairro'] ?? '').toString().trim();
          final cidade =
              (d['cidade'] ?? d['localidade'] ?? '').toString().trim();
          final estado = (d['estado'] ?? d['uf'] ?? '').toString().trim();
          final cep = (d['cep'] ?? '').toString().trim();
          final parts = <String>[];
          if (rua.isNotEmpty) parts.add(rua);
          if (bairro.isNotEmpty) parts.add(bairro);
          if (cidade.isNotEmpty && estado.isNotEmpty)
            parts.add('$cidade - $estado');
          else if (cidade.isNotEmpty) parts.add(cidade);
          if (cep.isNotEmpty) parts.add('CEP $cep');
          locCtrl.text = parts.join(', ');
        } else {
          locCtrl.text = endereco;
        }
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Local preenchido com o endereço do cadastro da igreja.'));
      } catch (_) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              ThemeCleanPremium.successSnackBar(
                  'Cadastre o endereço em Cadastro da Igreja primeiro.'));
      }
    }

    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              0, 0, 0, MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ThemeCleanPremium.primary,
                          ThemeCleanPremium.primaryLight,
                        ],
                      ),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          doc == null
                              ? 'Novo evento fixo'
                              : 'Editar evento fixo',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Título',
                          prefixIcon: Icon(Icons.title_rounded))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: ValueListenableBuilder<int>(
                            valueListenable: dow,
                            builder: (_, v, __) => DropdownButtonFormField<int>(
                                  value: v,
                                  decoration:
                                      const InputDecoration(labelText: 'Dia'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 1, child: Text('Seg')),
                                    DropdownMenuItem(
                                        value: 2, child: Text('Ter')),
                                    DropdownMenuItem(
                                        value: 3, child: Text('Qua')),
                                    DropdownMenuItem(
                                        value: 4, child: Text('Qui')),
                                    DropdownMenuItem(
                                        value: 5, child: Text('Sex')),
                                    DropdownMenuItem(
                                        value: 6, child: Text('Sáb')),
                                    DropdownMenuItem(
                                        value: 7, child: Text('Dom'))
                                  ],
                                  onChanged: (nv) => dow.value = nv ?? 7,
                                ))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: timeCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Horário'))),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: TextField(
                            controller: locCtrl,
                            decoration: const InputDecoration(
                                labelText: 'Local (opcional)',
                                prefixIcon: Icon(Icons.location_on_outlined)))),
                    const SizedBox(width: 8),
                    TextButton.icon(
                        onPressed: () async {
                          await fillLocationFromCadastro();
                          setSheetState(() {});
                        },
                        icon: const Icon(Icons.business_rounded, size: 18),
                        label: const Text('Do cadastro')),
                  ]),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                      valueListenable: defaultPhotoUrl,
                      builder: (_, url, __) {
                        if (url.isNotEmpty) {
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Foto padrão escolhida',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade700)),
                                const SizedBox(height: 8),
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: SafeNetworkImage(
                                          imageUrl: url,
                                          width: 96,
                                          height: 96,
                                          fit: BoxFit.cover,
                                          placeholder: Container(
                                              width: 96,
                                              height: 96,
                                              color: Colors.grey.shade200,
                                              child: Icon(Icons.photo_rounded,
                                                  size: 36,
                                                  color: Colors.grey.shade400)),
                                          errorWidget: Container(
                                              width: 96,
                                              height: 96,
                                              color: Colors.grey.shade200,
                                              child: Icon(
                                                  Icons.broken_image_rounded,
                                                  size: 36,
                                                  color: Colors.grey.shade500)),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(
                                                'Esta foto aparece na lista de Eventos Fixos. O Feed não mistura com a rotina semanal.',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color:
                                                        Colors.grey.shade600)),
                                            const SizedBox(height: 8),
                                            OutlinedButton.icon(
                                                icon: const Icon(
                                                    Icons.change_circle_rounded,
                                                    size: 18),
                                                label:
                                                    const Text('Trocar foto'),
                                                onPressed: () async {
                                                  final file =
                                                      await MediaHandlerService
                                                          .instance
                                                          .pickAndProcessImage(
                                                              source:
                                                                  ImageSource
                                                                      .gallery);
                                                  if (file == null ||
                                                      !ctx.mounted) return;
                                                  setSheetState(() {});
                                                  try {
                                                    final compressed =
                                                        file.path
                                                                .trim()
                                                                .isNotEmpty
                                                            ? await SafeImageBytes
                                                                .fromPath(
                                                                file.path,
                                                                maxEdge: 1080,
                                                                quality: 70,
                                                              )
                                                            : await ImageHelper
                                                                .compressImage(
                                                                await file
                                                                    .readAsBytes(),
                                                                minWidth: 800,
                                                                minHeight: 600,
                                                                quality: 70,
                                                              );
                                                    final templateStorageId =
                                                        doc?.id ??
                                                            DateTime.now()
                                                                .millisecondsSinceEpoch
                                                                .toString();
                                                    final storagePath =
                                                        ChurchStorageLayout
                                                            .eventTemplateCoverPath(
                                                          tenantId,
                                                          templateStorageId,
                                                        );
                                                    final downloadUrl =
                                                        await UnifiedUploadService
                                                            .uploadJpegBytes(
                                                      storagePath: storagePath,
                                                      bytes: compressed,
                                                    );
                                                    FirebaseStorageCleanupService
                                                        .scheduleCleanupAfterEventTemplateCoverUpload(
                                                      tenantId: tenantId,
                                                      templateUniqueId:
                                                          templateStorageId,
                                                    );
                                                    if (ctx.mounted) {
                                                      defaultPhotoUrl.value =
                                                          downloadUrl;
                                                      setSheetState(() {});
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              ThemeCleanPremium
                                                                  .successSnackBar(
                                                                      'Foto enviada.'));
                                                    }
                                                  } catch (e) {
                                                    if (ctx.mounted)
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(SnackBar(
                                                              content: Text(
                                                                  'Erro ao enviar foto: $e'),
                                                              backgroundColor:
                                                                  ThemeCleanPremium
                                                                      .error));
                                                  }
                                                }),
                                          ])),
                                      IconButton(
                                          icon: const Icon(Icons.close_rounded),
                                          onPressed: () {
                                            defaultPhotoUrl.value = '';
                                            setSheetState(() {});
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(ThemeCleanPremium
                                                    .successSnackBar(
                                                        'Foto removida.'));
                                          },
                                          tooltip: 'Remover foto'),
                                    ]),
                              ]);
                        }
                        return OutlinedButton.icon(
                          icon: const Icon(Icons.add_photo_alternate_outlined,
                              size: 20),
                          label: const Text('Foto padrão (opcional)'),
                          onPressed: () async {
                            final file = await MediaHandlerService.instance
                                .pickAndProcessImage(
                                    source: ImageSource.gallery);
                            if (file == null || !ctx.mounted) return;
                            setSheetState(() {});
                            try {
                              final compressed = file.path.trim().isNotEmpty
                                  ? await SafeImageBytes.fromPath(
                                      file.path,
                                      maxEdge: 1080,
                                      quality: 70,
                                    )
                                  : await ImageHelper.compressImage(
                                      await file.readAsBytes(),
                                      minWidth: 800,
                                      minHeight: 600,
                                      quality: 70,
                                    );
                              final templateStorageId = doc?.id ??
                                  DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString();
                              final storagePath =
                                  ChurchStorageLayout.eventTemplateCoverPath(
                                tenantId,
                                templateStorageId,
                              );
                              final downloadUrl =
                                  await UnifiedUploadService.uploadJpegBytes(
                                storagePath: storagePath,
                                bytes: compressed,
                              );
                              FirebaseStorageCleanupService
                                  .scheduleCleanupAfterEventTemplateCoverUpload(
                                tenantId: tenantId,
                                templateUniqueId: templateStorageId,
                              );
                              if (ctx.mounted) {
                                defaultPhotoUrl.value = downloadUrl;
                                setSheetState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                    ThemeCleanPremium.successSnackBar(
                                        'Foto enviada.'));
                              }
                            } catch (e) {
                              if (ctx.mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text('Erro ao enviar foto: $e'),
                                        backgroundColor:
                                            ThemeCleanPremium.error));
                            }
                          },
                        );
                      }),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                      valueListenable: recurrence,
                      builder: (_, v, __) => DropdownButtonFormField<String>(
                            value: v,
                            decoration:
                                const InputDecoration(labelText: 'Recorrência'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'weekly', child: Text('Semanal')),
                              DropdownMenuItem(
                                  value: 'biweekly', child: Text('Quinzenal')),
                              DropdownMenuItem(
                                  value: 'monthly', child: Text('Mensal'))
                            ],
                            onChanged: (nv) =>
                                recurrence.value = nv ?? 'weekly',
                          )),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<bool>(
                    valueListenable: includeInAgenda,
                    builder: (_, v, __) => SwitchListTile(
                      value: v,
                      onChanged: (nv) => includeInAgenda.value = nv,
                      contentPadding: EdgeInsets.zero,
                      activeTrackColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.45),
                      activeThumbColor: ThemeCleanPremium.primary,
                      title: const Text(
                        'Gerar na agenda e na programação pública',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      subtitle: Text(
                        'Desligado: mantém o culto no resumo de horários do site, sem expandir datas na agenda interna nem na programação pública; também não permite «Gerar no feed» em massa.',
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: Colors.grey.shade600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            foregroundColor: ThemeCleanPremium.primary,
                            side: BorderSide(
                              color: ThemeCleanPremium.primary
                                  .withValues(alpha: 0.4),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusLg),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            backgroundColor: ThemeCleanPremium.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusLg),
                            ),
                          ),
                          child: const Text(
                            'Salvar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (res != true) return;
    await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);
    await Future.delayed(const Duration(milliseconds: 150));
    final now = Timestamp.now();
    final payload = <String, dynamic>{
      'title': titleCtrl.text.trim(),
      'weekday': dow.value,
      'time': timeCtrl.text.trim(),
      'location': locCtrl.text.trim(),
      'recurrence': recurrence.value,
      'includeInAgenda': includeInAgenda.value,
      'active': true,
      'updatedAt': now,
    };
    if (defaultPhotoUrl.value.isNotEmpty) {
      final u = defaultPhotoUrl.value;
      payload['defaultImageUrl'] = u;
      payload['imageUrl'] = u;
      payload['imageUrls'] = <String>[u];
      payload['imagemUrl'] = u;
      payload['imagem_url'] = u;
    }
    if (doc == null) {
      payload['createdAt'] = now;
      payload['createdByUid'] = firebaseDefaultAuth.currentUser?.uid ?? '';
      await _templates.add(payload);
    } else {
      await doc.reference.update(payload);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Evento fixo salvo.'));
      _fixosTabKey.currentState?._refresh();
    }
  }

  Future<void> _generateFromTemplate(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data() ?? {};
    if (!eventTemplateIncludeInAgenda(data)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Este modelo está com «Gerar na agenda» desligado. Ative na edição do evento fixo para gerar entradas em massa.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    final title = (data['title'] ?? '').toString();
    final defaultImageUrl =
        (data['defaultImageUrl'] ?? data['imageUrl'] ?? '').toString().trim();
    final daysCtrl = TextEditingController(text: '60');
    final useFullYear = ValueNotifier<bool>(false);
    final result = await showDialog<({bool ok, bool fullYear})>(
        context: context,
        builder: (ctx) => StatefulBuilder(
              builder: (context, setDialogState) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg)),
                title: const Text('Gerar eventos futuros'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Cria entradas em massa no banco (útil para relatórios). Esses itens não aparecem no Feed — o Feed é só para eventos especiais publicados manualmente.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.35),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: daysCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Próximos X dias'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: useFullYear.value,
                      onChanged: (v) {
                        useFullYear.value = v ?? false;
                        if (useFullYear.value) daysCtrl.text = '365';
                        setDialogState(() {});
                      },
                      title: const Text('Gerar pro ano todo'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () =>
                          Navigator.pop(ctx, (ok: false, fullYear: false)),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(
                          ctx, (ok: true, fullYear: useFullYear.value)),
                      child: const Text('Gerar')),
                ],
              ),
            ));
    if (result == null || !result.ok) return;
    final weekday = (data['weekday'] ?? 7) as int;
    final time = (data['time'] ?? '19:30').toString();
    final location = (data['location'] ?? '').toString();
    final recurrence = (data['recurrence'] ?? 'weekly').toString();
    final daysAhead =
        result.fullYear ? 365 : (int.tryParse(daysCtrl.text.trim()) ?? 60);
    final now = DateTime.now();
    final until = now.add(Duration(days: daysAhead));
    final tp = time.split(':');
    final hh = int.tryParse(tp.isNotEmpty ? tp[0] : '') ?? 19;
    final mm = int.tryParse(tp.length > 1 ? tp[1] : '') ?? 30;
    final dates = <DateTime>[];
    var cursor = _nextWeekday(now, weekday);
    while (cursor.isBefore(until)) {
      dates.add(DateTime(cursor.year, cursor.month, cursor.day, hh, mm));
      if (recurrence == 'biweekly')
        cursor = cursor.add(const Duration(days: 14));
      else if (recurrence == 'monthly')
        cursor = DateTime(cursor.year, cursor.month + 1, cursor.day);
      else
        cursor = cursor.add(const Duration(days: 7));
    }
    final batch = ChurchRepository.batch();
    final tsNow = Timestamp.now();
    final imageUrls =
        defaultImageUrl.isNotEmpty ? <String>[defaultImageUrl] : <String>[];
    await ensureFirebaseReadyForPublishUpload();
    final op = ChurchRepository.churchId(_tid.trim());
    final agendaCol =         ChurchUiCollections.agenda(op);
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    for (final dt in dates) {
      final notRef = _noticias.doc();
      final endAgenda = dt.add(const Duration(hours: 2));
      batch.set(notRef, {
        'type': 'evento',
        'title': title,
        'text': '',
        'imageUrl': defaultImageUrl,
        'imageUrls': imageUrls,
        if (defaultImageUrl.isNotEmpty) 'imagemUrl': defaultImageUrl,
        if (defaultImageUrl.isNotEmpty) 'imagem_url': defaultImageUrl,
        'location': location,
        'videoUrl': '',
        'startAt': Timestamp.fromDate(dt),
        'dataEvento': Timestamp.fromDate(dt),
        'templateId': doc.id,
        'generated': true,
        'active': true,
        'likes': <String>[],
        'rsvp': <String>[],
        'createdAt': tsNow,
        'updatedAt': tsNow,
      });
      batch.set(agendaCol.doc(), {
        'title': title,
        'description': '',
        'startTime': Timestamp.fromDate(dt),
        'endTime': Timestamp.fromDate(endAgenda),
        'color': '2563eb',
        'category': 'culto',
        'location': location,
        'templateId': doc.id,
        'generated': true,
        'noticiaId': notRef.id,
        'recurrence': recurrence,
        'needSound': false,
        'needDataShow': false,
        'needCantina': false,
        'createdAt': tsNow,
        'updatedAt': tsNow,
        'createdByUid': uid,
      });
    }
    await batch.commit();
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              '${dates.length} eventos gerados!'));
  }

  DateTime _nextWeekday(DateTime from, int weekday) {
    var d = DateTime(from.year, from.month, from.day);
    while (d.weekday != weekday) d = d.add(const Duration(days: 1));
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = ThemeCleanPremium.isMobile(context);
    final showAppBar = !widget.embeddedInShell &&
        (!isMobile || Navigator.canPop(context));
    final muralTabs = _canWrite
        ? const <Widget>[
            Tab(text: 'Feed'),
            Tab(text: 'Galeria'),
            Tab(text: 'Eventos Fixos'),
            Tab(text: 'Dashboard'),
          ]
        : const <Widget>[
            Tab(text: 'Feed'),
            Tab(text: 'Galeria'),
          ];
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: !showAppBar
          ? null
          : AppBar(
              toolbarHeight: isMobile ? kToolbarHeight : 48,
              leading: Navigator.canPop(context)
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      tooltip: 'Voltar')
                  : null,
              title: Text(
                'Mural de Eventos',
                style: TextStyle(
                    fontSize: isMobile ? 17 : 16,
                    fontWeight: FontWeight.w700),
              ),
              actions: [
                if (_canManageAll)
                  IconButton(
                    tooltip: 'Diagnóstico Eventos',
                    onPressed: () => unawaited(_showEventosDiagnostic()),
                    icon: Icon(
                      Icons.medical_information_outlined,
                      color: ThemeCleanPremium.primary,
                    ),
                  ),
              ],
              bottom: _tab.length > 1
                  ? ChurchPanelPillTabBar(
                      controller: _tab,
                      dense: isMobile,
                      style: ChurchPanelPillTabBarStyle.onPrimary,
                      tabs: muralTabs,
                    )
                  : null,
            ),
      body: SafeArea(
          top: widget.onShellBack == null,
          child: Column(children: [
        if (widget.onShellBack != null)
          ChurchEmbeddedModuleBar(
            title: 'Mural de Eventos',
            icon: kChurchShellNavEntries[8].icon,
            accent: kChurchShellNavEntries[8].accent,
            onBack: widget.onShellBack!,
            subtitle: _eventsModuleBarSubtitle(),
          ),
        if (_tab.length > 1 && !showAppBar)
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
              tabs: muralTabs,
            ),
          ),
        Expanded(
            child: TabBarView(controller: _tab, children: [
          _FeedTab(
              key: _feedTabKey,
              tenantId: _tid,
              churchSlug: (_tenantData?['slug'] ?? _tenantData?['slugId'] ?? '')
                  .toString()
                  .trim(),
              churchData: _tenantData,
              noticias: _noticias,
              nomeIgreja: _nomeIgreja,
              logoUrl: _logoUrl,
              canWrite: _canWrite,
              onNovoEvento: () => _novoEvento(),
              onEditEvento: (doc) => _novoEvento(doc: doc),
              onDeleteEvento: _excluirEvento,
              initialFeedSearchQuery: widget.initialFeedSearchQuery),
          _LazyEventsTabGate(
            tabIndex: 1,
            controller: _tab,
            child: _GalleryArchiveTab(
              tenantId: _tid,
              noticias: _noticias,
            ),
          ),
          if (_canWrite)
            _LazyEventsTabGate(
              tabIndex: 2,
              controller: _tab,
              child: _FixosTab(
                  key: _fixosTabKey,
                  templates: _templates,
                  noticias: _noticias,
                  canWrite: _canWrite,
                  onEdit: _editTemplate,
                  onDelete: _deleteTemplate,
                  onGenerate: _generateFromTemplate,
                  onOpenNoticiaEvento: (doc) => _novoEvento(doc: doc)),
            ),
          if (_canWrite)
            _LazyEventsTabGate(
              tabIndex: 3,
              controller: _tab,
              child: _DashboardEventosTab(
                noticias: _noticias,
                canWrite: _canWrite,
              ),
            ),
        ])),
      ])),
      floatingActionButton: _canWrite && _tab.index == 0
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
                onPressed: () => _novoEvento(),
                icon: const Icon(Icons.add_a_photo_rounded, size: 24),
                label: const Text(
                  'Novo evento',
                  style:
                      TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                elevation: 0,
                hoverElevation: 0,
                focusElevation: 0,
                highlightElevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg)),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

/// CRUD simples de categorias (nome + cor) na subcoleção `event_categories`.
class _EventCategoriesManagerSheet extends StatefulWidget {
  final String tenantId;
  const _EventCategoriesManagerSheet({required this.tenantId});

  @override
  State<_EventCategoriesManagerSheet> createState() =>
      _EventCategoriesManagerSheetState();
}

class _GalleryArchiveTab extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> noticias;

  const _GalleryArchiveTab({
    required this.tenantId,
    required this.noticias,
  });

  @override
  State<_GalleryArchiveTab> createState() => _GalleryArchiveTabState();
}

class _GalleryArchiveTabState extends State<_GalleryArchiveTab> {
  late Future<QuerySnapshot<Map<String, dynamic>>> _future;
  QuerySnapshot<Map<String, dynamic>>? _lastGoodGallerySnap;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchApplied = '';
  Timer? _searchDebounce;
  String _order = 'recent_first';
  String _period = 'all';
  String _mediaType = 'all';
  String _category = 'all';
  String _monthYear = 'all';
  DateTime? _customFrom;
  DateTime? _customTo;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onGallerySearchInput);
    _future = _seedOrLoadGallery();
    unawaited(_openGalleryFast());
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _seedOrLoadGallery() {
    final seed = widget.tenantId.trim();
    if (seed.isEmpty) return _load();

    final ram = _EventosNoticiasRamCache.peek(seed);
    if (ram != null && ram.isNotEmpty) {
      final snap = MergedFirestoreQuerySnapshot(ram);
      _lastGoodGallerySnap = snap;
      return Future.value(snap);
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(
      _eventosNoticiasMemKey(seed, 250),
    );
    if (mem != null && mem.docs.isNotEmpty) {
      _lastGoodGallerySnap = mem;
      return Future.value(mem);
    }

    return _load();
  }

  Future<void> _openGalleryFast() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) return;
    try {
      final result = await ChurchEventosLoadService.loadFeed(
        seedTenantId: tid,
        limit: 250,
      ).timeout(const Duration(milliseconds: 1800));
      if (!mounted || result.docs.isEmpty) return;
      _EventosNoticiasRamCache.put(tid, result.docs);
      setState(() {
        _lastGoodGallerySnap = result.snapshot;
        _future = Future.value(result.snapshot);
      });
    } catch (_) {}
  }

  void _onGallerySearchInput() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final q = _searchCtrl.text.trim();
      if (q == _searchApplied) return;
      setState(() => _searchApplied = q);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onGallerySearchInput);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _load() async {
    final result = await ChurchEventosLoadService.loadFeed(
      seedTenantId: widget.tenantId,
      limit: 250,
    );
    if (result.docs.isNotEmpty) {
      _EventosNoticiasRamCache.put(widget.tenantId, result.docs);
      _lastGoodGallerySnap = result.snapshot;
    }
    return result.snapshot;
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
  }

  DateTime? _eventDate(Map<String, dynamic> data) {
    final base = eventArchiveBaseDate(data);
    if (base != null) return base;
    final c = data['createdAt'];
    if (c is Timestamp) return c.toDate();
    return null;
  }

  String _formatDatePt(DateTime? d) {
    if (d == null) return 'Sem data';
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  String _monthYearLabel(DateTime? d) {
    if (d == null) return 'Sem data';
    const months = <String>[
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  String _monthYearKey(DateTime? d) {
    if (d == null) return '';
    final mm = d.month.toString().padLeft(2, '0');
    return '${d.year}-$mm';
  }

  Widget _archiveGalleryCardMedia({
    required Map<String, dynamic> post,
    required List<String> photos,
    required List<Map<String, String>> videos,
  }) {
    final coverRef = photos.isNotEmpty
        ? sanitizeImageUrl(photos.first)
        : sanitizeImageUrl(eventNoticiaDisplayVideoThumbnailUrl(post) ?? '');
    final coverPath = eventNoticiaPhotoStoragePathAt(post, 0) ??
        eventNoticiaImageStoragePath(post);
    final storageLikeRef = coverRef.isNotEmpty &&
        (isFirebaseStorageHttpUrl(coverRef) ||
            firebaseStorageMediaUrlLooksLike(coverRef) ||
            coverRef.toLowerCase().startsWith('gs://'));
    final directHttps = isValidImageUrl(coverRef) &&
        (coverRef.startsWith('http://') || coverRef.startsWith('https://'));

    final media = Stack(
      fit: StackFit.expand,
      children: [
        if (directHttps)
          SafeNetworkImage(
            imageUrl: coverRef,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: kEventoAvisoFeedMemCacheMaxPx,
            memCacheHeight: kEventoAvisoFeedMemCacheMaxPx,
            skipFreshDisplayUrl: true,
            placeholder: const ColoredBox(color: Color(0xFFF1F5F9)),
            errorWidget: const ColoredBox(
              color: Color(0xFFF1F5F9),
              child: Center(child: Icon(Icons.photo_library_outlined)),
            ),
          )
        else if ((coverPath != null && coverPath.trim().isNotEmpty) ||
            storageLikeRef)
          StableStorageImage(
            storagePath: (coverPath != null && coverPath.trim().isNotEmpty)
                ? coverPath
                : null,
            gsUrl: coverRef.toLowerCase().startsWith('gs://') ? coverRef : null,
            imageUrl: coverRef.isNotEmpty ? coverRef : null,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            memCacheWidth: kEventoAvisoFeedMemCacheMaxPx,
            memCacheHeight: kEventoAvisoFeedMemCacheMaxPx,
            placeholder: const ColoredBox(color: Color(0xFFF1F5F9)),
            skipFreshDisplayUrl: true,
            errorWidget: const ColoredBox(
              color: Color(0xFFF1F5F9),
              child: Center(child: Icon(Icons.photo_library_outlined)),
            ),
          )
        else if (isValidImageUrl(coverRef))
          SafeNetworkImage(
            imageUrl: coverRef,
            fit: BoxFit.cover,
            memCacheWidth: kEventoAvisoFeedMemCacheMaxPx,
            memCacheHeight: kEventoAvisoFeedMemCacheMaxPx,
            skipFreshDisplayUrl: true,
            errorWidget: const ColoredBox(
              color: Color(0xFFF1F5F9),
              child: Center(child: Icon(Icons.photo_library_outlined)),
            ),
          )
        else
          const ColoredBox(
            color: Color(0xFFF1F5F9),
            child: Center(child: Icon(Icons.photo_library_outlined)),
          ),
        if (videos.isNotEmpty)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x22000000), Color(0x88000000)],
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.play_circle_fill_rounded,
              size: 46,
              color: Colors.white,
            ),
          ),
      ],
    );

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(ThemeCleanPremium.radiusLg),
      ),
      child: media,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar a galeria',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          final fallback = _lastGoodGallerySnap;
          if (fallback != null && fallback.docs.isNotEmpty) {
            return _buildGalleryBody(fallback, now: DateTime.now());
          }
          return const _FeedSkeleton();
        }
        _lastGoodGallerySnap = snap.data;
        final now = DateTime.now();
        return _buildGalleryBody(snap.data!, now: now);
      },
    );
  }

  Widget _buildGalleryBody(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required DateTime now,
  }) {
        var docs = snap.docs
            .where((d) =>
                noticiaDocEhEventoSpecialFeed(d) &&
                noticiaEventoEspecialCaiuDoFeedParaGaleria(d.data(), now))
            .toList();
        if (_period != 'all') {
          final cutoff = switch (_period) {
            '30d' => now.subtract(const Duration(days: 30)),
            '90d' => now.subtract(const Duration(days: 90)),
            '1y' => now.subtract(const Duration(days: 365)),
            _ => DateTime(1900),
          };
          docs = docs.where((d) {
            final dt = _eventDate(d.data());
            if (dt == null) return false;
            return !dt.isBefore(cutoff);
          }).toList();
        }
        if (_customFrom != null || _customTo != null) {
          docs = docs.where((d) {
            final dt = _eventDate(d.data());
            if (dt == null) return false;
            if (_customFrom != null && dt.isBefore(_customFrom!)) return false;
            if (_customTo != null &&
                dt.isAfter(_customTo!.add(const Duration(days: 1)))) {
              return false;
            }
            return true;
          }).toList();
        }
        final q = _searchApplied.trim().toLowerCase();
        if (q.isNotEmpty) {
          docs = docs.where((d) {
            final p = d.data();
            final t = (p['title'] ?? '').toString().toLowerCase();
            final body = churchPostPlainText(Map<String, dynamic>.from(p))
                .toLowerCase();
            final loc = (p['location'] ?? '').toString().toLowerCase();
            return t.contains(q) || body.contains(q) || loc.contains(q);
          }).toList();
        }
        if (_mediaType != 'all') {
          docs = docs.where((d) {
            final p = d.data();
            final hasPhoto = eventNoticiaPhotoUrls(p).isNotEmpty;
            final hasVideo = eventNoticiaVideosFromDoc(p).isNotEmpty;
            if (_mediaType == 'photos') return hasPhoto;
            if (_mediaType == 'videos') return hasVideo;
            return true;
          }).toList();
        }
        if (_category != 'all') {
          docs = docs.where((d) {
            final p = d.data();
            return (p['eventCategoryId'] ?? '').toString() == _category;
          }).toList();
        }
        final monthOptions = <MapEntry<String, String>>[];
        final seenMonth = <String>{};
        for (final d in docs) {
          final dt = _eventDate(d.data());
          final key = _monthYearKey(dt);
          if (key.isEmpty || seenMonth.contains(key)) continue;
          seenMonth.add(key);
          monthOptions.add(MapEntry(key, _monthYearLabel(dt)));
        }
        monthOptions.sort((a, b) => b.key.compareTo(a.key));
        if (_monthYear != 'all') {
          docs = docs.where((d) {
            final key = _monthYearKey(_eventDate(d.data()));
            return key == _monthYear;
          }).toList();
        }
        docs.sort((a, b) {
          final da = _eventDate(a.data()) ?? DateTime(1900);
          final db = _eventDate(b.data()) ?? DateTime(1900);
          final cmp = db.compareTo(da);
          return _order == 'recent_first' ? cmp : -cmp;
        });
        final archivePreloadUrls = docs
            .take(12)
            .map((d) {
              final post = d.data();
              final ph = eventNoticiaPhotoUrls(post);
              if (ph.isNotEmpty) return ph.first;
              final thumb = eventNoticiaDisplayVideoThumbnailUrl(post);
              return (thumb ?? '').toString().trim();
            })
            .where((u) => u.isNotEmpty)
            .toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final maps = docs.take(16).map((d) => d.data()).toList();
          unawaited(scheduleFeedMediaWarmup(context, maps, maxDocs: 16));
          if (archivePreloadUrls.isNotEmpty) {
            preloadNetworkImages(context, archivePreloadUrls, maxItems: 16);
          }
        });
        final categories = <String>{
          for (final d in snap.docs)
            (d.data()['eventCategoryId'] ?? '').toString().trim()
        }.where((c) => c.isNotEmpty).toList()
          ..sort();
        final sections = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
        for (final d in docs) {
          final key = _monthYearLabel(_eventDate(d.data()));
          sections.putIfAbsent(key, () => <QueryDocumentSnapshot<Map<String, dynamic>>>[]);
          sections[key]!.add(d);
        }
        if (docs.isEmpty) {
          return ThemeCleanPremium.premiumEmptyState(
            icon: Icons.photo_library_outlined,
            title: 'Galeria de eventos vazia',
            subtitle:
                'Quando um evento marcado como permanente terminar, ele ficará no Feed por 1 dia e depois virá para esta galeria de arquivo.',
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              ThemeCleanPremium.spaceMd,
              ThemeCleanPremium.spaceSm,
              ThemeCleanPremium.spaceMd,
              24,
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Pesquisar evento por título ou descrição',
                        prefixIcon: Icon(Icons.search_rounded),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _order,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Ordenação',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                  value: 'recent_first',
                                  child: Text('Último evento -> mais antigo')),
                              DropdownMenuItem(
                                  value: 'old_first',
                                  child: Text('Mais antigo -> mais recente')),
                            ],
                            onChanged: (v) =>
                                setState(() => _order = v ?? 'recent_first'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _period,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Período',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('Todos')),
                              DropdownMenuItem(value: '30d', child: Text('Últimos 30 dias')),
                              DropdownMenuItem(value: '90d', child: Text('Últimos 90 dias')),
                              DropdownMenuItem(value: '1y', child: Text('Último ano')),
                            ],
                            onChanged: (v) => setState(() => _period = v ?? 'all'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _mediaType,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Mídia',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('Todas')),
                              DropdownMenuItem(value: 'photos', child: Text('Só fotos')),
                              DropdownMenuItem(value: 'videos', child: Text('Só vídeos')),
                            ],
                            onChanged: (v) => setState(() => _mediaType = v ?? 'all'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _category,
                            isDense: true,
                            decoration: const InputDecoration(
                              labelText: 'Categoria',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                  value: 'all', child: Text('Todas')),
                              ...categories.map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              ),
                            ],
                            onChanged: (v) => setState(() => _category = v ?? 'all'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _monthYear,
                      isDense: true,
                      decoration: const InputDecoration(
                        labelText: 'Ano/Mês específico',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Todos os meses'),
                        ),
                        ...monthOptions.map(
                          (m) => DropdownMenuItem(
                            value: m.key,
                            child: Text(m.value),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _monthYear = v ?? 'all'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2019),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                initialDate: _customFrom ?? DateTime.now(),
                                locale: const Locale('pt', 'BR'),
                              );
                              if (d != null) setState(() => _customFrom = d);
                            },
                            icon: const Icon(Icons.event_rounded, size: 18),
                            label: Text(_customFrom == null
                                ? 'Data inicial'
                                : _formatDatePt(_customFrom)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2019),
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                                initialDate: _customTo ?? DateTime.now(),
                                locale: const Locale('pt', 'BR'),
                              );
                              if (d != null) setState(() => _customTo = d);
                            },
                            icon: const Icon(Icons.event_available_rounded, size: 18),
                            label: Text(_customTo == null
                                ? 'Data final'
                                : _formatDatePt(_customTo)),
                          ),
                        ),
                      ],
                    ),
                    if (_customFrom != null || _customTo != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () =>
                              setState(() {
                                _customFrom = null;
                                _customTo = null;
                              }),
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          label: const Text('Limpar período'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Arquivo por data (${docs.length} evento(s))',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
              const SizedBox(height: 10),
              for (final entry in sections.entries) ...[
                Container(
                  margin: const EdgeInsets.only(top: 6, bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    entry.key,
                    style: TextStyle(
                      color: ThemeCleanPremium.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: _muralArchiveGridDelegate(context),
                  itemCount: entry.value.length,
                  itemBuilder: (context, i) {
                    final d = entry.value[i];
                    final p = d.data();
                    final photos = eventNoticiaPhotoUrls(p);
                    final videos = eventNoticiaVideosFromDoc(p);
                    final dt = _eventDate(p);
                    return Material(
                      color: Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(ThemeCleanPremium.radiusLg),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      child: InkWell(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusLg),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _EventGalleryDetailPage(data: p),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    ThemeCleanPremium.radiusLg,
                                  ),
                                  border:
                                      Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          _archiveGalleryCardMedia(
                                            post: p,
                                            photos: photos,
                                            videos: videos,
                                          ),
                                          DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.black.withValues(
                                                      alpha: 0.08),
                                                  Colors.black.withValues(
                                                      alpha: 0.40),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 10,
                                            right: 10,
                                            child: _miniChip(
                                              Icons.photo_library_rounded,
                                              '${photos.length + videos.length} mídia(s)',
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 10,
                                            left: 10,
                                            right: 10,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    (p['title'] ?? 'Evento')
                                                        .toString(),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      fontSize: 14.5,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.94),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            999),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: const [
                                                      Icon(
                                                        Icons.grid_view_rounded,
                                                        size: 13,
                                                        color: ThemeCleanPremium
                                                            .primary,
                                                      ),
                                                      SizedBox(width: 4),
                                                      Text(
                                                        'Abrir álbum',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color:
                                                              ThemeCleanPremium
                                                                  .primary,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          12, 10, 12, 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _formatDatePt(dt),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              _miniChip(
                                                Icons.photo_library_rounded,
                                                '${photos.length} foto(s)',
                                              ),
                                              _miniChip(
                                                Icons.videocam_rounded,
                                                '${videos.length} vídeo(s)',
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        );
  }

  Widget _miniChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: ThemeCleanPremium.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Grelha responsiva: 2 colunas em telemóvel estreito, 3 em médio, até 4 em web/tablet.
  SliverGridDelegate _muralArchiveGridDelegate(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width - ThemeCleanPremium.spaceMd * 2;
    final maxExt = w < 400
        ? (w - 12) / 2
        : w < 640
            ? (w - 24) / 3
            : min(300.0, (w - 36) / 4);
    return SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: max(132.0, maxExt),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 0.84,
    );
  }
}

Map<String, dynamic> _noticiaDataForSingleVideoRow(
  Map<String, dynamic> base,
  Map<String, String> row,
) {
  final o = Map<String, dynamic>.from(base);
  o['videos'] = <Map<String, String>>[
    <String, String>{
      'videoUrl': row['videoUrl'] ?? '',
      'thumbUrl': row['thumbUrl'] ?? '',
    }
  ];
  return o;
}

DateTime? _galleryDetailEventDate(Map<String, dynamic> data) {
  final base = eventArchiveBaseDate(data);
  if (base != null) return base;
  final c = data['createdAt'];
  if (c is Timestamp) return c.toDate();
  return null;
}

String _galleryFormatDatePt(DateTime? d) {
  if (d == null) return 'Sem data';
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '$dd/$mm/${d.year}';
}

class _EventGalleryDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;

  const _EventGalleryDetailPage({required this.data});

  @override
  Widget build(BuildContext context) {
    final photos = eventNoticiaPhotoUrls(data);
    final videos = eventNoticiaVideosFromDoc(data);
    final titleStr = (data['title'] ?? 'Evento').toString();
    final dateStr = _galleryFormatDatePt(_galleryDetailEventDate(data));
    final mq = MediaQuery.of(context);
    final hPad = max(12.0, min(22.0, mq.size.width * 0.045));
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        title: Text(
          (data['title'] ?? 'Detalhes do evento').toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(hPad, 14, hPad, 28),
        children: [
          if (churchPostPlainText(Map<String, dynamic>.from(data))
              .trim()
              .isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ChurchPostRichTextViewer(
                data: Map<String, dynamic>.from(data),
              ),
            ),
          if (photos.isNotEmpty) ...[
            Text(
              'Fotos',
              style: TextStyle(
                fontSize: mq.size.width < 400 ? 15 : 17,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: photos.length,
              gridDelegate:
                  _muralDetailPhotosGridDelegate(mq.size.width),
              itemBuilder: (_, i) => Material(
                color: Colors.white,
                elevation: 0,
                shadowColor: Colors.black12,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            _FullScreenGallery(images: photos, initial: i),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: SafeNetworkImage(
                        imageUrl: photos[i],
                        fit: BoxFit.cover,
                        errorWidget: Container(
                          color: const Color(0xFFF1F5F9),
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          if (videos.isNotEmpty) ...[
            const Text(
              'Vídeos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ...videos.map((v) {
              final raw = (v['videoUrl'] ?? '').toString().trim();
              if (raw.isEmpty) return const SizedBox.shrink();
              final one = _noticiaDataForSingleVideoRow(data, v);
              final hosted = eventNoticiaHostedVideoPlayUrl(one) ?? '';
              var external = '';
              if (hosted.isEmpty) {
                external =
                    eventNoticiaExternalVideoUrl(one)?.trim() ?? raw;
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EventVideoBlock(
                  title: titleStr,
                  dateStr: dateStr,
                  hostedVideoUrl: hosted,
                  externalLaunchUrl: external,
                  thumbUrl: (v['thumbUrl'] ?? '').toString(),
                  openExternalInTheater: true,
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _EventCategoriesManagerSheetState extends State<_EventCategoriesManagerSheet> {
  static const List<Color> _palette = [
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFEA580C),
    Color(0xFF9333EA),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
    Color(0xFF475569),
  ];

  final _nome = TextEditingController();
  Color _selectedColor = _palette[0];
  bool _saving = false;
  bool _loadingList = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = [];

  Future<String> _operationalTenantId() async =>
      ChurchRepository.churchId(widget.tenantId);

  CollectionReference<Map<String, dynamic>> _colFor(String tid) =>
      ChurchUiCollections.eventCategories(tid);

  @override
  void initState() {
    super.initState();
    unawaited(_reloadList());
  }

  Future<void> _reloadList() async {
    if (mounted) setState(() => _loadingList = true);
    try {
      final q = await ChurchTenantResilientReads.eventCategories(
        widget.tenantId,
        userUid: firebaseDefaultAuth.currentUser?.uid,
      );
      final list = q.docs.toList()
        ..sort((a, b) => (a.data()['nome'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b.data()['nome'] ?? '').toString().toLowerCase()));
      if (mounted) {
        setState(() {
          _docs = list;
          _loadingList = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _add() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) return;
    setState(() => _saving = true);
    try {
      final tid = await _operationalTenantId();
      await FirestoreWebGuard.runChatWriteWithRecovery(
        () => _colFor(tid).add({
          'nome': nome,
          'cor': _selectedColor.value,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );
      _nome.clear();
      await _reloadList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Categoria adicionada.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(formatUploadErrorForUser(e)),
          backgroundColor: ThemeCleanPremium.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir categoria'),
        content: Text(
            'Remover "${(doc.data()?['nome'] ?? doc.id)}"? Eventos antigos mantêm a cor gravada.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirestoreWebGuard.runChatWriteWithRecovery(
        () => doc.reference.delete(),
      );
      await _reloadList();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $e'),
          backgroundColor: ThemeCleanPremium.error,
        ));
      }
    }
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Categorias de eventos',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: Colors.grey.shade900,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nome,
                decoration: const InputDecoration(
                  labelText: 'Nova categoria',
                  prefixIcon: Icon(Icons.label_outline_rounded),
                ),
              ),
              const SizedBox(height: 10),
              Text('Cor na agenda',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _palette)
                    InkWell(
                      onTap: () => setState(() => _selectedColor = c),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedColor == c
                                ? Colors.black87
                                : Colors.white,
                            width: _selectedColor == c ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _add,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.add_rounded),
                label: Text(_saving ? 'Salvando…' : 'Adicionar'),
              ),
              const SizedBox(height: 16),
              if (_loadingList)
                const Center(child: CircularProgressIndicator())
              else if (_docs.isEmpty)
                Text(
                  'Nenhuma categoria ainda.',
                  style: TextStyle(color: Colors.grey.shade600),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Cadastradas',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.grey.shade800)),
                    const SizedBox(height: 8),
                    ..._docs.map((d) {
                      final nome = (d.data()['nome'] ?? d.id).toString();
                      final cor = d.data()['cor'];
                      final color = cor is int ? Color(cor) : Colors.grey;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: color,
                          radius: 12,
                        ),
                        title: Text(nome),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _delete(d),
                        ),
                      );
                    }),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Feed Tab — leitura pontual (.get()) para evitar INTERNAL ASSERTION FAILED (web/mobile).
// ═══════════════════════════════════════════════════════════════════════════════
class _FeedTab extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> noticias;
  final String nomeIgreja, logoUrl;
  final bool canWrite;
  final VoidCallback onNovoEvento;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onEditEvento,
      onDeleteEvento;
  final String churchSlug;
  final Map<String, dynamic>? churchData;
  final String? initialFeedSearchQuery;
  const _FeedTab(
      {super.key,
      required this.tenantId,
      this.churchSlug = '',
      this.churchData,
      required this.noticias,
      required this.nomeIgreja,
      required this.logoUrl,
      required this.canWrite,
      required this.onNovoEvento,
      required this.onEditEvento,
      required this.onDeleteEvento,
      this.initialFeedSearchQuery});

  @override
  State<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends State<_FeedTab> {
  static const int _feedPageSize = YahwehPerformanceV4.defaultPageSize;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _loadedDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _feedLastCursor;
  bool _hasMoreFeedPages = true;
  bool _isLoadingMore = false;
  bool _isInitialLoading = true;
  QuerySnapshot<Map<String, dynamic>>? _lastGoodEventsSnap;
  bool _showingOfflineEvents = false;
  Object? _feedLoadError;
  String _filterPeriod = 'all';
  int _filterWeekday = 0;
  final _searchCtrl = TextEditingController();
  String _searchApplied = '';
  Timer? _searchDebounce;
  bool _selectMode = false;
  final Set<String> _selectedEventIds = <String>{};

  Query<Map<String, dynamic>> _eventsBaseQuery({bool filtered = true}) {
    final col = ChurchUiCollections.eventos(widget.tenantId.trim());
    if (!filtered) {
      return col.orderBy('startAt', descending: true);
    }
    return col
        .where('ativo', isEqualTo: true)
        .where('publicado', isEqualTo: true)
        .orderBy('startAt', descending: true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialFeedSearchQuery != null &&
        widget.initialFeedSearchQuery!.trim().isNotEmpty) {
      _searchCtrl.text = widget.initialFeedSearchQuery!.trim();
      _searchApplied = _searchCtrl.text.trim();
    }
    _searchCtrl.addListener(_onFeedSearchInput);
    unawaited(_bootstrapFeed());
  }

  Future<void> _bootstrapFeed() async {
    final seed = widget.tenantId.trim();
    if (seed.isNotEmpty) {
      final ram = _EventosNoticiasRamCache.peek(seed);
      if (ram != null && ram.isNotEmpty) {
        final docs = ram.length > _feedPageSize
            ? ram.sublist(0, _feedPageSize)
            : ram;
        if (mounted) {
          setState(() {
            _loadedDocs
              ..clear()
              ..addAll(docs);
            _feedLastCursor = docs.isNotEmpty ? docs.last : null;
            _hasMoreFeedPages = ram.length > _feedPageSize;
            _isInitialLoading = false;
            _lastGoodEventsSnap = MergedFirestoreQuerySnapshot(docs);
          });
        }
      }
    }
    unawaited(_primeEventsFromCache());
    if (_loadedDocs.isEmpty) {
      await _loadInitialEvents();
    }
  }

  Future<void> _primeEventsFromCache() async {
    final tid = widget.tenantId.trim();
    if (tid.isEmpty) return;

    void applyDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      if (!mounted || docs.isEmpty || _loadedDocs.isNotEmpty) return;
      setState(() {
        _loadedDocs
          ..clear()
          ..addAll(docs);
        _feedLastCursor = docs.isNotEmpty ? docs.last : null;
        _hasMoreFeedPages = docs.length >= _feedPageSize;
        _isInitialLoading = false;
        _lastGoodEventsSnap = MergedFirestoreQuerySnapshot(docs);
      });
    }

    try {
      final result = await ChurchEventosLoadService.loadFeed(
        seedTenantId: tid,
        limit: _feedPageSize,
      ).timeout(const Duration(milliseconds: 1800));
      if (result.docs.isNotEmpty) {
        _EventosNoticiasRamCache.put(tid, result.docs);
        applyDocs(result.docs);
        return;
      }
    } catch (_) {}

    try {
      final cacheSnap = await _eventsBaseQuery()
          .limit(_feedPageSize)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (cacheSnap.docs.isNotEmpty) {
        _EventosNoticiasRamCache.put(tid, cacheSnap.docs);
        applyDocs(
            cacheSnap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>());
      }
    } catch (_) {}
  }

  void _onFeedSearchInput() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final q = _searchCtrl.text.trim();
      if (q == _searchApplied) return;
      setState(() => _searchApplied = q);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.removeListener(_onFeedSearchInput);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialEvents() async {
    setState(() {
      _isInitialLoading = _loadedDocs.isEmpty;
      _showingOfflineEvents = false;
      _feedLoadError = null;
      _hasMoreFeedPages = true;
      _feedLastCursor = null;
      _loadedDocs.clear();
    });
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchEventosLoadService.loadFeed(
          seedTenantId: widget.tenantId.trim(),
          limit: _feedPageSize,
        ).then((r) => r.snapshot),
        maxAttempts: 4,
      ).timeout(const Duration(seconds: 14));
      final docs =
          snap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
      if (!mounted) return;
      setState(() {
        _loadedDocs
          ..clear()
          ..addAll(docs);
        _feedLastCursor = docs.isNotEmpty ? docs.last : null;
        _hasMoreFeedPages = docs.length >= _feedPageSize;
        _isInitialLoading = false;
        _lastGoodEventsSnap = snap;
        _feedLoadError = null;
      });
      if (docs.isNotEmpty) {
        _EventosNoticiasRamCache.put(widget.tenantId.trim(), docs);
      }
    } catch (e) {
      if (!mounted) return;
      if (_loadedDocs.isNotEmpty) {
        setState(() => _showingOfflineEvents = true);
        return;
      }
      try {
        final cacheSnap = await _eventsBaseQuery()
            .limit(_feedPageSize)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 4));
        final docs =
            cacheSnap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
        if (!mounted) return;
        setState(() {
          _loadedDocs
            ..clear()
            ..addAll(docs);
          _feedLastCursor = docs.isNotEmpty ? docs.last : null;
          _hasMoreFeedPages = docs.length >= _feedPageSize;
          _isInitialLoading = false;
          _showingOfflineEvents = docs.isNotEmpty;
          _lastGoodEventsSnap = cacheSnap;
          _feedLoadError = docs.isEmpty ? e : null;
        });
      } catch (_) {
        if (mounted) {
          setState(() {
            _isInitialLoading = false;
            _feedLoadError = e;
          });
        }
      }
    }
  }

  Future<void> _loadMoreEvents() async {
    if (_isLoadingMore || !_hasMoreFeedPages || _feedLastCursor == null) {
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final page = await FirestoreWebGuard.runWithWebRecovery(() {
        return FirestoreCursorPagination.fetchDocumentsPage(
          baseQuery: _eventsBaseQuery(),
          startAfter: _feedLastCursor,
          pageSize: _feedPageSize,
        );
      });
      if (!mounted) return;
      final idSeen = {for (final d in _loadedDocs) d.id};
      final next = page.items.where((d) => idSeen.add(d.id)).toList();
      setState(() {
        _loadedDocs.addAll(next);
        _feedLastCursor = page.lastDocument ?? _feedLastCursor;
        _hasMoreFeedPages = page.hasMore;
      });
      if (_loadedDocs.isNotEmpty) {
        _EventosNoticiasRamCache.put(widget.tenantId, _loadedDocs);
      }
    } catch (e, st) {
      unawaited(CrashlyticsService.record(e, st, reason: 'eventos_feed_load_more'));
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _refresh() async {
    await _loadInitialEvents();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _loadEventsSnapshot() async {
    if (_loadedDocs.isEmpty) {
      await _loadInitialEvents();
    }
    return MergedFirestoreQuerySnapshot(_loadedDocs);
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedEventIds.clear();
    });
  }

  Future<void> _deleteFeedRefs(
      List<DocumentReference<Map<String, dynamic>>> refs) async {
    if (refs.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nada para excluir.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir eventos'),
        content: Text('Deseja excluir ${refs.length} evento(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await ensureFirebaseReadyForPublishUpload();
    const int chunkSize = 400; // limite seguro de batch
    for (var i = 0; i < refs.length; i += chunkSize) {
      final batch = ChurchRepository.batch();
      final chunk = refs.sublist(
          i, i + chunkSize > refs.length ? refs.length : i + chunkSize);
      for (final r in chunk) {
        batch.delete(r);
      }
      await batch.commit();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Eventos excluídos.'));
      _selectedEventIds.clear();
      _selectMode = false;
      await _loadInitialEvents();
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteSelectedFeed() async {
    final ids = _selectedEventIds.toList();
    final refs = ids.map((id) => widget.noticias.doc(id)).toList();
    await _deleteFeedRefs(refs);
  }

  Future<void> _deleteByCurrentPeriod() async {
    final snap = await _loadEventsSnapshot();
    final allDocs =
        snap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
    final docs = _applyFilters(allDocs, DateTime.now(), _filterPeriod,
        _filterWeekday, _searchCtrl.text);
    final refs = docs.map((d) => d.reference).toList();
    await _deleteFeedRefs(refs);
  }

  static List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyFilters(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime now,
    String period,
    int weekday,
    String searchQuery,
  ) {
    // Feed = só eventos especiais; data passada → Galeria, não o Feed.
    var out = docs.where(noticiaDocEhEventoSpecialFeed).where((d) {
      final data = d.data();
      if (data['ativo'] == false) return false;
      if (data['publicado'] == false) return false;
      if (noticiaEventoEspecialCaiuDoFeedParaGaleria(d.data(), now)) {
        return false;
      }
      final v = d.data()['validUntil'];
      if (v == null) return true;
      if (v is Timestamp) return v.toDate().isAfter(now);
      return true;
    }).toList();
    if (period != 'all') {
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 7));
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      final startLastMonth = DateTime(now.year, now.month - 1, 1);
      final endLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);
      final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);
      out = out.where((d) {
        DateTime? dt;
        try {
          dt = (d.data()['startAt'] as Timestamp).toDate();
        } catch (_) {}
        if (dt == null) return false;
        if (period == 'week')
          return !dt.isBefore(now) && dt.isBefore(endOfWeek);
        if (period == 'month')
          return dt.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
              dt.isBefore(endOfMonth.add(const Duration(days: 1)));
        if (period == 'last_month')
          return !dt.isBefore(startLastMonth) && !dt.isAfter(endLastMonth);
        if (period == 'year')
          return !dt.isBefore(now) && !dt.isAfter(endOfYear);
        return true;
      }).toList();
    }
    if (weekday > 0 && weekday < 8) {
      out = out.where((d) {
        try {
          final dt = (d.data()['startAt'] as Timestamp).toDate();
          return dt.weekday == weekday;
        } catch (_) {
          return false;
        }
      }).toList();
    }
    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      out = out
          .where((d) =>
              (d.data()['title'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (_feedLoadError != null && _loadedDocs.isEmpty) {
      return ChurchPanelErrorBody(
        title: 'Não foi possível carregar avisos e eventos',
        error: _feedLoadError,
        onRetry: _refresh,
      );
    }
    if (_isInitialLoading && _loadedDocs.isEmpty) {
      return const _FeedSkeleton();
    }
    final now = DateTime.now();
    return _buildFeedList(_loadedDocs, now: now, offlineBanner: _showingOfflineEvents);
  }

  Widget _buildFeedList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs, {
    DateTime? now,
    bool offlineBanner = false,
  }) {
        final effectiveNow = now ?? DateTime.now();
        final docs = _applyFilters(
            allDocs, effectiveNow, _filterPeriod, _filterWeekday, _searchApplied);

        final preloadUrls = docs
            .take(8)
            .map((d) {
              final data = d.data();
              final photos = eventNoticiaPhotoUrls(data);
              if (photos.isNotEmpty) return photos.first;
              final thumb = eventNoticiaDisplayVideoThumbnailUrl(data);
              return (thumb ?? '').toString().trim();
            })
            .where((u) => u.isNotEmpty)
            .toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          final maps = docs.take(10).map((d) => d.data()).toList();
          unawaited(scheduleFeedMediaWarmup(context, maps, maxDocs: 10));
          if (preloadUrls.isNotEmpty) {
            preloadNetworkImages(context, preloadUrls, maxItems: 12);
          }
        });

        if (docs.isEmpty) {
          return ThemeCleanPremium.premiumEmptyState(
            icon: Icons.event_available_rounded,
            title: 'Nenhum evento ainda',
            subtitle:
                'Use o Feed para cultos especiais, campanhas e datas comemorativas. A programação semanal fica em Eventos Fixos.',
            action: widget.canWrite
                ? FilledButton.icon(
                    onPressed: widget.onNovoEvento,
                    icon: const Icon(Icons.add_photo_alternate_rounded),
                    label: const Text('Criar primeiro evento'),
                  )
                : null,
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final avail = constraints.maxWidth;
              final narrowFeed = kIsWeb &&
                  avail.isFinite &&
                  avail > AppTheme.maxSocialFeedWidthWeb;
              Widget feedList = ListView.builder(
            padding: const EdgeInsets.fromLTRB(
                ThemeCleanPremium.spaceMd,
                ThemeCleanPremium.spaceSm,
                ThemeCleanPremium.spaceMd,
                80),
            cacheExtent: 1200,
            itemCount: docs.length +
                1 +
                (offlineBanner ? 1 : 0) +
                (_hasMoreFeedPages || _isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (offlineBanner && index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Material(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 20, color: Colors.orange.shade800),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Modo offline — a mostrar a última lista guardada. Puxe para atualizar.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final headerIndex = offlineBanner ? 1 : 0;
              if (index == headerIndex) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Buscar por evento',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusMd)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _filterPeriod,
                              decoration: const InputDecoration(
                                  labelText: 'Período',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8)),
                              items: const [
                                DropdownMenuItem(
                                    value: 'all', child: Text('Todos')),
                                DropdownMenuItem(
                                    value: 'week',
                                    child: Text('Esta semana')),
                                DropdownMenuItem(
                                    value: 'month', child: Text('Este mês')),
                                DropdownMenuItem(
                                    value: 'last_month',
                                    child: Text('Mês anterior')),
                                DropdownMenuItem(
                                    value: 'year', child: Text('Este ano')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _filterPeriod = v ?? 'all'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: DropdownButtonFormField<int>(
                              value: _filterWeekday,
                              decoration: const InputDecoration(
                                  labelText: 'Dia',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8)),
                              items: const [
                                DropdownMenuItem(
                                    value: 0, child: Text('Qualquer')),
                                DropdownMenuItem(
                                    value: 1, child: Text('Seg')),
                                DropdownMenuItem(
                                    value: 2, child: Text('Ter')),
                                DropdownMenuItem(
                                    value: 3, child: Text('Qua')),
                                DropdownMenuItem(
                                    value: 4, child: Text('Qui')),
                                DropdownMenuItem(
                                    value: 5, child: Text('Sex')),
                                DropdownMenuItem(
                                    value: 6, child: Text('Sáb')),
                                DropdownMenuItem(
                                    value: 7, child: Text('Dom')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _filterWeekday = v ?? 0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _MuralFeedSelectionRow(
                        selectMode: _selectMode,
                        selectedCount: _selectedEventIds.length,
                        onToggleSelect: _toggleSelectMode,
                        onExcluirPorPeriodo: _deleteByCurrentPeriod,
                        onExcluirSelecionados: _deleteSelectedFeed,
                      ),
                    ],
                  ),
                );
              }
              final footerIndex = headerIndex + docs.length + 1;
              if ((_hasMoreFeedPages || _isLoadingMore) &&
                  index == footerIndex) {
                return LazyLoadMoreFooter(
                  loading: _isLoadingMore,
                  visible: _hasMoreFeedPages || _isLoadingMore,
                  onLoadMore: _loadMoreEvents,
                );
              }
              if (index <= headerIndex || index > headerIndex + docs.length) {
                return const SizedBox.shrink();
              }
              final d = docs[index - headerIndex - 1];
              final selected = _selectedEventIds.contains(d.id);
              return Stack(
                children: [
                  _EventoPost(
                    tenantId: widget.tenantId,
                    churchSlug: widget.churchSlug,
                    churchData: widget.churchData,
                    doc: d,
                    nomeIgreja: widget.nomeIgreja,
                    logoUrl: widget.logoUrl,
                    canWrite: widget.canWrite,
                    selectionMode: _selectMode,
                    onEdit: () => widget.onEditEvento(d),
                    onDelete: () => widget.onDeleteEvento(d),
                  ),
                  if (_selectMode)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: SizedBox(
                        width: ThemeCleanPremium.minTouchTarget,
                        height: ThemeCleanPremium.minTouchTarget,
                        child: Checkbox(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedEventIds.remove(d.id);
                              } else {
                                _selectedEventIds.add(d.id);
                              }
                            });
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          );
              if (narrowFeed) {
                feedList = Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: AppTheme.maxSocialFeedWidthWeb,
                    child: feedList,
                  ),
                );
              }
              return feedList;
            },
          ),
        );
  }
}

/// Ações de seleção / exclusão do feed do Mural — botões com gradiente e sombra soft.
class _MuralFeedSelectionRow extends StatelessWidget {
  final bool selectMode;
  final int selectedCount;
  final VoidCallback onToggleSelect;
  final VoidCallback onExcluirPorPeriodo;
  final VoidCallback onExcluirSelecionados;

  const _MuralFeedSelectionRow({
    required this.selectMode,
    required this.selectedCount,
    required this.onToggleSelect,
    required this.onExcluirPorPeriodo,
    required this.onExcluirSelecionados,
  });

  @override
  Widget build(BuildContext context) {
    final p = ThemeCleanPremium.primary;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _SoftOutlinePillButton(
          onPressed: onToggleSelect,
          icon: selectMode
              ? Icons.close_rounded
              : Icons.check_box_outlined,
          label: selectMode ? 'Cancelar seleção' : 'Selecionar',
          borderColor: selectMode
              ? const Color(0xFF94A3B8)
              : p.withValues(alpha: 0.5),
          foreground: selectMode ? const Color(0xFF475569) : p,
        ),
        if (selectMode)
          _CoralActionPillButton(
            onPressed: selectedCount == 0 ? null : onExcluirSelecionados,
            icon: Icons.delete_sweep_rounded,
            label: 'Excluir ($selectedCount)',
          )
        else
          _CoralActionPillButton(
            onPressed: onExcluirPorPeriodo,
            icon: Icons.event_busy_rounded,
            label: 'Excluir por período',
          ),
      ],
    );
  }
}

class _SoftOutlinePillButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color borderColor;
  final Color foreground;

  const _SoftOutlinePillButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.borderColor,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.6),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                ThemeCleanPremium.primary.withValues(alpha: 0.05),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.07),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: foreground),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.15,
                    color: foreground,
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

class _CoralActionPillButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  const _CoralActionPillButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final e = ThemeCleanPremium.error;
    final disabled = onPressed == null;
    return Opacity(
      opacity: disabled ? 0.48 : 1,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [e, Color.lerp(e, const Color(0xFFB91C1C), 0.2)!],
              ),
              boxShadow: [
                BoxShadow(
                  color: e.withValues(alpha: 0.38),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: 0.15,
                      color: Colors.white,
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// Stories Bar — estilo Instagram
// ═══════════════════════════════════════════════════════════════════════════════
class _StoriesBar extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final String nomeIgreja, logoUrl, tenantId;
  final CollectionReference<Map<String, dynamic>> noticias;
  const _StoriesBar(
      {required this.docs,
      required this.nomeIgreja,
      required this.logoUrl,
      required this.noticias,
      required this.tenantId});

  @override
  Widget build(BuildContext context) {
    if (docs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 96,
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        itemCount: docs.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _StoryCircle(
                  label: 'Sua Igreja',
                  imageUrl: logoUrl,
                  isFirst: true,
                  onTap: () {}),
            );
          }
          final d = docs[i - 1].data();
          final title = (d['title'] ?? '').toString();
          final imgs = _eventImageUrlsFromData(d);
          final thumbV = eventNoticiaDisplayVideoThumbnailUrl(d);
          var img = imgs.isNotEmpty ? imgs.first : '';
          if (img.isEmpty && thumbV != null && thumbV.isNotEmpty) img = thumbV;
          if (img.isEmpty) img = (d['imageUrl'] ?? '').toString();
          if (img.isNotEmpty && looksLikeHostedVideoFileUrl(img)) {
            img = thumbV ?? '';
          }
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _StoryCircle(
              label: title.length > 10 ? '${title.substring(0, 10)}...' : title,
              imageUrl: img,
              onTap: () => _openStory(context, docs[i - 1]),
            ),
          );
        },
      ),
    );
  }

  void _openStory(
      BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final title = (data['title'] ?? '').toString();
    final text = churchPostPlainText(Map<String, dynamic>.from(data));
    final imgs = _eventImageUrlsFromData(data);
    final displayThumbAll = eventNoticiaDisplayVideoThumbnailUrl(data) ?? '';
    var img = imgs.isNotEmpty ? imgs.first : '';
    if (img.isEmpty && displayThumbAll.isNotEmpty) img = displayThumbAll;
    if (img.isEmpty) img = (data['imageUrl'] ?? '').toString();
    if (img.isNotEmpty && looksLikeHostedVideoFileUrl(img))
      img = displayThumbAll;
    final loc = (data['location'] ?? '').toString();
    DateTime? dt;
    try {
      dt = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    final dateStr = dt != null
        ? '${_wn(dt.weekday)}, ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        onVerticalDragEnd: (_) => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
              child: Stack(children: [
            Builder(builder: (ctx2) {
              final vidPlay = eventNoticiaHostedVideoPlayUrl(data);
              final extVid = eventNoticiaExternalVideoUrl(data);
              final storyThumb =
                  eventNoticiaDisplayVideoThumbnailUrl(data) ?? '';
              if (isValidImageUrl(img)) {
                return Center(
                  child: SafeNetworkImage(
                    imageUrl: sanitizeImageUrl(img),
                    fit: BoxFit.contain,
                    placeholder: const Center(
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54),
                      ),
                    ),
                    errorWidget: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_rounded,
                              size: 64, color: Colors.white54),
                          const SizedBox(height: 16),
                          Text('Falha ao carregar foto',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (vidPlay != null && vidPlay.isNotEmpty) {
                Future<void> openVid() async {
                  final u = Uri.tryParse(vidPlay.startsWith('http')
                      ? vidPlay
                      : 'https://$vidPlay');
                  if (u != null && await canLaunchUrl(u)) {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  }
                }

                if (isValidImageUrl(storyThumb)) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: openVid,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SafeNetworkImage(
                                  imageUrl: sanitizeImageUrl(storyThumb),
                                  fit: BoxFit.cover,
                                  placeholder: Container(
                                      color: Colors.black54,
                                      child: const Center(
                                          child: SizedBox(
                                              width: 40,
                                              height: 40,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white54)))),
                                  errorWidget: Container(
                                      color: const Color(0xFF1E3A8A),
                                      child: Icon(
                                          Icons.play_circle_filled_rounded,
                                          color: Colors.white.withOpacity(0.9),
                                          size: 72)),
                                ),
                                Container(color: Colors.black38),
                                const Center(
                                    child: Icon(Icons.play_circle_fill_rounded,
                                        size: 72, color: Colors.white)),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 10,
                                  child: Text(title,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          shadows: [
                                            Shadow(
                                                blurRadius: 8,
                                                color: Colors.black54)
                                          ]),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: openVid,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_filled_rounded,
                              color: Colors.white.withOpacity(0.95), size: 72),
                          const SizedBox(height: 16),
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          Text('Toque para assistir ao vídeo',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              if (extVid != null && extVid.isNotEmpty) {
                Future<void> openExt() async {
                  final u = Uri.tryParse(
                      extVid.startsWith('http') ? extVid : 'https://$extVid');
                  if (u != null && await canLaunchUrl(u)) {
                    await launchUrl(u, mode: LaunchMode.externalApplication);
                  }
                }

                if (isValidImageUrl(storyThumb)) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: openExt,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                SafeNetworkImage(
                                  imageUrl: sanitizeImageUrl(storyThumb),
                                  fit: BoxFit.cover,
                                  placeholder: Container(
                                      color: Colors.black54,
                                      child: const Center(
                                          child: SizedBox(
                                              width: 40,
                                              height: 40,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white54)))),
                                  errorWidget: Container(
                                      color:
                                          Colors.red.shade900.withOpacity(0.4),
                                      child: Icon(Icons.ondemand_video_rounded,
                                          color: Colors.red.shade200,
                                          size: 64)),
                                ),
                                Container(color: Colors.black38),
                                Center(
                                    child: Icon(Icons.ondemand_video_rounded,
                                        color: Colors.red.shade200, size: 64)),
                                Positioned(
                                  left: 12,
                                  right: 12,
                                  bottom: 10,
                                  child: Text('YouTube / Vimeo',
                                      style: TextStyle(
                                          color: Colors.white.withOpacity(0.95),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                return Center(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: openExt,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ondemand_video_rounded,
                              color: Colors.red.shade300, size: 72),
                          const SizedBox(height: 14),
                          Text(title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          Text('Toque para abrir no YouTube / Vimeo',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.85),
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: Container(
                  padding: const EdgeInsets.all(40),
                  decoration: const BoxDecoration(
                      gradient: LinearGradient(
                          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.event_rounded,
                          color: Colors.white70, size: 56),
                      const SizedBox(height: 16),
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              );
            }),
            Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Row(children: [
                  SafeCircleAvatarImage(
                      imageUrl: logoUrl.isNotEmpty ? logoUrl : null,
                      radius: 18,
                      fallbackIcon: Icons.church_rounded,
                      fallbackColor: Colors.white,
                      backgroundColor: Colors.white24),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(nomeIgreja.isNotEmpty ? nomeIgreja : 'Igreja',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        if (dateStr.isNotEmpty)
                          Text(dateStr,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11)),
                      ])),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48))),
                ])),
            Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (loc.isNotEmpty)
                        Row(children: [
                          const Icon(Icons.location_on_rounded,
                              color: Colors.white70, size: 14),
                          const SizedBox(width: 4),
                          Flexible(
                              child: Text(loc,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)))
                        ]),
                      if (text.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(text,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis)
                      ],
                    ])),
          ])),
        ),
      ),
    );
  }

  static String _wn(int w) => const [
        '',
        'Seg',
        'Ter',
        'Qua',
        'Qui',
        'Sex',
        'Sáb',
        'Dom'
      ][w.clamp(0, 7)];
}

class _StoryCircle extends StatelessWidget {
  final String label, imageUrl;
  final bool isFirst;
  final VoidCallback onTap;
  const _StoryCircle(
      {required this.label,
      required this.imageUrl,
      this.isFirst = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isFirst
                  ? null
                  : const LinearGradient(colors: [
                      Color(0xFF833AB4),
                      Color(0xFFE1306C),
                      Color(0xFFF77737)
                    ]),
              border: isFirst
                  ? Border.all(color: Colors.grey.shade300, width: 2)
                  : null,
            ),
            child: SafeCircleAvatarImage(
              imageUrl:
                  isValidImageUrl(imageUrl) ? sanitizeImageUrl(imageUrl) : null,
              radius: 25,
              fallbackIcon:
                  isFirst ? Icons.church_rounded : Icons.event_rounded,
              fallbackColor: Colors.grey.shade500,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

List<String> _eventImageUrlsFromData(Map<String, dynamic> data) =>
    eventNoticiaPhotoUrls(data);

/// Fotos do card do Feed sem repetir a capa/miniatura do vídeo (evita faixa cinza/branca + vídeo).
/// Índice da foto no doc original (para [eventNoticiaPhotoStoragePathAt]) a partir da URL filtrada.
int? _eventPhotoUrlIndexInDoc(Map<String, dynamic> data, String candidateUrl) {
  final target = sanitizeImageUrl(candidateUrl);
  if (target.isEmpty) return null;
  final photos = eventNoticiaPhotoUrls(data);
  for (var i = 0; i < photos.length; i++) {
    if (sanitizeImageUrl(photos[i]) == target) return i;
  }
  return null;
}

List<String> _eventFeedCardPhotoUrls(Map<String, dynamic> data) {
  final raw = _eventImageUrlsFromData(data);
  final thumbUrls = <String>{
    sanitizeImageUrl(eventNoticiaDisplayVideoThumbnailUrl(data) ?? ''),
    sanitizeImageUrl(eventNoticiaVideoThumbUrl(data) ?? ''),
  }..removeWhere((e) => e.isEmpty);
  final thumbPaths = <String>{};
  for (final u in thumbUrls) {
    final p = firebaseStorageObjectPathFromHttpUrl(u);
    if (p != null && p.isNotEmpty) {
      thumbPaths.add(normalizeFirebaseStorageObjectPath(p));
    }
  }
  return dedupeImageRefsByStorageIdentity(raw.where((u) {
    final s = sanitizeImageUrl(u);
    if (thumbUrls.contains(s)) return false;
    final p = firebaseStorageObjectPathFromHttpUrl(s);
    if (p != null && p.isNotEmpty &&
        thumbPaths.contains(normalizeFirebaseStorageObjectPath(p))) {
      return false;
    }
    return true;
  }).toList());
}

List<Map<String, String>> _eventVideosFromData(Map<String, dynamic> data) =>
    eventNoticiaVideosFromDoc(data);

// ═══════════════════════════════════════════════════════════════════════════════
// Post do Evento — Instagram completo (foto, vídeo, comentários)
// ═══════════════════════════════════════════════════════════════════════════════
class _EventoPost extends StatefulWidget {
  final String tenantId;
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String nomeIgreja, logoUrl;
  final bool canWrite;
  final bool selectionMode;
  final VoidCallback onEdit, onDelete;
  final String churchSlug;
  final Map<String, dynamic>? churchData;
  const _EventoPost({
    required this.tenantId,
    this.churchSlug = '',
    this.churchData,
    required this.doc,
    required this.nomeIgreja,
    required this.logoUrl,
    required this.canWrite,
    this.selectionMode = false,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_EventoPost> createState() => _EventoPostState();
}

class _EventoPostState extends State<_EventoPost>
    with SingleTickerProviderStateMixin {
  bool _showHeart = false;
  int _carouselIndex = 0;

  String? get _myUid => firebaseDefaultAuth.currentUser?.uid;

  Future<({String name, String photo})> _memberDisplay() async {
    final user = firebaseDefaultAuth.currentUser;
    if (user == null) return (name: 'Membro', photo: '');
    var name = user.displayName?.trim() ?? '';
    var photo = user.photoURL?.trim() ?? '';
    if (name.isEmpty) {
      try {
        final uDoc = await firebaseDefaultFirestore
            .collection('users')
            .doc(user.uid)
            .get();
        final d = uDoc.data() ?? {};
        name = (d['nome'] ?? d['name'] ?? 'Membro').toString();
        photo = (d['fotoUrl'] ?? d['photoUrl'] ?? photo).toString();
      } catch (_) {
        name = 'Membro';
      }
    }
    return (name: name.isEmpty ? 'Membro' : name, photo: photo);
  }

  Future<void> _toggleLike() async {
    if (_myUid == null) return;
    final data = widget.doc.data();
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
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Não foi possível curtir agora.'),
        );
      }
    }
  }

  void _onDoubleTap() async {
    final data = widget.doc.data();
    final merged = NoticiaSocialService.mergedLikeUids(data);
    final liked = _myUid != null && merged.contains(_myUid!);
    if (liked || _myUid == null) {
      setState(() => _showHeart = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) setState(() => _showHeart = false);
      });
      return;
    }
    setState(() => _showHeart = true);
    await _toggleLike();
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  Future<void> _toggleRsvp() async {
    if (_myUid == null) return;
    final data = widget.doc.data();
    final rsvpList = List<String>.from(
        ((data['rsvp'] as List?) ?? []).map((e) => e.toString()));
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
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
              'Não foi possível atualizar a confirmação.'),
        );
      }
    }
  }

  void _openComments() {
    showNoticiaCommentsBottomSheet(
      context,
      commentsRef: widget.doc.reference.collection('comentarios'),
      tenantId: widget.tenantId,
      canDelete: widget.canWrite,
    );
  }

  Future<void> _openShareSheet(Rect? shareOrigin) async {
    final data = widget.doc.data();
    final title = (data['title'] ?? '').toString();
    final text = churchPostPlainText(Map<String, dynamic>.from(data));
    final loc = (data['location'] ?? '').toString();
    DateTime? dt;
    try {
      dt = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    final churchName = widget.nomeIgreja.trim().isNotEmpty
        ? widget.nomeIgreja.trim()
        : 'Nossa igreja';
    final links = resolveNoticiaShareLinks(
      tenantId: widget.tenantId.trim(),
      noticiaId: widget.doc.id,
      churchSlug: widget.churchSlug,
    );
    final elat = _eventPostParseDouble(data['locationLat']);
    final elng = _eventPostParseDouble(data['locationLng']);
    final msg = buildNoticiaInviteShareMessage(
      churchName: churchName,
      noticiaKind: 'evento',
      title: title,
      bodyText: text,
      startAt: dt,
      location: loc.isNotEmpty ? loc : null,
      locationLat: elat,
      locationLng: elng,
      publicSiteUrl: links.publicSiteUrl,
      inviteCardUrl: links.eventPageUrl,
      tenantId: widget.tenantId.trim(),
      noticiaId: widget.doc.id,
      churchSlug: links.resolvedSlug,
    );
    if (!mounted) return;
    await showChurchNoticiaShareSheet(
      context,
      shareLink: links.eventPageUrl,
      shareMessage: msg,
      shareSubject: churchName,
      previewImageUrl: null,
      videoPlayUrl: null,
      noticiaDataForLazyMedia: data,
      sharePositionOrigin: shareOrigin,
    );
  }

  void _openFullScreen(List<String> images) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                _FullScreenGallery(images: images, initial: _carouselIndex)));
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}m';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}min';
    return 'agora';
  }

  Widget _buildEventFeedPhotoSlide({
    required Map<String, dynamic> data,
    required String imageUrl,
    required double w,
    required double h,
    required int memW,
    required int memH,
    required Widget Function() errorWidget,
  }) {
    final url = sanitizeImageUrl(imageUrl);
    final rev = eventNoticiaMediaCacheRevision(data);
    final displayUrl = cacheBustImageUrl(url, revisionMs: rev);
    final ph = Container(
      color: const Color(0xFFF8FAFC),
      child: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: ThemeCleanPremium.primary.withOpacity(0.6),
          ),
        ),
      ),
    );
    final err = errorWidget();
    final origIdx = _eventPhotoUrlIndexInDoc(data, imageUrl);
    final path = origIdx != null
        ? eventNoticiaPhotoStoragePathAt(data, origIdx)
        : null;
    if (isValidImageUrl(displayUrl) &&
        (displayUrl.startsWith('http://') || displayUrl.startsWith('https://'))) {
      return SafeNetworkImage(
        key: ValueKey('evt_direct_$displayUrl'),
        imageUrl: displayUrl,
        fit: BoxFit.contain,
        width: w,
        height: h,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: true,
      );
    }
    if (path != null && path.trim().isNotEmpty) {
      return StableStorageImage(
        key: ValueKey('evt_st_${path}_$displayUrl'),
        storagePath: path,
        imageUrl: isValidImageUrl(url) ? displayUrl : null,
        gsUrl: url.toLowerCase().startsWith('gs://') ? url : null,
        width: w,
        height: h,
        fit: BoxFit.contain,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: true,
      );
    }
    final storageLike = url.isNotEmpty &&
        (isFirebaseStorageHttpUrl(url) || firebaseStorageMediaUrlLooksLike(url));
    if (storageLike) {
      return FreshFirebaseStorageImage(
        key: ValueKey('evt_ff_$displayUrl'),
        imageUrl: displayUrl,
        fit: BoxFit.contain,
        width: w,
        height: h,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: ph,
        errorWidget: err,
      );
    }
    if (isValidImageUrl(url)) {
      return SafeNetworkImage(
        key: ValueKey('evt_sn_$displayUrl'),
        imageUrl: displayUrl,
        fit: BoxFit.contain,
        width: w,
        height: h,
        memCacheWidth: memW,
        memCacheHeight: memH,
        placeholder: ph,
        errorWidget: err,
        skipFreshDisplayUrl: true,
      );
    }
    return err;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final mergedLikes = NoticiaSocialService.mergedLikeUids(data);
    final liked = _myUid != null && mergedLikes.contains(_myUid!);
    final likeCount = NoticiaSocialService.likeDisplayCount(data, mergedLikes);
    final rsvpUids = List<String>.from(
      ((data['rsvp'] as List?) ?? []).map((e) => e.toString()),
    );
    final rsvp = _myUid != null && rsvpUids.contains(_myUid!);
    final rsvpCount = NoticiaSocialService.rsvpDisplayCount(data, rsvpUids);
    final title = (data['title'] ?? '').toString();
    final allImages = _eventFeedCardPhotoUrls(data);
    final hasImages = allImages.isNotEmpty;
    final location = (data['location'] ?? '').toString();
    final eventVideos = _eventVideosFromData(data);
    final videoUrl = eventVideos.isNotEmpty
        ? (eventVideos.first['videoUrl'] ?? '')
        : (data['videoUrl'] ?? '').toString().trim();
    final displayVideoThumb = eventNoticiaDisplayVideoThumbnailUrl(data) ?? '';
    final rawHosted = eventNoticiaHostedVideoPlayUrl(data) ?? '';
    final hostedVideoUrl = sanitizeImageUrl(rawHosted);
    final useHostedPlayer = hostedVideoUrl.isNotEmpty &&
        (hostedVideoUrl.startsWith('http://') ||
            hostedVideoUrl.startsWith('https://')) &&
        looksLikeHostedVideoFileUrl(hostedVideoUrl);
    var externalLaunchUrl = '';
    if (!useHostedPlayer) {
      final ext = eventNoticiaExternalVideoUrl(data);
      if (ext != null && ext.trim().isNotEmpty) {
        externalLaunchUrl = sanitizeImageUrl(ext.trim());
      } else if (videoUrl.isNotEmpty) {
        externalLaunchUrl = sanitizeImageUrl(videoUrl);
      }
    }
    final hasVideoRow = useHostedPlayer || externalLaunchUrl.isNotEmpty;
    final publishState = (data['publishState'] ?? '').toString();
    final mediaUploading =
        publishState == MuralFastPublishService.stateUploading;
    final publishFailed = publishState == MuralFastPublishService.stateFailed;
    final publishError = (data['publishError'] ?? '').toString();

    DateTime? eventDt;
    try {
      eventDt = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    DateTime? createdDt;
    try {
      createdDt = (data['createdAt'] as Timestamp).toDate();
    } catch (_) {}
    final eventDateStr = eventDt != null
        ? '${_wn(eventDt.weekday)}, ${eventDt.day.toString().padLeft(2, '0')}/${eventDt.month.toString().padLeft(2, '0')}/${eventDt.year} às ${eventDt.hour.toString().padLeft(2, '0')}:${eventDt.minute.toString().padLeft(2, '0')}'
        : '';
    final createdAgo = createdDt != null ? _timeAgo(createdDt) : '';
    final isFuture = eventDt != null && eventDt.isAfter(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: ThemeCleanPremium.cardBackground,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header (endereço vai para os links no fim do card)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ThemeCleanPremium.primary.withOpacity(0.08),
                  border: Border.all(
                      color: ThemeCleanPremium.primary.withOpacity(0.3),
                      width: 1.5)),
              child: SafeCircleAvatarImage(
                  imageUrl: widget.logoUrl.isNotEmpty ? widget.logoUrl : null,
                  radius: 19,
                  fallbackIcon: Icons.church_rounded,
                  fallbackColor: ThemeCleanPremium.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      widget.nomeIgreja.isNotEmpty
                          ? widget.nomeIgreja
                          : 'Igreja',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13)),
                ])),
            if (widget.canWrite && !widget.selectionMode)
              PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      color: Colors.grey.shade700),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  onSelected: (v) {
                    if (v == 'edit') widget.onEdit();
                    if (v == 'delete') widget.onDelete();
                  },
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'edit',
                            child: Row(children: [
                              Icon(Icons.edit_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('Editar')
                            ])),
                        PopupMenuItem(
                            value: 'delete',
                            child: Row(children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Excluir',
                                  style: TextStyle(color: Colors.red))
                            ]))
                      ]),
          ]),
        ),
        // Título + data ficam só como barra fina sobre foto/vídeo (estilo avisos / EcoFire)
        // Fotos e vídeo (preview visível)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((mediaUploading || publishFailed) && !hasImages)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: FutureBuilder<List<Uint8List>?>(
                  future: MuralPostPendingMediaCache.get(
                    tenantId: widget.tenantId,
                    postId: widget.doc.id,
                  ),
                  builder: (context, pendingSnap) {
                    final pending = pendingSnap.data;
                    if (pending != null && pending.isNotEmpty) {
                      return AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(pending.first, fit: BoxFit.cover),
                              if (mediaUploading)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 12,
                                    ),
                                    color: Colors.black.withValues(alpha: 0.45),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'A publicar fotos…',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
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
                    if (publishFailed) {
                      return AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: ColoredBox(
                            color: ThemeCleanPremium.error
                                .withValues(alpha: 0.06),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cloud_off_rounded,
                                    color: ThemeCleanPremium.error,
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    publishError.isNotEmpty
                                        ? publishError
                                        : 'Falha ao publicar fotos.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          ThemeCleanPremium.onSurfaceVariant,
                                    ),
                                  ),
                                  if (widget.canWrite) ...[
                                    const SizedBox(height: 10),
                                    FilledButton.tonal(
                                      onPressed: () {
                                        unawaited(
                                          MuralPublishOutboxService
                                              .retryFromCard(
                                            tenantId: widget.tenantId,
                                            postId: widget.doc.id,
                                            postType: 'evento',
                                            existingUrls: allImages,
                                            startSlotIndex: allImages.length,
                                            hasVideo: hasVideoRow,
                                          ),
                                        );
                                      },
                                      child: const Text('Tentar de novo'),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return AspectRatio(
                      aspectRatio: 4 / 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(color: const Color(0xFFF8FAFC)),
                            const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'A publicar fotos…',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
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
              ),
            if (hasImages)
              GestureDetector(
                onDoubleTap: widget.selectionMode ? null : _onDoubleTap,
                onTap: !widget.selectionMode
                    ? () => _openFullScreen(allImages)
                    : null,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    if (allImages.length == 1)
                      LayoutBuilder(
                        builder: (context, c) {
                          final w = c.maxWidth.isFinite && c.maxWidth > 0
                              ? c.maxWidth
                              : 400.0;
                          final ar = postFeedCarouselAspectRatioForIndex(
                              data, 0, allImages.length);
                          final h = w / ar;
                          final dpr = MediaQuery.devicePixelRatioOf(context);
                          final memW = (w * dpr).round().clamp(64, 2048);
                          final memH = (h * dpr).round().clamp(64, 2048);
                          return AspectRatio(
                            aspectRatio: ar,
                            child: _buildEventFeedPhotoSlide(
                              data: data,
                              imageUrl: allImages[0],
                              w: w,
                              h: h,
                              memW: memW,
                              memH: memH,
                              errorWidget: () => _eventImageErrorWithOverlay(
                                  title: title, dateStr: eventDateStr),
                            ),
                          );
                        },
                      ),
                    if (allImages.length > 1)
                      LayoutBuilder(
                        builder: (context, c) {
                          final w = c.maxWidth.isFinite && c.maxWidth > 0
                              ? c.maxWidth
                              : 400.0;
                          final ar = postFeedCarouselAspectRatioForIndex(
                              data, _carouselIndex, allImages.length);
                          final h = w / ar;
                          return AspectRatio(
                            aspectRatio: ar,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                PageView.builder(
                                  physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics()),
                                  padEnds: false,
                                  itemCount: allImages.length,
                                  onPageChanged: (p) =>
                                      setState(() => _carouselIndex = p),
                                  itemBuilder: (_, idx) {
                                    final dpr =
                                        MediaQuery.devicePixelRatioOf(context);
                                    final memW =
                                        (w * dpr).round().clamp(64, 2048);
                                    final memH =
                                        (h * dpr).round().clamp(64, 2048);
                                    return _buildEventFeedPhotoSlide(
                                      data: data,
                                      imageUrl: allImages[idx],
                                      w: w,
                                      h: h,
                                      memW: memW,
                                      memH: memH,
                                      errorWidget: () =>
                                          _eventImageErrorWithOverlay(
                                              title: title,
                                              dateStr: eventDateStr),
                                    );
                                  },
                                ),
                                Positioned(
                                  bottom: 44,
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        'Arraste para ver ${allImages.length} fotos',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    if ((title.isNotEmpty || eventDateStr.isNotEmpty) &&
                        !widget.selectionMode)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: _EventMediaOverlayBar(
                              title: title, dateStr: eventDateStr),
                        ),
                      ),
                    AnimatedOpacity(
                      opacity: _showHeart ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.thumb_up_rounded,
                          color: Colors.white,
                          size: 80,
                          shadows: [
                            Shadow(blurRadius: 20, color: Colors.black38)
                          ]),
                    ),
                    if (allImages.length > 1)
                      Positioned(
                        bottom: 10,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            allImages.length,
                            (idx) => Container(
                              width: idx == _carouselIndex ? 8 : 6,
                              height: idx == _carouselIndex ? 8 : 6,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: idx == _carouselIndex
                                    ? ThemeCleanPremium.primary
                                    : Colors.white60,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!widget.selectionMode)
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Material(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.zoom_in_rounded,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text('Ampliar',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (hasVideoRow)
              Padding(
                padding:
                    EdgeInsets.only(top: hasImages ? 8 : 0, left: 4, right: 4),
                child: _EventVideoBlock(
                  title: title,
                  dateStr: eventDateStr,
                  hostedVideoUrl: useHostedPlayer ? hostedVideoUrl : '',
                  externalLaunchUrl: externalLaunchUrl,
                  thumbUrl: displayVideoThumb,
                ),
              ),
            if (!hasImages &&
                !hasVideoRow &&
                (title.isNotEmpty || eventDateStr.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusLg),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFE2E8F0),
                                Colors.grey.shade100
                              ],
                            ),
                          ),
                        ),
                        Center(
                          child: Icon(
                            Icons.event_rounded,
                            size: 44,
                            color: Colors.white.withValues(alpha: 0.95),
                            shadows: const [
                              Shadow(blurRadius: 14, color: Colors.black26)
                            ],
                          ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _EventMediaOverlayBar(
                              title: title, dateStr: eventDateStr),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Actions
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            IconButton(
              onPressed: widget.selectionMode ? null : _toggleLike,
              icon: Icon(
                  liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  color:
                      liked ? ThemeCleanPremium.primary : Colors.grey.shade800,
                  size: 26),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
            IconButton(
              onPressed: widget.selectionMode ? null : _openComments,
              icon: Icon(Icons.forum_outlined,
                  color: Colors.grey.shade800, size: 24),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
            IconButton(
              onPressed: widget.selectionMode
                  ? null
                  : () {
                      final origin = shareRectFromContext(context);
                      _openShareSheet(origin);
                    },
              icon: Icon(Icons.share_rounded,
                  color: Colors.grey.shade800, size: 24),
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            ),
            if (!widget.selectionMode)
              YahwehNoticiaWhatsAppOneTapButton(
                churchName: widget.nomeIgreja,
                churchSlug: widget.churchSlug,
                tenantId: widget.tenantId,
                noticiaId: widget.doc.id,
                postData: widget.doc.data(),
                noticiaKindOverride: 'evento',
              ),
            const Spacer(),
            if (isFuture)
              Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.selectionMode ? null : _toggleRsvp,
                    borderRadius: BorderRadius.circular(20),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: rsvp
                              ? ThemeCleanPremium.success
                              : ThemeCleanPremium.success.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color:
                                  ThemeCleanPremium.success.withOpacity(0.3))),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            rsvp
                                ? Icons.check_circle_rounded
                                : Icons.add_circle_outline_rounded,
                            size: 16,
                            color: rsvp
                                ? Colors.white
                                : ThemeCleanPremium.success),
                        const SizedBox(width: 4),
                        Text(rsvp ? 'Confirmado' : 'Participar',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: rsvp
                                    ? Colors.white
                                    : ThemeCleanPremium.success)),
                      ]),
                    ),
                  )),
          ]),
        ),
        // Likes + RSVP count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (likeCount > 0)
              Text('$likeCount curtida${likeCount > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
            if (rsvpCount > 0 && isFuture)
              Text(
                  '$rsvpCount pessoa${rsvpCount > 1 ? 's' : ''} confirmou presença',
                  style: TextStyle(
                      fontSize: 12,
                      color: ThemeCleanPremium.success,
                      fontWeight: FontWeight.w600)),
          ]),
        ),
        // Texto de divulgação (título já está na faixa)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: ChurchPostRichTextViewer(
            key: ValueKey(
                '${widget.doc.id}_${churchPostRichContentSig(Map<String, dynamic>.from(data))}'),
            data: Map<String, dynamic>.from(data),
          ),
        ),
        // Convite, site público e mapa
        _EventPostLinksRow(
          tenantId: widget.tenantId,
          churchSlug: widget.churchSlug,
          churchData: widget.churchData,
          shareInviteUrl: resolveNoticiaShareLinks(
            tenantId: widget.tenantId.trim(),
            noticiaId: widget.doc.id,
            churchSlug: widget.churchSlug,
            churchData: widget.churchData,
          ).eventPageUrl,
          eventLocation: location,
          eventLat: _eventPostParseDouble(data['locationLat']),
          eventLng: _eventPostParseDouble(data['locationLng']),
        ),
        // Link(s) do(s) vídeo(s)
        if (eventVideos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: eventVideos.asMap().entries.map((e) {
                final vUrl = e.value['videoUrl'] ?? '';
                if (vUrl.isEmpty) return const SizedBox.shrink();
                return InkWell(
                  onTap: () async {
                    final uri = Uri.tryParse(
                        vUrl.startsWith('http') ? vUrl : 'https://$vUrl');
                    if (uri != null && await canLaunchUrl(uri))
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.play_circle_filled_rounded,
                          size: 20, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Text(
                          eventVideos.length > 1
                              ? 'Vídeo ${e.key + 1}'
                              : 'Assistir vídeo',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        // Comments — link sem stream para evitar INTERNAL ASSERTION FAILED
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: GestureDetector(
              onTap: _openComments,
              child: Text('Ver comentários',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            )),
        // Time ago
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
            child: Text(createdAgo.isNotEmpty ? 'há $createdAgo' : '',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400))),
      ]),
    );
  }

  static String _wn(int w) => const [
        '',
        'Seg',
        'Ter',
        'Qua',
        'Qui',
        'Sex',
        'Sáb',
        'Dom'
      ][w.clamp(0, 7)];
}

// ═══════════════════════════════════════════════════════════════════════════════
// Vídeo hospedado: foto/vídeo em destaque + barra fina no topo + toque → teatro → tela cheia
// ═══════════════════════════════════════════════════════════════════════════════
class _HostedVideoInlinePanel extends StatefulWidget {
  final String videoUrl;
  final String thumbUrl;
  final String title;
  final String dateStr;
  const _HostedVideoInlinePanel(
      {required this.videoUrl,
      required this.thumbUrl,
      required this.title,
      required this.dateStr});

  @override
  State<_HostedVideoInlinePanel> createState() =>
      _HostedVideoInlinePanelState();
}

class _HostedVideoInlinePanelState extends State<_HostedVideoInlinePanel> {
  bool _failed = false;
  bool _posterLoading = false;

  @override
  void initState() {
    super.initState();
    _posterLoading = false;
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _openFullscreen() async {
    if (!mounted) return;
    final t = sanitizeImageUrl(widget.thumbUrl);
    await showChurchHostedVideoDialog(
      context,
      videoUrl: widget.videoUrl,
      thumbnailUrl: isValidImageUrl(t) ? t : null,
      autoPlay: true,
      title: widget.title,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final safeThumb = sanitizeImageUrl(widget.thumbUrl);
    final useThumb = isValidImageUrl(safeThumb);
    final storageLikeThumb = useThumb &&
        (isFirebaseStorageHttpUrl(safeThumb) ||
            firebaseStorageMediaUrlLooksLike(safeThumb));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: const Color(0xFF0F172A),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                if (useThumb)
                  LayoutBuilder(
                    builder: (context, c) {
                      final w = c.maxWidth;
                      final h = c.maxHeight;
                      final dpr = MediaQuery.devicePixelRatioOf(context);
                      final memW = eventoAvisoMemCacheWidthPx(w, dpr);
                      final memH = eventoAvisoMemCacheHeightPx(h, dpr);
                      final ph = DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.grey.shade800,
                              const Color(0xFF0F172A)
                            ],
                          ),
                        ),
                        child: const Center(
                            child: SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white38))),
                      );
                      final err = DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [
                            Colors.grey.shade700,
                            const Color(0xFF0F172A)
                          ]),
                        ),
                        child: Center(
                            child: Icon(Icons.videocam_off_rounded,
                                color: Colors.white.withValues(alpha: 0.5),
                                size: 40)),
                      );
                      if (storageLikeThumb) {
                        return FreshFirebaseStorageImage(
                          key: ValueKey<String>('evt_vid_poster_$safeThumb'),
                          imageUrl: safeThumb,
                          fit: BoxFit.cover,
                          width: w,
                          height: h,
                          memCacheWidth: memW,
                          memCacheHeight: memH,
                          placeholder: ph,
                          errorWidget: err,
                        );
                      }
                      return SafeNetworkImage(
                        key: ValueKey(safeThumb),
                        imageUrl: safeThumb,
                        fit: BoxFit.cover,
                        width: w,
                        height: h,
                        memCacheWidth: memW,
                        memCacheHeight: memH,
                        placeholder: ph,
                        errorWidget: err,
                      );
                    },
                  )
                else if (_posterLoading)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.grey.shade800,
                        const Color(0xFF0F172A)
                      ]),
                    ),
                    child: const Center(
                        child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white38))),
                  )
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.grey.shade700,
                        const Color(0xFF0F172A)
                      ]),
                    ),
                    child: Center(
                        child: Icon(Icons.play_circle_outline_rounded,
                            color: Colors.white.withValues(alpha: 0.35),
                            size: 56)),
                  ),
                if (widget.title.isNotEmpty || widget.dateStr.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: _EventMediaOverlayBar(
                          title: widget.title, dateStr: widget.dateStr),
                    ),
                  ),
                if (_failed)
                  ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () async {
                          final u = Uri.tryParse(widget.videoUrl);
                          if (u != null && await canLaunchUrl(u)) {
                            await launchUrl(u,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        icon: const Icon(Icons.open_in_browser_rounded,
                            color: Colors.white, size: 20),
                        label: const Text('Abrir vídeo',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: IconButton(
                      tooltip: 'Tela cheia',
                      icon: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white, size: 22),
                      onPressed: _openFullscreen,
                      visualDensity: VisualDensity.compact,
                      constraints:
                          const BoxConstraints(minWidth: 44, minHeight: 44),
                    ),
                  ),
                ),
                if (!_failed && !_posterLoading)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openFullscreen,
                      child: Center(
                        child: Icon(Icons.play_circle_rounded,
                            size: 64,
                            color: Colors.white.withValues(alpha: 0.92)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
          child: Text(
            kIsWeb
                ? 'Controles do navegador · ícone Tela cheia para ampliar'
                : 'Toque no vídeo para abrir em tela cheia nesta mesma sessão',
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Bloco de vídeo do evento — Storage: player inline; link: feed → browser; galeria → teatro in-app
// ═══════════════════════════════════════════════════════════════════════════════
class _EventVideoBlock extends StatelessWidget {
  final String title, dateStr;
  final String hostedVideoUrl;
  final String externalLaunchUrl;
  final String thumbUrl;
  /// YouTube / link: no galeria abre teatro in-app; no feed mantém abrir no browser.
  final bool openExternalInTheater;

  const _EventVideoBlock({
    required this.title,
    required this.dateStr,
    this.hostedVideoUrl = '',
    this.externalLaunchUrl = '',
    this.thumbUrl = '',
    this.openExternalInTheater = false,
  });

  @override
  Widget build(BuildContext context) {
    if (hostedVideoUrl.isNotEmpty) {
      return _HostedVideoInlinePanel(
        videoUrl: hostedVideoUrl,
        thumbUrl: thumbUrl,
        title: title,
        dateStr: dateStr,
      );
    }

    final launch = externalLaunchUrl.trim();
    if (launch.isEmpty) {
      return const SizedBox.shrink();
    }
    final uri = Uri.tryParse(
        launch.startsWith('http://') || launch.startsWith('https://')
            ? launch
            : 'https://$launch');
    final safeThumb = sanitizeImageUrl(thumbUrl);
    final useThumb = isValidImageUrl(safeThumb);

    Future<void> openInBrowser() async {
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    void openTheater() {
      unawaited(
        showChurchHostedVideoTheater(
          context,
          videoUrl: launch,
          thumbnailUrl: useThumb ? safeThumb : null,
          title: title,
        ),
      );
    }

    void openImmersive() {
      unawaited(
        openChurchHostedVideoImmersive(
          context,
          videoUrl: launch,
          thumbnailUrl: useThumb ? safeThumb : null,
          title: title,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: const Color(0xFF1E3A8A),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            child: InkWell(
              onTap: openExternalInTheater ? openTheater : openInBrowser,
              child: useThumb
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        LayoutBuilder(
                          builder: (context, c) {
                            final w = c.maxWidth.isFinite && c.maxWidth > 0
                                ? c.maxWidth
                                : 400.0;
                            final h = c.maxHeight.isFinite && c.maxHeight > 0
                                ? c.maxHeight
                                : 225.0;
                            final dpr = MediaQuery.devicePixelRatioOf(context);
                            return SafeNetworkImage(
                              key: ValueKey(safeThumb),
                              imageUrl: safeThumb,
                              fit: BoxFit.cover,
                              width: w,
                              height: h,
                              memCacheWidth: eventoAvisoMemCacheWidthPx(w, dpr),
                              memCacheHeight: eventoAvisoMemCacheHeightPx(h, dpr),
                              placeholder: Container(
                                  color: const Color(0xFF1E3A8A),
                                  child: const Center(
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white54))),
                              errorWidget:
                                  _externalVideoFallback(title, dateStr),
                            );
                          },
                        ),
                        Container(color: Colors.black26),
                        if (title.isNotEmpty || dateStr.isNotEmpty)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: _EventMediaOverlayBar(
                                  title: title, dateStr: dateStr),
                            ),
                          ),
                        Center(
                            child: Icon(Icons.play_circle_rounded,
                                size: 64,
                                color: Colors.white.withValues(alpha: 0.95))),
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Material(
                            color: Colors.black54,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: openExternalInTheater
                                  ? 'Tela cheia no app'
                                  : 'Abrir no navegador',
                              icon: Icon(
                                openExternalInTheater
                                    ? Icons.fullscreen_rounded
                                    : Icons.open_in_new_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: openExternalInTheater
                                  ? openImmersive
                                  : openInBrowser,
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                  minWidth: 44, minHeight: 44),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _externalVideoFallback(title, dateStr),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            openExternalInTheater
                ? 'Toque no vídeo para pré-visualização; ícone no canto para tela cheia (sem abrir o navegador).'
                : 'Toque para abrir no navegador (YouTube / Vimeo)',
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  static Widget _externalVideoFallback(String title, String dateStr) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFF1E293B), const Color(0xFF0F172A)],
              ),
            ),
          ),
          if (title.isNotEmpty || dateStr.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _EventMediaOverlayBar(title: title, dateStr: dateStr),
              ),
            ),
          Center(
            child: Icon(Icons.play_circle_rounded,
                color: Colors.white.withValues(alpha: 0.88), size: 52),
          ),
        ],
      );
}

/// Erro de imagem no feed: fundo neutro + barra fina (sem faixa azul alta).
Widget _eventImageErrorWithOverlay(
    {required String title, required String dateStr}) {
  return Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: Colors.grey.shade300),
      if (title.isNotEmpty || dateStr.isNotEmpty)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _EventMediaOverlayBar(title: title, dateStr: dateStr),
        ),
      const Center(
          child:
              Icon(Icons.broken_image_rounded, size: 44, color: Colors.grey)),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Barra fina sobre foto/vídeo (título + data em uma linha) — estilo avisos / EcoFire
// ═══════════════════════════════════════════════════════════════════════════════
class _EventMediaOverlayBar extends StatelessWidget {
  final String title;
  final String dateStr;
  const _EventMediaOverlayBar({required this.title, required this.dateStr});

  @override
  Widget build(BuildContext context) {
    if (title.isEmpty && dateStr.isEmpty) return const SizedBox.shrink();
    final line = [
      if (title.isNotEmpty) title,
      if (dateStr.isNotEmpty) dateStr,
    ].join(' · ');
    return ClipRect(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.78),
              Colors.black.withValues(alpha: 0.4),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.event_rounded,
                color: Colors.white.withValues(alpha: 0.92), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  shadows: [
                    Shadow(
                        blurRadius: 10,
                        color: Colors.black.withValues(alpha: 0.65))
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

double? _eventPostParseDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v != null) return double.tryParse(v.toString());
  return null;
}

/// Links rápidos: convite (OG), site público da igreja e mapa (evento ou cadastro).
class _EventPostLinksRow extends StatelessWidget {
  final String tenantId;
  final String churchSlug;
  final Map<String, dynamic>? churchData;
  final String shareInviteUrl;
  final String eventLocation;
  final double? eventLat;
  final double? eventLng;

  const _EventPostLinksRow({
    required this.tenantId,
    required this.churchSlug,
    this.churchData,
    required this.shareInviteUrl,
    required this.eventLocation,
    this.eventLat,
    this.eventLng,
  });

  Widget _buildLinks(BuildContext context, Map<String, dynamic>? church) {
    final resolvedSlug = resolveChurchPublicSlug(
      churchSlug: churchSlug,
      tenantId: tenantId,
      churchData: church ?? churchData,
    );
    final publicSite = resolvedSlug.isNotEmpty
        ? AppConstants.publicChurchHomeUrl(resolvedSlug)
        : AppConstants.effectivePublicWebBaseUrl;
        double? lat = eventLat;
        double? lng = eventLng;
        if (church != null) {
          if (lat == null) lat = _eventPostParseDouble(church['latitude']);
          if (lng == null) lng = _eventPostParseDouble(church['longitude']);
        }
        String? mapsUrl;
        if (lat != null && lng != null) {
          mapsUrl = AppConstants.mapsShortUrl(lat: lat, lng: lng);
        } else if (eventLocation.trim().isNotEmpty) {
          mapsUrl = AppConstants.mapsShortUrl(address: eventLocation.trim());
        } else if (church != null) {
          final end = (church['endereco'] ?? '').toString().trim();
          if (end.isNotEmpty) {
            mapsUrl = AppConstants.mapsShortUrl(address: end);
          }
        }

        Future<void> open(String url) async {
          final u = Uri.tryParse(url);
          if (u != null && await canLaunchUrl(u)) {
            await launchUrl(u, mode: LaunchMode.externalApplication);
          }
        }

        Widget chip(
            {required IconData icon,
            required String label,
            required String url}) {
          return Material(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => open(url),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 18, color: ThemeCleanPremium.primary),
                    const SizedBox(width: 8),
                    Text(label,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Convite (link)',
                  url: shareInviteUrl),
              chip(
                  icon: Icons.public_rounded,
                  label: 'Site público',
                  url: publicSite),
              if (mapsUrl != null)
                chip(
                    icon: Icons.map_rounded,
                    label: 'Localização',
                    url: mapsUrl),
            ],
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    if (churchData != null) {
      return _buildLinks(context, churchData);
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          ChurchUiCollections.churchDoc(tenantId).get(),
      builder: (context, snap) {
        return _buildLinks(context, snap.data?.data());
      },
    );
  }
}

/// Limites da visualização ampliada (web / tablet largo) — imagem centrada, legível, sem “fullscreen” exagerado.
const double _kMuralLightboxMaxWidthWeb = 760;
const double _kMuralLightboxMaxHeightWeb = 520;
const double _kMuralLightboxMaxWidthTablet = 720;

/// Miniaturas na página de detalhe do evento (antes de abrir o lightbox).
SliverGridDelegate _muralDetailPhotosGridDelegate(double listViewportWidth) {
  final inner = max(200.0, listViewportWidth - 32);
  final maxExt = inner < 360
      ? (inner - 8) / 2
      : inner < 620
          ? (inner - 16) / 3
          : min(220.0, (inner - 24) / 4);
  return SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: max(115.0, maxExt),
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 0.92,
  );
}

// Galeria full screen: web usa HTTP+memory (FreshFirebaseStorageImage); fallback abrir no navegador.
class _ResilientGalleryImage extends StatelessWidget {
  final String imageUrl;
  const _ResilientGalleryImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final availH = (screenH -
            mq.padding.vertical -
            kToolbarHeight -
            28)
        .clamp(200.0, screenH);
    final wideLayout = screenW >= 560;
    final capWeb = kIsWeb || wideLayout;
    double lw = screenW - (capWeb ? 48 : 18);
    double lh = availH;
    if (capWeb) {
      lw = min(lw, kIsWeb ? _kMuralLightboxMaxWidthWeb : _kMuralLightboxMaxWidthTablet);
      lh = min(lh, kIsWeb ? _kMuralLightboxMaxHeightWeb : 560);
    } else {
      lh = min(lh, screenH * 0.88);
    }
    lw = max(120.0, lw);
    lh = max(160.0, lh);
    final dpr = mq.devicePixelRatio;
    final memW = (lw * dpr).round().clamp(64, 4096);
    final memH = (lh * dpr).round().clamp(64, 4096);
    return FreshFirebaseStorageImage(
      key: ValueKey(imageUrl),
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      width: lw,
      height: lh,
      memCacheWidth: memW,
      memCacheHeight: memH,
      placeholder: const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
        ),
      ),
      errorWidget: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_rounded, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text('Falha ao carregar',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () async {
                final u = Uri.tryParse(imageUrl.trim());
                if (u != null && await canLaunchUrl(u)) {
                  await launchUrl(u, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_browser_rounded,
                  color: Colors.white70),
              label: const Text('Abrir no navegador',
                  style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full Screen Gallery (zoom/pan)
// ═══════════════════════════════════════════════════════════════════════════════
class _FullScreenGallery extends StatefulWidget {
  final List<String> images;
  final int initial;
  const _FullScreenGallery({required this.images, this.initial = 0});

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initial;
    _ctrl = PageController(initialPage: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F14),
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.maybePop(context),
            tooltip: 'Voltar'),
        backgroundColor: const Color(0xB3000000),
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.images.length > 1
            ? Text(
                '${_current + 1} / ${widget.images.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: PageView.builder(
          controller: _ctrl,
          itemCount: widget.images.length,
          onPageChanged: (p) => setState(() => _current = p),
          itemBuilder: (_, i) {
            final raw = widget.images[i].trim();
            final url = sanitizeImageUrl(raw);
            final valid = url.startsWith('http://') ||
                url.startsWith('https://') ||
                url.toLowerCase().startsWith('gs://') ||
                firebaseStorageMediaUrlLooksLike(url);
            if (!valid) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_rounded,
                        size: 64, color: Colors.white54),
                    const SizedBox(height: 16),
                    Text('Imagem indisponível',
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ],
                ),
              );
            }
            return Center(
              child: InteractiveViewer(
                minScale: 0.65,
                maxScale: 4.0,
                boundaryMargin: const EdgeInsets.all(48),
                child: _ResilientGalleryImage(imageUrl: url),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Skeleton Loading
// ═══════════════════════════════════════════════════════════════════════════════
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
      child: YahwehSkeletonLoading.eventosFeed(postCount: 3),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Formulário de Evento (com múltiplas imagens)
// ═══════════════════════════════════════════════════════════════════════════════
class _EventoFormPage extends StatefulWidget {
  final String tenantId;
  final String resolvedTenantId;
  final CollectionReference<Map<String, dynamic>> noticias;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  const _EventoFormPage({
    required this.tenantId,
    required this.resolvedTenantId,
    required this.noticias,
    this.doc,
  });

  @override
  State<_EventoFormPage> createState() => _EventoFormPageState();
}

class _EventoFormPageState extends State<_EventoFormPage> {
  late TextEditingController _title, _videoUrl, _bodyDescription;
  late TextEditingController _cep,
      _logradouro,
      _numero,
      _bairro,
      _cidade,
      _uf,
      _quadraLote,
      _referencia;
  final List<String> _existingUrls = [];
  final List<Uint8List> _newImages = [];
  final List<String> _newImagePaths = [];
  final List<String> _newNames = [];
  int _inFlightPhotoUploads = 0;
  bool _eventDraftEnsured = false;
  final ValueNotifier<int> _addressPreviewTick = ValueNotifier(0);

  void _notifyAddressPreview() => _addressPreviewTick.value++;

  int get _newPhotoCount => kIsWeb ? _newImages.length : _newImagePaths.length;

  Future<void> _addEncodedEventPhoto(XFile encoded) async {
    final displayName = encoded.name.isNotEmpty
        ? encoded.name
        : 'foto.webp';
    Uint8List? webBytes;
    String? mobilePath;
    if (kIsWeb) {
      webBytes = await encoded.readAsBytes();
      if (!mounted) return;
      setState(() {
        _newImages.add(webBytes!);
        _newNames.add(displayName);
      });
    } else {
      final encodedPath = encoded.path.trim();
      if (encodedPath.isNotEmpty) {
        final existing = File(encodedPath);
        if (existing.existsSync() && existing.lengthSync() > 0) {
          mobilePath = encodedPath;
        }
      }
      mobilePath ??= await FeedEditorMediaService.persistXFileToTemp(
        encoded,
        prefix: 'gy_event',
      );
      if (mobilePath == null || !File(mobilePath).existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.errorSnackBarWithRetry(
              'Não foi possível preparar a foto. Tente outra imagem.',
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _newImagePaths.add(mobilePath!);
        _newNames.add(
          displayName.isNotEmpty ? displayName : mobilePath!.split('/').last,
        );
      });
    }
    if (!mounted) return;
    ImmediateMediaAttachFeedback.showArquivoAnexado(context, displayName);
  }

  void _removePendingEventPhotoFromLists({
    Uint8List? webBytes,
    String? mobilePath,
  }) {
    if (webBytes != null) {
      final i = _newImages.indexOf(webBytes);
      if (i >= 0) {
        _newImages.removeAt(i);
        if (i < _newNames.length) _newNames.removeAt(i);
      }
    } else if (mobilePath != null) {
      final i = _newImagePaths.indexOf(mobilePath);
      if (i >= 0) {
        _newImagePaths.removeAt(i);
        if (i < _newNames.length) _newNames.removeAt(i);
      }
    }
  }

  Future<void> _uploadAttachedEventPhotoInBackground({
    Uint8List? webBytes,
    String? mobilePath,
  }) async {
    if (!mounted) return;
    final slot = _existingUrls.length + _inFlightPhotoUploads;
    _inFlightPhotoUploads++;
    try {
      if (widget.doc == null && !_eventDraftEnsured) {
        await ImmediateFeedPhotoAttach.ensureDraftPost(
          docRef: _eventDocRef,
          isNewDoc: true,
          tenantId: _editorTenantId,
          postType: 'evento',
          title: _title.text,
        );
        _eventDraftEnsured = true;
      }
      final url = await ImmediateFeedPhotoAttach.uploadSingleSlot(
        tenantId: _editorTenantId,
        postType: 'evento',
        postId: _eventDocRef.id,
        slotIndex: slot,
        bytes: webBytes,
        localPath: mobilePath,
      );
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        setState(() {
          _removePendingEventPhotoFromLists(
            webBytes: webBytes,
            mobilePath: mobilePath,
          );
          _existingUrls.add(url);
        });
        if (mounted) {
          ImmediateMediaAttachFeedback.showEnviadoEVinculado(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(formatUploadErrorForUser(e)),
            backgroundColor: ThemeCleanPremium.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _inFlightPhotoUploads--);
      } else {
        _inFlightPhotoUploads--;
      }
    }
  }

  Future<List<Uint8List>> _copyNewImagesForPublish() async {
    if (kIsWeb) return List<Uint8List>.from(_newImages);
    final out = <Uint8List>[];
    for (final p in _newImagePaths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      out.add(await IosPublishImagePipeline.compressForPublishFromPath(p));
    }
    return out;
  }

  Future<Uint8List?> _firstNewImageBytes() async {
    if (kIsWeb) {
      return _newImages.isEmpty ? null : _newImages.first;
    }
    if (_newImagePaths.isEmpty) return null;
    final path = _newImagePaths.first;
    final f = File(path);
    if (!f.existsSync()) return null;
    return IosPublishImagePipeline.compressForPublishFromPath(path);
  }

  void _removeNewPhotoAt(int index) {
    setState(() {
      if (kIsWeb) {
        _newImages.removeAt(index);
      } else {
        _newImagePaths.removeAt(index);
      }
      _newNames.removeAt(index);
    });
  }

  /// Vídeos enviados (máx. 2): cada um com videoUrl e thumbUrl para carregamento rápido.
  final List<Map<String, String>> _eventVideos = [];
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  DateTime? _validUntil;
  bool _publicSite = true;
  bool _allDay = false;
  late DateTime _allDayEndDate;
  late DateTime _endDateTime;
  String? _eventCategoryId;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _categoryDocs = [];
  bool _loadingCategories = false;
  bool _firebaseBootstrapReady = false;
  String? _firebaseBootstrapError;
  bool _saving = false;
  bool _mediaPicking = false;
  bool _uploadingVideo = false;
  /// Evento já publicado (stub+fotos) enquanto o vídeo ainda sobe — merge ao concluir.
  bool _publishedAwaitingVideoMerge = false;
  /// null = a comprimir / a preparar; 0–1 = progresso real do upload ao Storage.
  double? _videoUploadFraction;
  bool _buscandoCep = false;
  bool _loadingChurchAddress = false;
  String? _operationalTenantId;

  String get _editorTenantId => ChurchPanelTenant.resolve(
        (_operationalTenantId ?? '').isNotEmpty
            ? _operationalTenantId
            : widget.resolvedTenantId,
      );

  /// Novo evento: mesmo id desde o init, para vídeos ficarem em paths estáveis `…/eventos/videos/{id}_v0.mp4`.
  late final DocumentReference<Map<String, dynamic>> _eventDocRef;

  /// Endereço da igreja (com lat/lng) vs. endereço manual por CEP.
  bool _useChurchLocation = false;
  String? _churchAddressText;
  double? _locationLat;
  double? _locationLng;
  static int get _maxVideoSeconds => kMediaEventVideoMaxSeconds;
  static const int _maxVideosPerEvent = FeedMediaPublishService.kMaxVideosPerPost;
  static const int _maxPhotosPerEvent = FeedMediaPublishService.kMaxPhotosPerEvento;

  static String _buildEnderecoFromTenant(Map<String, dynamic> data) {
    final endereco = (data['endereco'] ?? '').toString().trim();
    if (endereco.isNotEmpty) return endereco;
    final rua = (data['rua'] ?? data['address'] ?? '').toString().trim();
    final numero = (data['numero'] ?? '').toString().trim();
    final quadra = (data['quadraLoteNumero'] ??
            data['quadraLote'] ??
            data['quadra_lote'] ??
            '')
        .toString()
        .trim();
    final bairro = (data['bairro'] ?? '').toString().trim();
    final cidade =
        (data['cidade'] ?? data['localidade'] ?? '').toString().trim();
    final estado = (data['estado'] ?? data['uf'] ?? '').toString().trim();
    final cep = _onlyDigits((data['cep'] ?? '').toString());
    final parts = <String>[];
    if (rua.isNotEmpty) {
      parts.add(numero.isNotEmpty ? '$rua, Nº $numero' : rua);
    } else if (numero.isNotEmpty) {
      parts.add('Nº $numero');
    }
    if (quadra.isNotEmpty) parts.add('Qd/Lt $quadra');
    if (bairro.isNotEmpty) parts.add(bairro);
    if (cidade.isNotEmpty && estado.isNotEmpty) {
      parts.add('$cidade - $estado');
    } else if (cidade.isNotEmpty) {
      parts.add(cidade);
    } else if (estado.isNotEmpty) {
      parts.add(estado);
    }
    if (cep.length == 8) parts.add('CEP ${_formatCepDisplay(cep)}');
    return parts.join(', ');
  }

  void _fillManualFieldsFromTenant(Map<String, dynamic> data) {
    final cepDigits = _onlyDigits((data['cep'] ?? '').toString());
    if (cepDigits.length == 8) {
      _cep.text = _formatCepDisplay(cepDigits);
    }
    _logradouro.text =
        (data['rua'] ?? data['address'] ?? data['endereco'] ?? '')
            .toString()
            .trim();
    _numero.text = (data['numero'] ?? '').toString().trim();
    _bairro.text = (data['bairro'] ?? '').toString().trim();
    _cidade.text =
        (data['cidade'] ?? data['localidade'] ?? '').toString().trim();
    _uf.text = (data['estado'] ?? data['uf'] ?? '').toString().trim();
    _quadraLote.text = (data['quadraLoteNumero'] ??
            data['quadraLote'] ??
            data['quadra_lote'] ??
            '')
        .toString()
        .trim();
  }

  void _sairModoIgreja() {
    setState(() {
      _useChurchLocation = false;
      _churchAddressText = null;
      _locationLat = null;
      _locationLng = null;
    });
  }

  Future<void> _usarEnderecoIgreja() async {
    if (_loadingChurchAddress) return;
    setState(() => _loadingChurchAddress = true);
    try {
      final bundle = await ChurchTenantResilientReads.loadChurchAddressBundle(
        _editorTenantId,
        userUid: firebaseDefaultAuth.currentUser?.uid,
      );
      final data = bundle.tenantData;
      final endereco = _buildEnderecoFromTenant(data);
      if (endereco.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                'Cadastre o endereço da igreja em Cadastro da Igreja primeiro.'),
          );
        }
        return;
      }
      final lat = data['latitude'];
      final lng = data['longitude'];
      if (mounted) {
        setState(() {
          _operationalTenantId = bundle.firestoreTenantId;
          _useChurchLocation = true;
          _churchAddressText = endereco;
          _fillManualFieldsFromTenant(data);
          _locationLat = lat is num
              ? lat.toDouble()
              : (lat != null ? double.tryParse(lat.toString()) : null);
          _locationLng = lng is num
              ? lng.toDouble()
              : (lng != null ? double.tryParse(lng.toString()) : null);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Endereço da igreja aplicado. Use «Definir por CEP / manual» para outro local.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(
            'Não foi possível ler o endereço da igreja agora. '
            'Pode preencher o local manualmente ou tentar de novo.',
            onRetry: _usarEnderecoIgreja,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingChurchAddress = false);
    }
  }

  static String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String _formatCepDisplay(String digits) {
    final d = _onlyDigits(digits);
    if (d.length <= 5) return d;
    return '${d.substring(0, 5)}-${d.substring(5, d.length.clamp(5, 8))}';
  }

  String _montarEnderecoManual() {
    final parts = <String>[];
    final rua = _logradouro.text.trim();
    final nume = _numero.text.trim();
    if (rua.isNotEmpty) {
      parts.add(nume.isNotEmpty ? '$rua, Nº $nume' : rua);
    } else if (nume.isNotEmpty) {
      parts.add('Nº $nume');
    }
    final qd = _quadraLote.text.trim();
    if (qd.isNotEmpty) parts.add('Qd/Lt $qd');
    final bairro = _bairro.text.trim();
    if (bairro.isNotEmpty) parts.add(bairro);
    final cid = _cidade.text.trim();
    final uf = _uf.text.trim();
    if (cid.isNotEmpty && uf.isNotEmpty) {
      parts.add('$cid - $uf');
    } else if (cid.isNotEmpty) {
      parts.add(cid);
    } else if (uf.isNotEmpty) {
      parts.add(uf);
    }
    final cep = _onlyDigits(_cep.text);
    if (cep.length == 8) parts.add('CEP ${_formatCepDisplay(cep)}');
    final ref = _referencia.text.trim();
    if (ref.isNotEmpty) parts.add('Ref.: $ref');
    return parts.join(', ');
  }

  String _localSalvo() {
    if (_useChurchLocation && (_churchAddressText ?? '').trim().isNotEmpty) {
      return _churchAddressText!.trim();
    }
    return _montarEnderecoManual();
  }

  Future<void> _buscarCep() async {
    final cep = _onlyDigits(_cep.text);
    if (cep.length != 8) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Informe um CEP com 8 dígitos.'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
      }
      return;
    }
    setState(() => _buscandoCep = true);
    try {
      final uri = Uri.parse('https://viacep.com.br/ws/$cep/json/');
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      if (res.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('CEP: erro HTTP ${res.statusCode}'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
        return;
      }
      final j = jsonDecode(res.body);
      if (j is! Map || j['erro'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('CEP não encontrado.'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
        return;
      }
      setState(() {
        _useChurchLocation = false;
        _churchAddressText = null;
        _locationLat = null;
        _locationLng = null;
        _logradouro.text = (j['logradouro'] ?? '').toString();
        _bairro.text = (j['bairro'] ?? '').toString();
        _cidade.text = (j['localidade'] ?? '').toString();
        _uf.text = (j['uf'] ?? '').toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'CEP encontrado. Complete número, quadra/lote e ponto de referência se quiser.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao buscar CEP: $e'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _buscandoCep = false);
    }
  }

  Future<({DocumentReference<Map<String, dynamic>> docRef, String igrejaId})>
      _prepareEventoPublishContext() async {
    await EventoCreatePublishService.ensureReady(logLabel: 'evento_prepare');
    final igrejaId = EventoPublishService.resolveChurchId(
      (_operationalTenantId ?? '').isNotEmpty
          ? _operationalTenantId!
          : widget.resolvedTenantId.isNotEmpty
              ? widget.resolvedTenantId
              : widget.tenantId,
    );
    if (mounted) setState(() => _operationalTenantId = igrejaId);
    final docId = _eventDocRef.id;
    final docRef = EventoPublishService.docRef(
      churchId: igrejaId,
      docId: docId,
    );
    return (docRef: docRef, igrejaId: igrejaId);
  }

  String? _videoStoragePathForPublish(String igrejaId) {
    if (_eventVideos.isEmpty) return null;
    final stored = (_eventVideos.first['videoPath'] ?? '').toString().trim();
    if (stored.isNotEmpty) return stored;
    return EventosPublishVerificationService.hostedVideoStoragePath(
      igrejaId: igrejaId,
      eventoId: _eventDocRef.id,
      slot: 0,
    );
  }

  Future<void> _waitForVideoUploadComplete() async {
    const maxWait = Duration(minutes: 11);
    final deadline = DateTime.now().add(maxWait);
    while (_uploadingVideo && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (_uploadingVideo) {
      throw StateError(
        'O envio do vídeo demorou demais. Aguarde ou remova o vídeo e tente de novo.',
      );
    }
  }

  Future<void> _showEventoPublishVerifiedSuccess({required bool isNewDoc}) async {
    if (!mounted) return;
    unawaited(IosPublishMemory.releaseAfterHeavyWork());
    Navigator.pop(context, true);
  }

  @override
  void initState() {
    super.initState();
    _operationalTenantId = widget.resolvedTenantId.trim();
    _eventDocRef = widget.doc?.reference ?? widget.noticias.doc();
    final data = widget.doc?.data() ?? {};
    _title = TextEditingController(text: (data['title'] ?? '').toString());
    _bodyDescription = TextEditingController(
      text: churchPostPlainText(data),
    );
    _videoUrl =
        TextEditingController(text: (data['videoUrl'] ?? '').toString());
    _cep = TextEditingController();
    _logradouro = TextEditingController();
    _numero = TextEditingController();
    _bairro = TextEditingController();
    _cidade = TextEditingController();
    _uf = TextEditingController();
    _quadraLote = TextEditingController();
    _referencia = TextEditingController();

    final locChurch = data['eventLocationSource'] == 'church';
    if (locChurch && (data['location'] ?? '').toString().trim().isNotEmpty) {
      _useChurchLocation = true;
      _churchAddressText = (data['location'] ?? '').toString().trim();
    } else {
      _cep.text = _formatCepDisplay(
          _onlyDigits((data['locationCep'] ?? '').toString()));
      _logradouro.text = (data['locationLogradouro'] ?? '').toString();
      _numero.text = (data['locationNumero'] ?? '').toString();
      _bairro.text = (data['locationBairro'] ?? '').toString();
      _cidade.text = (data['locationCidade'] ?? '').toString();
      _uf.text = (data['locationUf'] ?? '').toString();
      _quadraLote.text = (data['locationQuadraLote'] ?? '').toString();
      _referencia.text = (data['locationReferencia'] ?? '').toString();
      if (_logradouro.text.isEmpty && _cep.text.isEmpty) {
        final legacy = (data['location'] ?? '').toString().trim();
        if (legacy.isNotEmpty) _logradouro.text = legacy;
      }
    }
    final videosRaw = data['videos'];
    if (videosRaw is List && videosRaw.isNotEmpty) {
      for (final e in videosRaw) {
        if (_eventVideos.length >= _maxVideosPerEvent) break;
        if (e is Map) {
          final vUrl =
              (e['videoUrl'] ?? e['video_url'] ?? '').toString().trim();
          if (vUrl.isNotEmpty)
            _eventVideos.add({
              'videoUrl': vUrl,
              'thumbUrl':
                  (e['thumbUrl'] ?? e['thumb_url'] ?? '').toString().trim()
            });
        }
      }
    } else if ((data['videoUrl'] ?? '').toString().trim().isNotEmpty) {
      _eventVideos.add({
        'videoUrl': (data['videoUrl'] ?? '').toString().trim(),
        'thumbUrl': (data['thumbUrl'] ?? '').toString().trim()
      });
    }
    final lat = data['locationLat'];
    final lng = data['locationLng'];
    _locationLat = lat is num
        ? lat.toDouble()
        : (lat != null ? double.tryParse(lat.toString()) : null);
    _locationLng = lng is num
        ? lng.toDouble()
        : (lng != null ? double.tryParse(lng.toString()) : null);
    // Mesma extração do feed/painel: imageUrls (lista ou lista de mapas), imageUrl, defaultImageUrl, fotos, etc.
    final urls = _eventImageUrlsFromData(data);
    _existingUrls.addAll(urls);
    try {
      _date = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    _allDayEndDate = DateTime(_date.year, _date.month, _date.day);
    _endDateTime = _date.add(const Duration(hours: 2));
    _allDay = data['allDay'] == true;
    try {
      final endRaw = (data['endAt'] as Timestamp?)?.toDate();
      if (_allDay) {
        if (endRaw != null) {
          _allDayEndDate =
              DateTime(endRaw.year, endRaw.month, endRaw.day);
        } else {
          _allDayEndDate = DateTime(_date.year, _date.month, _date.day);
        }
      } else if (endRaw != null) {
        _endDateTime = endRaw;
      }
    } catch (_) {}
    final cid = (data['eventCategoryId'] ?? '').toString().trim();
    _eventCategoryId = cid.isEmpty ? null : cid;
    try {
      final v = data['validUntil'];
      if (v is Timestamp) _validUntil = v.toDate();
    } catch (_) {}
    _publicSite = data['publicSite'] != false;
    unawaited(_bootstrapEventForm());
  }

  Future<void> _bootstrapEventForm() async {
    try {
      await EventoCreatePublishService.ensureReady(logLabel: 'evento_form');
      final tid = ChurchRepository.churchId(widget.tenantId);
      if (mounted) {
        setState(() {
          _operationalTenantId = tid.trim();
          _firebaseBootstrapReady = true;
          _firebaseBootstrapError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _firebaseBootstrapReady = false;
          _firebaseBootstrapError = formatUploadErrorForUser(e);
        });
      }
    }
    await _loadCategories();
  }

  String _agendaCategoryKeyFromEvent() {
    for (final c in _categoryDocs) {
      if (c.id == _eventCategoryId) {
        final nome = (c.data()['nome'] ?? '').toString().toLowerCase();
        if (nome.contains('culto')) return 'culto';
        if (nome.contains('líder') ||
            nome.contains('lider') ||
            nome.contains('reuni')) {
          return 'lideranca';
        }
        if (nome.contains('ebd') ||
            nome.contains('ensino') ||
            nome.contains('escola')) {
          return 'ensino_ebd';
        }
        return 'evento_social';
      }
    }
    return 'evento_social';
  }

  String _agendaColorHexForCategory() {
    for (final c in _categoryDocs) {
      if (c.id == _eventCategoryId) {
        final cor = c.data()['cor'];
        if (cor is int) {
          return '#${(cor & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
        }
      }
    }
    return '#E11D48';
  }

  Future<void> _upsertAgendaLinkedNoticia(String noticiaId) async {
    final (start, end) = _computeStartEndForSave();
    final cat = _agendaCategoryKeyFromEvent();
    final colorHex = _agendaColorHexForCategory();
    final agendaCol = ChurchUiCollections.agenda(_editorTenantId);
    final existing =
        await agendaCol.where('noticiaId', isEqualTo: noticiaId).limit(10).get();
    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _bodyDescription.text.trim(),
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'noticiaId': noticiaId,
      'category': cat,
      'color': colorHex,
      'location': _localSalvo(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = ChurchRepository.batch();
    if (existing.docs.isEmpty) {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdByUid'] = firebaseDefaultAuth.currentUser?.uid ?? '';
      batch.set(agendaCol.doc(), payload);
    } else {
      for (final d in existing.docs) {
        batch.set(d.reference, payload, SetOptions(merge: true));
      }
    }
    await batch.commit();
  }

  Future<void> _removeAgendaLinkedNoticia(String noticiaId) async {
    final q = await ChurchUiCollections.agenda(_editorTenantId)
        .where('noticiaId', isEqualTo: noticiaId)
        .get();
    final batch = ChurchRepository.batch();
    for (final d in q.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  Future<void> _applyAgendaSyncAfterSave(String postId) async {
    try {
      await ensureFirebaseReadyForPublishUpload();
      await _upsertAgendaLinkedNoticia(postId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calendário interno: $e'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final list = await ChurchEventosLoadService.loadEventCategories(
        seedTenantId: _editorTenantId,
      );
      if (mounted) {
        setState(() {
          _categoryDocs = list;
          _loadingCategories = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  (DateTime, DateTime) _computeStartEndForSave() {
    if (_allDay) {
      final s = DateTime(_date.year, _date.month, _date.day);
      final eDay = DateTime(
        _allDayEndDate.year,
        _allDayEndDate.month,
        _allDayEndDate.day,
      );
      if (eDay.isBefore(s)) {
        final end =
            DateTime(s.year, s.month, s.day, 23, 59, 59);
        return (s, end);
      }
      final end = DateTime(eDay.year, eDay.month, eDay.day, 23, 59, 59);
      return (s, end);
    }
    final start = _date;
    var end = _endDateTime;
    if (!end.isAfter(start)) {
      end = start.add(const Duration(hours: 2));
    }
    return (start, end);
  }

  Map<String, dynamic> _schedulingAndCategoryFields({required bool merge}) {
    final (start, end) = _computeStartEndForSave();
    final startTs = Timestamp.fromDate(start);
    final out = <String, dynamic>{
      'allDay': _allDay,
      'startAt': startTs,
      'endAt': Timestamp.fromDate(end),
      // dataEvento: índice da Agenda (sidebar); alinhado ao início do evento no mural.
      'dataEvento': startTs,
      'notifyLeaders': true,
      'notifyMembers': true,
    };
    if (_eventCategoryId != null && _eventCategoryId!.isNotEmpty) {
      QueryDocumentSnapshot<Map<String, dynamic>>? cat;
      for (final c in _categoryDocs) {
        if (c.id == _eventCategoryId) {
          cat = c;
          break;
        }
      }
      if (cat != null) {
        final d = cat.data();
        out['eventCategoryId'] = cat.id;
        out['eventCategoryName'] = (d['nome'] ?? '').toString();
        final cor = d['cor'];
        if (cor is int) out['eventCategoryColor'] = cor;
      }
    } else if (merge) {
      out['eventCategoryId'] = FieldValue.delete();
      out['eventCategoryName'] = FieldValue.delete();
      out['eventCategoryColor'] = FieldValue.delete();
    }
    return out;
  }

  Map<String, dynamic> _eventBodyFirestoreFields() {
    final plain = _bodyDescription.text.trim();
    return {
      'text': plain,
      kChurchPostTextDeltaKey: churchPostDeltaJsonFromPlainText(plain),
    };
  }

  @override
  void dispose() {
    _addressPreviewTick.dispose();
    _title.dispose();
    _bodyDescription.dispose();
    _videoUrl.dispose();
    _cep.dispose();
    _logradouro.dispose();
    _numero.dispose();
    _bairro.dispose();
    _cidade.dispose();
    _uf.dispose();
    _quadraLote.dispose();
    _referencia.dispose();
    super.dispose();
  }

  /// [allowDeleteSentinels] só pode ser true com `set(..., SetOptions(merge: true))` ou `update`.
  /// `add()` / `set` sem merge rejeitam [FieldValue.delete] — causa [cloud_firestore/invalid-argument].
  Map<String, dynamic> _locationFieldsForSave(
      {required bool allowDeleteSentinels}) {
    final del = FieldValue.delete();
    if (_useChurchLocation) {
      final m = <String, dynamic>{
        'location': _localSalvo(),
        'eventLocationSource': 'church',
      };
      if (allowDeleteSentinels) {
        m.addAll({
          'locationCep': del,
          'locationLogradouro': del,
          'locationNumero': del,
          'locationBairro': del,
          'locationCidade': del,
          'locationUf': del,
          'locationQuadraLote': del,
          'locationReferencia': del,
        });
      }
      if (_locationLat != null && _locationLng != null) {
        m['locationLat'] = _locationLat;
        m['locationLng'] = _locationLng;
      } else if (allowDeleteSentinels) {
        m['locationLat'] = del;
        m['locationLng'] = del;
      }
      return m;
    }
    final manual = <String, dynamic>{
      'location': _localSalvo(),
      'eventLocationSource': 'manual',
      'locationCep': _onlyDigits(_cep.text),
      'locationLogradouro': _logradouro.text.trim(),
      'locationNumero': _numero.text.trim(),
      'locationBairro': _bairro.text.trim(),
      'locationCidade': _cidade.text.trim(),
      'locationUf': _uf.text.trim().toUpperCase(),
      'locationQuadraLote': _quadraLote.text.trim(),
      'locationReferencia': _referencia.text.trim(),
    };
    if (allowDeleteSentinels) {
      manual['locationLat'] = del;
      manual['locationLng'] = del;
    }
    return manual;
  }

  Future<void> _pickImages() async {
    final totalAtual = _existingUrls.length + _newPhotoCount;
    if (totalAtual >= _maxPhotosPerEvent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Limite de $_maxPhotosPerEvent fotos por evento. Remova alguma para adicionar mais.'),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() => _mediaPicking = true);
    try {
      final remaining =
          (_maxPhotosPerEvent - totalAtual).clamp(1, _maxPhotosPerEvent);
      var encodeSkipped = 0;
      await MediaHandlerService.instance.pickMultiCropEncodeFeedWebpFromGallery(
        context,
        maxPickCount: remaining,
        webpOutputQuality: kEffectiveMuralFeedWebpQuality,
        onEachReady: (encoded, index, total) async {
          if (_existingUrls.length + _newPhotoCount >= _maxPhotosPerEvent) {
            return;
          }
          await _addEncodedEventPhoto(encoded);
        },
        onEncodeSkipped: (_, __) => encodeSkipped++,
      );
      if (encodeSkipped > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            encodeSkipped == 1
                ? 'Não foi possível preparar 1 foto. Tente outra imagem ou reinicie o app.'
                : 'Não foi possível preparar $encodeSkipped fotos. Tente outras imagens.',
          ),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(formatUploadErrorForUser(e)),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _mediaPicking = false);
    }
  }

  Future<void> _pickCamera() async {
    final totalAtual = _existingUrls.length + _newPhotoCount;
    if (totalAtual >= _maxPhotosPerEvent) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Limite de $_maxPhotosPerEvent fotos por evento. Remova alguma para adicionar mais.'),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() => _mediaPicking = true);
    try {
      final file = await MediaHandlerService.instance.pickCropEncodeFeedImageWebp(
        source: ImageSource.camera,
        webCropContext: context,
        webpOutputQuality: kEffectiveMuralFeedWebpQuality,
      );
      if (file != null && mounted) {
        await _addEncodedEventPhoto(file);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(formatUploadErrorForUser(e)),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _mediaPicking = false);
    }
  }

  /// Deriva caminhos `igrejas/...` a partir das URLs (só Firebase Storage HTTPS).
  List<String>? _pathsFromImageUrls(List<String> urls) {
    final paths = <String>[];
    for (final u in urls) {
      final s = sanitizeImageUrl(u.trim());
      if (!isValidImageUrl(s)) return null;
      final p = firebaseStorageObjectPathFromHttpUrl(s);
      if (p == null || p.isEmpty) return null;
      paths.add(normalizeFirebaseStorageObjectPath(p));
    }
    return paths;
  }

  Future<MediaUploadResult> _upload(
      Uint8List bytes, String postDocId, int slotIndex) async {
    await FeedPostMediaUpload.warmAuthToken();
    final storagePath = FeedTenantStorageMap.feedEventoPhotoPath(
      _editorTenantId,
      postDocId,
      slotIndex,
    );
    final webp = bytesLookLikeWebp(bytes);
    final prepared = webp
        ? await FeedPostMediaUpload.prepareFeedWebpBytes(bytes)
        : bytes;
    return MediaUploadService.uploadBytesDetailed(
      storagePath: storagePath,
      bytes: prepared,
      contentType: webp ? 'image/webp' : 'image/jpeg',
      skipClientPrepare: webp,
      useOfflineQueue: false,
      maxAttempts: 4,
    );
  }

  Widget _videoPlaceholder() => Container(
        width: 100,
        height: 100,
        color: Colors.grey.shade300,
        child: Icon(Icons.play_circle_outline_rounded,
            size: 40, color: Colors.grey.shade600),
      );

  /// Slot 0/1 explícito no path (`_v0.mp4`); legado sem sufixo → `null` (apenas apagar por URL).
  int? _hostedVideoStorageSlotFromUrl(String videoUrl) {
    final u = sanitizeImageUrl(videoUrl.trim());
    if (u.isEmpty || !isFirebaseStorageHttpUrl(u)) return null;
    final path = firebaseStorageObjectPathFromHttpUrl(u);
    if (path == null || path.isEmpty) return null;
    if (!path.contains('/eventos/videos/')) return null;
    final m = RegExp(r'_v(\d+)\.mp4$', caseSensitive: false).firstMatch(path);
    if (m != null) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null) return n.clamp(0, 1);
    }
    return null;
  }

  /// Próximo slot livre (0 ou 1). Vídeos legado em `videos/` sem `_vN` contam pelo índice na lista.
  int _nextHostedVideoStorageSlot() {
    final used = <int>{};
    for (var i = 0; i < _eventVideos.length; i++) {
      final url = (_eventVideos[i]['videoUrl'] ?? '').toString();
      final s = _hostedVideoStorageSlotFromUrl(url);
      if (s != null) {
        used.add(s);
      } else {
        final u = sanitizeImageUrl(url.trim());
        final p = firebaseStorageObjectPathFromHttpUrl(u) ?? '';
        if (u.isNotEmpty &&
            isFirebaseStorageHttpUrl(u) &&
            p.contains('/eventos/videos/')) {
          used.add(i.clamp(0, 1));
        }
      }
    }
    if (!used.contains(0)) return 0;
    if (!used.contains(1)) return 1;
    return -1;
  }

  Future<void> _removeEventVideoAt(int index) async {
    if (index < 0 || index >= _eventVideos.length) return;
    final v = _eventVideos[index];
    final videoUrl = (v['videoUrl'] ?? '').toString();
    final thumbUrl = (v['thumbUrl'] ?? '').toString();
    final slot = _hostedVideoStorageSlotFromUrl(videoUrl);
    if (slot != null) {
      await FirebaseStorageCleanupService.deleteEventHostedVideoSlotFiles(
        tenantId: _editorTenantId,
        postDocId: _eventDocRef.id,
        videoSlot: slot,
      );
    } else {
      await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
          [videoUrl, thumbUrl]);
    }
    if (mounted) setState(() => _eventVideos.removeAt(index));
  }

  Future<void> _pickAndUploadVideo() async {
    if (_uploadingVideo || _eventVideos.length >= _maxVideosPerEvent) {
      if (_eventVideos.length >= _maxVideosPerEvent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Limite atingido: cada evento pode ter no máximo $_maxVideosPerEvent vídeos de até $_maxVideoSeconds segundos.'),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    if (mounted) {
      setState(() {
        _uploadingVideo = true;
        _videoUploadFraction = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'A enviar vídeo… Aguarde concluir antes de publicar.',
        ),
      );
    }
    unawaited(runFirebaseBackgroundTask(() async {
      try {
        final snap = await _eventDocRef.get();
        final existing = _eventVideosFromData(snap.data() ?? {});
        if (existing.length >= _maxVideosPerEvent) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text(
                  'Este evento já atingiu o limite de 1 vídeo. Remova para adicionar outro.'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating,
            ));
          }
          return;
        }
        final slot = _nextHostedVideoStorageSlot();
        if (slot < 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'Limite de $_maxVideosPerEvent vídeos no Storage. Remova um vídeo para adicionar outro.'),
              backgroundColor: ThemeCleanPremium.error,
              behavior: SnackBarBehavior.floating,
            ));
          }
          return;
        }
        final result = await VideoHandlerService.instance
            .pickCompressAndUpload(
          tenantId: _editorTenantId,
          eventPostDocId: _eventDocRef.id,
          videoSlotIndex: slot,
          maxDuration: mediaEventVideoMaxDurationEffective,
          maxRawPickBytes:
              kIsWeb ? null : mediaEventVideoMobilePickMaxBytesEffective,
          onUploadProgress: (p) {
            if (!mounted) return;
            setState(() => _videoUploadFraction = p.clamp(0.0, 1.0));
          },
        )
            .timeout(
          const Duration(minutes: 10),
          onTimeout: () => throw TimeoutException(
            'O vídeo demorou demais. Remova-o, escolha um ficheiro menor ou publique só com fotos.',
          ),
        );
        if (result == null || !mounted) return;
        setState(() {
          _eventVideos.add({
            'videoPath': result.videoStoragePath,
            'thumbStoragePath': result.thumbStoragePath,
          });
        });
        if (_publishedAwaitingVideoMerge) {
          _publishedAwaitingVideoMerge = false;
          unawaited(_mergePublishedEventVideoFields());
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
              'Vídeo anexado (máx. ${_maxVideoSeconds}s).',
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(formatUploadErrorForUser(e)),
            backgroundColor: ThemeCleanPremium.error,
          ));
        }
      } finally {
        if (mounted) {
          setState(() {
            _uploadingVideo = false;
            _videoUploadFraction = null;
          });
        }
      }
    }, debugLabel: 'event_video_upload'));
  }

  Future<void> _openAddMediaSheet() async {
    if (_mediaPicking) return;
    final photosFull =
        (_existingUrls.length + _newPhotoCount) >= _maxPhotosPerEvent;
    final videosFull = _eventVideos.length >= _maxVideosPerEvent;
    if (photosFull && videosFull) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Limite atingido: $_maxPhotosPerEvent fotos e $_maxVideosPerEvent vídeos. Remova itens ou use o link abaixo.',
          ),
          backgroundColor: ThemeCleanPremium.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(ThemeCleanPremium.radiusMd + 4),
              boxShadow: ThemeCleanPremium.softUiCardShadow,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.workspace_premium_rounded,
                          color: ThemeCleanPremium.primary, size: 22),
                      const SizedBox(width: 8),
                      Text(
                        'Mídia premium',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.2,
                          color: Colors.grey.shade900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fotos: recorte + WebP (1080 px · 75%). Vídeo: até $_maxVideoSeconds s, máx. 15 MB no celular.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.grey.shade200,
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFF0FDF4),
                      child: Icon(Icons.photo_library_rounded,
                          color: Colors.green.shade700, size: 24),
                    ),
                    title: const Text('Fotos da galeria',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      photosFull
                          ? 'Limite de $_maxPhotosPerEvent fotos atingido'
                          : 'Várias imagens · recorte por foto',
                      style: TextStyle(
                        fontSize: 12,
                        color: photosFull
                            ? ThemeCleanPremium.error
                            : Colors.grey.shade600,
                      ),
                    ),
                    enabled: !photosFull && !_mediaPicking,
                    onTap: photosFull || _mediaPicking
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _pickImages();
                          },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.grey.shade200,
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.camera_alt_rounded,
                          color: ThemeCleanPremium.primary, size: 24),
                    ),
                    title: const Text('Tirar foto',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      photosFull
                          ? 'Limite de fotos atingido'
                          : 'Câmera · uma foto com recorte',
                      style: TextStyle(
                        fontSize: 12,
                        color: photosFull
                            ? ThemeCleanPremium.error
                            : Colors.grey.shade600,
                      ),
                    ),
                    enabled: !photosFull && !_mediaPicking,
                    onTap: photosFull || _mediaPicking
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _pickCamera();
                          },
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: Colors.grey.shade200,
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.videocam_rounded,
                          color: ThemeCleanPremium.primary, size: 24),
                    ),
                    title: const Text('Vídeo (arquivo)',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      _uploadingVideo
                          ? 'Aguarde o envio em andamento…'
                          : videosFull
                              ? 'Máx. $_maxVideosPerEvent vídeos por evento'
                              : 'Até $_maxVideoSeconds s — MP4 leve envia direto; senão 720p HD',
                      style: TextStyle(
                        fontSize: 12,
                        color: (_uploadingVideo || videosFull)
                            ? Colors.grey.shade500
                            : Colors.grey.shade600,
                      ),
                    ),
                    enabled: !_uploadingVideo && !videosFull,
                    onTap: (_uploadingVideo || videosFull)
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _pickAndUploadVideo();
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double? _aspectRatioFromBytes(Uint8List bytes) {
    try {
      final im = img.decodeImage(bytes);
      if (im == null || im.height <= 0) return null;
      return im.width / im.height;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _buildEventCorePayload({
    required List<String> allUrls,
    required double? aspectRatio,
    required bool isNewDoc,
  }) {
    final allUrlsSafe =
        allUrls.where((u) => !looksLikeHostedVideoFileUrl(u.trim())).toList();
    final firstVideoUrl = _eventVideos.isNotEmpty
        ? (_eventVideos.first['videoUrl'] ?? '')
        : _videoUrl.text.trim();
    final firstThumbUrl =
        _eventVideos.isNotEmpty ? (_eventVideos.first['thumbUrl'] ?? '') : '';
    final videosClean = _eventVideos
        .map((e) => <String, dynamic>{
              'videoUrl': (e['videoUrl'] ?? '').toString().trim(),
              'thumbUrl': (e['thumbUrl'] ?? '').toString().trim(),
            })
        .where((m) => (m['videoUrl'] as String).isNotEmpty)
        .toList();
    final hasVideo = firstVideoUrl.toString().trim().isNotEmpty;
    final ar = (aspectRatio ?? 1.0).clamp(0.45, 1.9);

    final fotoPaths = EventosPublishVerificationService.storagePathsFromUrls(
      allUrlsSafe,
    );
    final videoPath = _eventVideos.isNotEmpty
        ? EventosPublishVerificationService.hostedVideoStoragePath(
            igrejaId: _editorTenantId,
            eventoId: _eventDocRef.id,
            slot: 0,
          )
        : null;

    final payload = <String, dynamic>{
      'type': 'evento',
      'title': _title.text.trim(),
      ..._eventBodyFirestoreFields(),
      'videoUrl': firstVideoUrl,
      'thumbUrl': firstThumbUrl,
      'videos': videosClean,
      'fotos': fotoPaths,
      if (videoPath != null && videoPath.isNotEmpty) 'videoPath': videoPath,
      'ativo': true,
      'publicado': true,
      'status': 'publicado',
      'active': true,
      'likes': widget.doc?.data()?['likes'] ?? <String>[],
      'rsvp': widget.doc?.data()?['rsvp'] ?? <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
      'generated': false,
      'publicSite': _publicSite,
      'galleryPermanent': false,
      ..._schedulingAndCategoryFields(merge: !isNewDoc),
      ..._locationFieldsForSave(allowDeleteSentinels: !isNewDoc),
      ...MuralPostMediaPayload.buildMediaFields(
        allUrls: allUrlsSafe,
        aspectRatio: ar,
        hasVideo: hasVideo,
        allowDeleteSentinels: !isNewDoc,
      ),
    };
    if (_validUntil != null) {
      payload['validUntil'] = Timestamp.fromDate(_validUntil!);
    }
    if (!isNewDoc) {
      payload['imageVariants'] = FieldValue.delete();
      payload['templateId'] = FieldValue.delete();
      if (widget.doc!.data()?['createdAt'] == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }
    } else {
      payload['createdAt'] = FieldValue.serverTimestamp();
      payload['createdByUid'] = firebaseDefaultAuth.currentUser?.uid ?? '';
      payload['likesCount'] = 0;
      payload['rsvpCount'] = 0;
      payload['commentsCount'] = 0;
    }
    return payload;
  }

  Future<void> _mergePublishedEventVideoFields() async {
    try {
      await runFirebaseBackgroundTask(() async {
      final firstVideoUrl = _eventVideos.isNotEmpty
          ? (_eventVideos.first['videoUrl'] ?? '').toString().trim()
          : _videoUrl.text.trim();
      if (firstVideoUrl.isEmpty) return;
      final firstThumbUrl = _eventVideos.isNotEmpty
          ? (_eventVideos.first['thumbUrl'] ?? '').toString().trim()
          : '';
      final videosClean = _eventVideos
          .map((e) => <String, dynamic>{
                'videoUrl': (e['videoUrl'] ?? '').toString().trim(),
                'thumbUrl': (e['thumbUrl'] ?? '').toString().trim(),
              })
          .where((m) => (m['videoUrl'] as String).isNotEmpty)
          .toList();
      await _eventDocRef.set(
        {
          'videoUrl': firstVideoUrl,
          'thumbUrl': firstThumbUrl,
          'videos': videosClean,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      PublicationEngine.scheduleDistribution(
        tenantId: widget.tenantId,
        kind: PublicationKind.evento,
        postId: _eventDocRef.id,
        isNewDoc: false,
        publicSite: _publicSite,
        phase: PublicationDistributionPhase.afterMediaFinalized,
      );
      }, debugLabel: 'event_video_merge');
    } catch (_) {}
  }

  /// Reconexão após INTERNAL ASSERTION — mesmo pipeline linear (upload → Firestore).
  Future<void> _retryEventPublishFirestoreFirst() async {
    await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
    await _waitForVideoUploadComplete();
    final ctx = await _prepareEventoPublishContext();
    final docRef = ctx.docRef;
    final publishTenantId = ctx.igrejaId;
    final isNewDoc = widget.doc == null && !_eventDraftEnsured;
    await _waitForInFlightPhotoUploads();
    final pending = _pendingEventPhotosForPublish();
    final existingUrls = dedupeImageRefsByStorageIdentity(_existingUrls);
    double? aspectRatio;
    if (existingUrls.isNotEmpty) {
      final prev = widget.doc?.data()?['media_info'];
      if (prev is Map) {
        final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
        if (oar is num) aspectRatio = oar.toDouble();
      }
    }
    final videoPathForPublish = _videoStoragePathForPublish(publishTenantId);
    final hasVideo = videoPathForPublish != null &&
        videoPathForPublish.isNotEmpty;
    final (eventStart, _) = _computeStartEndForSave();
    final payload = _buildEventCorePayload(
      allUrls: existingUrls,
      aspectRatio: aspectRatio,
      isNewDoc: isNewDoc,
    );
    payload.remove('videoUrl');
    await EventoCreatePublishService.publish(
      docRef: docRef,
      tenantId: publishTenantId,
      corePayload: payload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      startSlotIndex: existingUrls.length,
      hasVideo: hasVideo,
      newImagesBytes: pending.bytes,
      newImagePaths: pending.paths,
      videoStoragePath: videoPathForPublish,
      publicSite: _publicSite,
      eventStartAt: eventStart,
      location: _localSalvo(),
      agendaCategory: _agendaCategoryKeyFromEvent(),
      agendaColorHex: _agendaColorHexForCategory(),
    );
  }

  Future<void> _waitForInFlightPhotoUploads() async {
    const maxWait = Duration(seconds: 90);
    final deadline = DateTime.now().add(maxWait);
    while (_inFlightPhotoUploads > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (_inFlightPhotoUploads > 0) {
      throw StateError(
        'Ainda a enviar fotos. Aguarde o vínculo ao Storage e tente de novo.',
      );
    }
  }

  /// Fotos pendentes (só enviadas ao clicar em Publicar).
  ({List<Uint8List>? bytes, List<String>? paths}) _pendingEventPhotosForPublish() {
    if (kIsWeb) {
      if (_newImages.isEmpty) return (bytes: null, paths: null);
      return (bytes: List<Uint8List>.from(_newImages), paths: null);
    }
    final paths = FeedEditorMediaService.existingValidPaths(_newImagePaths);
    if (paths.isEmpty) return (bytes: null, paths: null);
    return (bytes: null, paths: paths);
  }

  void _clearPendingEventPhotosAfterPublish() {
    if (!mounted) return;
    setState(() {
      _newImages.clear();
      _newImagePaths.clear();
      _newNames.clear();
    });
  }

  void _openEventEditorPhotoLightbox({
    required List<String> urls,
    required int initialIndex,
    List<Uint8List>? localBytes,
    List<String>? localPaths,
  }) {
    final network = urls.where((u) => u.trim().isNotEmpty).toList();
    if (network.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _FullScreenGallery(
            images: network,
            initial: initialIndex.clamp(0, network.length - 1),
          ),
        ),
      );
      return;
    }
    if (localBytes != null &&
        initialIndex >= 0 &&
        initialIndex < localBytes.length) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.memory(
                  localBytes[initialIndex],
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_mediaPicking) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Aguarde a preparação das fotos terminar.',
        ),
      );
      return;
    }
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe o título.')));
      return;
    }
    setState(() => _saving = true);
    final isNewDoc = widget.doc == null && !_eventDraftEnsured;
    final uid = firebaseDefaultAuth.currentUser?.uid ?? '';
    final titulo = _title.text.trim();
    try {
      await EventoCreatePublishService.ensureReady(logLabel: 'evento_save');
      ChurchPublishFlowLog.eventoStart();
      final ctx = await _prepareEventoPublishContext();
      final docRef = ctx.docRef;
      final publishTenantId = ctx.igrejaId;
      final postId = docRef.id;

      await _waitForInFlightPhotoUploads();
      final pending = _pendingEventPhotosForPublish();

      unawaited(
        EventosPublishVerificationService.logPublishPhase(
          phase: 'before',
          igrejaId: publishTenantId,
          uid: uid,
          titulo: titulo,
          eventoId: postId,
          fotos: EventosPublishVerificationService.storagePathsFromUrls(
            _existingUrls,
          ),
          videoPath: _videoStoragePathForPublish(publishTenantId),
        ),
      );

      final existingUrls = dedupeImageRefsByStorageIdentity(_existingUrls);
      double? aspectRatio;
      if (existingUrls.isNotEmpty) {
        final prev = widget.doc?.data()?['media_info'];
        if (prev is Map) {
          final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
          if (oar is num) aspectRatio = oar.toDouble();
        }
      }
      final videoPathForPublish = _videoStoragePathForPublish(publishTenantId);
      final hasVideo = videoPathForPublish != null &&
          videoPathForPublish.isNotEmpty;
      final (eventStart, _) = _computeStartEndForSave();
      final payload = _buildEventCorePayload(
        allUrls: existingUrls,
        aspectRatio: aspectRatio,
        isNewDoc: isNewDoc,
      );
      payload.remove('videoUrl');

      await EventoCreatePublishService.publish(
        docRef: docRef,
        tenantId: publishTenantId,
        corePayload: payload,
        isNewDoc: isNewDoc,
        existingUrls: existingUrls,
        startSlotIndex: existingUrls.length,
        hasVideo: hasVideo,
        newImagesBytes: pending.bytes,
        newImagePaths: pending.paths,
        videoStoragePath: videoPathForPublish,
        publicSite: _publicSite,
        eventStartAt: eventStart,
        location: _localSalvo(),
        agendaCategory: _agendaCategoryKeyFromEvent(),
        agendaColorHex: _agendaColorHexForCategory(),
      );

      _clearPendingEventPhotosAfterPublish();

      unawaited(
        EventosPublishVerificationService.logPublishPhase(
          phase: 'after',
          igrejaId: publishTenantId,
          uid: uid,
          titulo: titulo,
          eventoId: postId,
        ),
      );
      EventosPublishVerificationService.clearLastError();
      await _showEventoPublishVerifiedSuccess(isNewDoc: isNewDoc);
    } catch (e, st) {
      ChurchPublishFlowLog.logCatch(e, st, label: 'evento_save');
      EventosPublishVerificationService.rememberLastError(e);
      unawaited(
        EventosPublishVerificationService.logPublishPhase(
          phase: 'error',
          igrejaId: _editorTenantId,
          uid: uid,
          titulo: titulo,
          eventoId: _eventDocRef.id,
          erro: e,
        ),
      );
      unawaited(CrashlyticsService.record(e, st, reason: 'eventos_publish'));
      final msg = e.toString();
      final isAssertionOrPerm = msg.contains('INTERNAL ASSERTION') ||
          msg.contains('permission-denied') ||
          msg.contains('WatchChangeAggregator') ||
          msg.contains('PersistentListenStream') ||
          msg.contains('Unexpected state') ||
          msg.contains('core/no-app') ||
          isFirebaseNoAppError(e);
      final verifyFailed =
          msg.contains('Documento não localizado no Firestore') ||
              msg.contains(EventosPublishVerificationService
                  .kPublishVerifyFailedMessage) ||
              msg.contains(EventosPublishVerificationService
                  .kStorageVerifyFailedMessage);
      if (mounted && isAssertionOrPerm) {
        try {
          await _retryEventPublishFirestoreFirst();
          final verifyCtx = await _prepareEventoPublishContext();
          await EventosPublishVerificationService.verifyDocumentExists(
            verifyCtx.docRef,
          );
          EventosPublishVerificationService.clearLastError();
          _clearPendingEventPhotosAfterPublish();
          await _showEventoPublishVerifiedSuccess(isNewDoc: isNewDoc);
          unawaited(_applyAgendaSyncAfterSave(_eventDocRef.id));
        } catch (e2, st2) {
          ChurchPublishFlowLog.logCatch(e2, st2, label: 'evento_retry');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(formatUploadErrorForUser(e2)),
              backgroundColor: ThemeCleanPremium.error,
            ));
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              verifyFailed
                  ? (msg.contains('Storage')
                      ? EventosPublishVerificationService
                          .kStorageVerifyFailedMessage
                      : EventosPublishVerificationService
                          .kPublishVerifyFailedMessage)
                  : formatUploadErrorForUser(e),
            ),
            backgroundColor: ThemeCleanPremium.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveDraft() async {
    if (_saving) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe o título.')));
      return;
    }
    setState(() => _saving = true);
    final docRef = _eventDocRef;
    final isNewDoc = widget.doc == null && !_eventDraftEnsured;
    try {
      await EventoCreatePublishService.ensureReady(logLabel: 'evento_draft');
      await runFirebaseBackgroundTask(() async {
      final existingUrls = dedupeImageRefsByStorageIdentity(_existingUrls);
      double? aspectRatio;
      if (existingUrls.isNotEmpty) {
        final prev = widget.doc?.data()?['media_info'];
        if (prev is Map) {
          final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
          if (oar is num) aspectRatio = oar.toDouble();
        }
      }
      final payload = _buildEventCorePayload(
        allUrls: existingUrls,
        aspectRatio: aspectRatio,
        isNewDoc: isNewDoc,
      );
      await FeedMediaPublishService.saveDraft(
        docRef: docRef,
        payload: payload,
        isNewDoc: isNewDoc,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Rascunho guardado'),
        );
        Navigator.pop(context, true);
      }
      }, debugLabel: 'event_draft');
    } catch (e, st) {
      unawaited(CrashlyticsService.record(e, st, reason: 'eventos_draft'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(formatUploadErrorForUser(e)),
          backgroundColor: ThemeCleanPremium.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPreviews = <Widget>[];
    for (var i = 0; i < _existingUrls.length; i++) {
      final idx = i;
      allPreviews.add(Stack(children: [
        GestureDetector(
          onTap: () => _openEventEditorPhotoLightbox(
            urls: _existingUrls,
            initialIndex: idx,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SafeNetworkImage(
                imageUrl: _existingUrls[idx],
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                placeholder: Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade200,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))),
                errorWidget: Container(
                    width: 100,
                    height: 100,
                    color: Colors.grey.shade300,
                    child: const Icon(Icons.broken_image_rounded,
                        color: Colors.grey))),
          ),
        ),
        Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
                onTap: () => setState(() => _existingUrls.removeAt(idx)),
                child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white)))),
      ]));
    }
    for (var i = 0; i < _newPhotoCount; i++) {
      final idx = i;
      final thumbChild = kIsWeb
          ? feedEditorLocalPhotoThumb(
              webBytes: _newImages[idx],
              mobilePath: null,
              size: 100,
            )
          : feedEditorLocalPhotoThumb(
              webBytes: null,
              mobilePath: _newImagePaths[idx],
              size: 100,
            );
      allPreviews.add(Stack(children: [
        GestureDetector(
          onTap: () => _openEventEditorPhotoLightbox(
            urls: const [],
            initialIndex: idx,
            localBytes: kIsWeb ? _newImages : null,
            localPaths: kIsWeb ? null : _newImagePaths,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: thumbChild,
          ),
        ),
        Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
                onTap: () => _removeNewPhotoAt(idx),
                child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close,
                        size: 14, color: Colors.white)))),
      ]));
    }

    final padding = ThemeCleanPremium.pagePadding(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final minTouch = ThemeCleanPremium.minTouchTarget;
    final publishLabel = widget.doc != null ? 'Atualizar Evento' : 'Publicar Evento';

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        toolbarHeight: 56,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFDB2777)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(minimumSize: Size(minTouch, minTouch)),
        ),
        title: Text(widget.doc != null ? 'Editar Evento' : 'Novo Evento',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: Material(
        elevation: 14,
        shadowColor: const Color(0x59000000),
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              10,
              padding.right,
              10 + bottomInset,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: ThemeCleanPremium.minTouchTarget,
                  child: FilledButton.tonalIcon(
                    onPressed: (_mediaPicking || _saving) ? null : _openAddMediaSheet,
                    icon: const Icon(Icons.add_photo_alternate_rounded, size: 22),
                    label: Text(
                      'Adicionar foto ou vídeo (${_existingUrls.length + _newPhotoCount + _eventVideos.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          ThemeCleanPremium.primary.withValues(alpha: 0.12),
                      foregroundColor: ThemeCleanPremium.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusMd),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: ThemeCleanPremium.minTouchTarget,
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _saveDraft,
                    icon: const Icon(Icons.drive_file_rename_outline_rounded,
                        size: 20),
                    label: const Text(
                      'Guardar rascunho',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ThemeCleanPremium.onSurfaceVariant,
                      side: BorderSide(
                        color: ThemeCleanPremium.onSurfaceVariant
                            .withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                            ThemeCleanPremium.radiusMd),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: ThemeCleanPremium.minTouchTarget + 8,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.maybePop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ThemeCleanPremium.primary,
                        side: BorderSide(
                          color: ThemeCleanPremium.primary
                              .withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Cancelar',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: (_saving || _mediaPicking) ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded, size: 22),
                      label: Text(
                        _saving ? 'A guardar…' : publishLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1D4ED8),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
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
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(padding.left, padding.top, padding.right,
              padding.bottom + bottomInset),
          children: [
            AsyncUploadProgressStrip(
              localActive: _mediaPicking || _uploadingVideo || _saving,
              localLabel: _uploadingVideo
                  ? 'A enviar vídeo…'
                  : (_mediaPicking
                      ? 'A preparar fotos…'
                      : 'A publicar evento…'),
            ),
            if (_firebaseBootstrapError != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ThemeCleanPremium.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ThemeCleanPremium.error),
                ),
                child: Text(
                  _firebaseBootstrapError!,
                  style: TextStyle(
                    color: ThemeCleanPremium.error,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ] else if (!_firebaseBootstrapReady) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 3),
            ],
            const SizedBox(height: 10),
            // Mídia no topo (fotos + vídeos antes dos campos de texto).
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusMd),
                border: Border.all(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.perm_media_rounded,
                          color: ThemeCleanPremium.primary, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Fotos e vídeos do evento',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: Colors.grey.shade900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    kIsWeb
                        ? 'Fotos comprimidas no dispositivo (1080 px). Vídeos até $_maxVideoSeconds s.'
                        : 'Fotos leves no celular (1080 px · 75%). Vídeos até $_maxVideoSeconds s e máx. 15 MB — acima disso o app bloqueia para não travar.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (_uploadingVideo) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _videoUploadFraction,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _videoUploadFraction == null
                          ? 'A preparar vídeo…'
                          : 'A enviar vídeo… ${((_videoUploadFraction ?? 0) * 100).round()}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                  if (allPreviews.isNotEmpty || _eventVideos.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      ...allPreviews,
                      ...List.generate(_eventVideos.length, (i) {
                        final v = _eventVideos[i];
                        final thumbUrl = v['thumbUrl'] ?? '';
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: thumbUrl.isNotEmpty &&
                                      isValidImageUrl(thumbUrl)
                                  ? SafeNetworkImage(
                                      imageUrl: thumbUrl,
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                      placeholder: Container(
                                        width: 100,
                                        height: 100,
                                        color: Colors.grey.shade200,
                                        child: const Center(
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                      ),
                                      errorWidget: _videoPlaceholder(),
                                    )
                                  : _videoPlaceholder(),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => unawaited(_removeEventVideoAt(i)),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close,
                                      size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Fields
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow),
              child: Column(children: [
                TextField(
                    controller: _title,
                    autocorrect: true,
                    enableSuggestions: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                        labelText: 'Título do evento *',
                        prefixIcon: Icon(Icons.title_rounded))),
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.article_outlined,
                          size: 20,
                          color:
                              ThemeCleanPremium.primary.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Descrição / divulgação',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Texto simples — sem negrito nem cores no editor. '
                      'O mural e o site continuam a mostrar o conteúdo normalmente.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bodyDescription,
                      maxLines: null,
                      minLines: 8,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      autocorrect: true,
                      enableSuggestions: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        alignLabelWithHint: true,
                        hintText:
                            'Convite, horários, local, link… Use Enter para parágrafos.',
                        contentPadding: const EdgeInsets.fromLTRB(
                            14, 14, 14, 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                              ThemeCleanPremium.radiusMd),
                          borderSide: BorderSide(
                            color: ThemeCleanPremium.primary
                                .withValues(alpha: 0.75),
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _videoUrl,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Link do vídeo (YouTube / Vimeo)',
                    prefixIcon: Icon(Icons.link_rounded),
                    hintText: 'https://...',
                    helperText:
                        'Opcional. Use o botão inferior para foto/vídeo em arquivo.',
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 22,
                        color: ThemeCleanPremium.primary.withOpacity(0.85)),
                    const SizedBox(width: 8),
                    Text('Data, horário e categoria',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Colors.grey.shade800)),
                  ],
                ),
                const SizedBox(height: 10),
                if (_loadingCategories)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                DropdownButtonFormField<String?>(
                  value: _eventCategoryId != null &&
                          _categoryDocs.any((c) => c.id == _eventCategoryId)
                      ? _eventCategoryId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Categoria',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sem categoria'),
                    ),
                    ..._categoryDocs.map((c) {
                      final n = (c.data()['nome'] ?? c.id).toString();
                      final cor = c.data()['cor'];
                      final col = cor is int
                          ? Color(cor)
                          : ThemeCleanPremium.primary;
                      return DropdownMenuItem<String?>(
                        value: c.id,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: col,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: Text(n)),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (v) => setState(() => _eventCategoryId = v),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (ctx) => _EventCategoriesManagerSheet(
                          tenantId: widget.tenantId,
                        ),
                      );
                      await _loadCategories();
                    },
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    label: const Text('Gerir categorias'),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _allDay,
                  onChanged: (v) => setState(() {
                    _allDay = v;
                    if (v) {
                      _allDayEndDate =
                          DateTime(_date.year, _date.month, _date.day);
                    }
                  }),
                  title: const Text('Dia inteiro'),
                  subtitle: Text(
                    'Marca o(s) dia(s) completo(s) na agenda colorida.',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  secondary: const Icon(Icons.calendar_view_day_rounded),
                ),
                if (_allDay) ...[
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime.now()
                                .subtract(const Duration(days: 365)),
                            lastDate:
                                DateTime.now().add(const Duration(days: 730)),
                            locale: const Locale('pt', 'BR'),
                          );
                          if (d != null && mounted) {
                            setState(() {
                              _date = DateTime(
                                  d.year, d.month, d.day, 12, 0);
                              final startDay =
                                  DateTime(d.year, d.month, d.day);
                              if (_allDayEndDate.isBefore(startDay)) {
                                _allDayEndDate = startDay;
                              }
                            });
                          }
                        },
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(
                          'Início: ${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final first =
                              DateTime(_date.year, _date.month, _date.day);
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _allDayEndDate.isBefore(first)
                                ? first
                                : _allDayEndDate,
                            firstDate: first,
                            lastDate:
                                DateTime.now().add(const Duration(days: 730)),
                            locale: const Locale('pt', 'BR'),
                          );
                          if (d != null && mounted) {
                            setState(() => _allDayEndDate =
                                DateTime(d.year, d.month, d.day));
                          }
                        },
                        icon: const Icon(Icons.event_repeat_rounded, size: 18),
                        label: Text(
                          'Fim: ${_allDayEndDate.day.toString().padLeft(2, '0')}/${_allDayEndDate.month.toString().padLeft(2, '0')}/${_allDayEndDate.year}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ]),
                ] else ...[
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 365)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 730)),
                        locale: const Locale('pt', 'BR'),
                        helpText: 'Data de início',
                        cancelText: 'Cancelar',
                        confirmText: 'OK',
                      );
                      if (d != null && mounted) {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_date),
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          ),
                          helpText: 'Horário de início',
                          cancelText: 'Cancelar',
                          confirmText: 'OK',
                        );
                        if (t != null && mounted) {
                          setState(() => _date = DateTime(
                              d.year, d.month, d.day, t.hour, t.minute));
                        }
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Início',
                        prefixIcon: Icon(Icons.calendar_month_rounded),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year} ${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _endDateTime,
                        firstDate: _date,
                        lastDate:
                            DateTime.now().add(const Duration(days: 730)),
                        locale: const Locale('pt', 'BR'),
                        helpText: 'Data de término',
                        cancelText: 'Cancelar',
                        confirmText: 'OK',
                      );
                      if (d != null && mounted) {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_endDateTime),
                          builder: (context, child) => MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          ),
                          helpText: 'Horário de término',
                          cancelText: 'Cancelar',
                          confirmText: 'OK',
                        );
                        if (t != null && mounted) {
                          setState(() => _endDateTime = DateTime(
                              d.year, d.month, d.day, t.hour, t.minute));
                        }
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Término',
                        prefixIcon: Icon(Icons.event_available_rounded),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        '${_endDateTime.day.toString().padLeft(2, '0')}/${_endDateTime.month.toString().padLeft(2, '0')}/${_endDateTime.year} ${_endDateTime.hour.toString().padLeft(2, '0')}:${_endDateTime.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEEF2FF), Color(0xFFFDF2F8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF818CF8).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notifications_active_rounded,
                          color: Color(0xFF7C3AED), size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notificações automáticas: ao publicar, 1 dia antes e 1 hora antes do evento. Agenda interna sincronizada sozinha.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Icon(Icons.place_rounded,
                        size: 22,
                        color: ThemeCleanPremium.primary.withOpacity(0.85)),
                    const SizedBox(width: 8),
                    Text('Local do evento (opcional)',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Colors.grey.shade800)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Use o endereço da igreja com um toque ou preencha manualmente (CEP ou campos abaixo).',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: Colors.grey.shade600),
                ),
                const SizedBox(height: 14),
                if (_useChurchLocation &&
                    (_churchAddressText ?? '').trim().isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.shade200),
                      boxShadow: ThemeCleanPremium.softUiCardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Endereço da igreja',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade800,
                                fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(_churchAddressText!.trim(),
                            style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: Colors.grey.shade900)),
                        if (_locationLat != null && _locationLng != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                                'Coordenadas da igreja: link de mapa no compartilhamento.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700)),
                          ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _sairModoIgreja,
                              icon: Icon(Icons.edit_location_alt_rounded,
                                  size: 18, color: Colors.grey.shade800),
                              label: Text('Definir por CEP / manual',
                                  style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w600)),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: Size(minTouch, minTouch),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12)),
                            ),
                            FilledButton.icon(
                              onPressed: _usarEnderecoIgreja,
                              icon: const Icon(Icons.refresh_rounded,
                                  size: 18, color: Colors.white),
                              label: const Text('Atualizar da igreja',
                                  style: TextStyle(color: Colors.white)),
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  minimumSize: Size(minTouch, minTouch)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else ...[
                  FilledButton.icon(
                    onPressed:
                        _loadingChurchAddress ? null : _usarEnderecoIgreja,
                    icon: _loadingChurchAddress
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.church_rounded,
                            size: 20, color: Colors.white),
                    label: Text(
                      _loadingChurchAddress
                          ? 'A carregar endereço…'
                          : 'Usar endereço da igreja (cadastro)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      minimumSize: Size(double.infinity, minTouch),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'ou CEP / manual',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cep,
                          keyboardType: TextInputType.number,
                          maxLength: 9,
                          onChanged: (_) => _notifyAddressPreview(),
                          decoration: InputDecoration(
                            labelText: 'CEP',
                            hintText: '00000-000',
                            counterText: '',
                            prefixIcon: const Icon(Icons.pin_drop_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.icon(
                          onPressed: _buscandoCep ? null : _buscarCep,
                          icon: _buscandoCep
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.search_rounded,
                                  size: 20, color: Colors.white),
                          label: Text(
                              _buscandoCep ? 'Buscando...' : 'Buscar CEP',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            backgroundColor: ThemeCleanPremium.primary,
                            minimumSize: Size(minTouch, minTouch),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _logradouro,
                    onChanged: (_) => _notifyAddressPreview(),
                    decoration: InputDecoration(
                      labelText: 'Logradouro (rua, avenida…)',
                      prefixIcon: const Icon(Icons.signpost_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _numero,
                    onChanged: (_) => _notifyAddressPreview(),
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Número',
                      prefixIcon: const Icon(Icons.numbers_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bairro,
                    onChanged: (_) => _notifyAddressPreview(),
                    decoration: InputDecoration(
                      labelText: 'Bairro',
                      prefixIcon: const Icon(Icons.apartment_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _cidade,
                          onChanged: (_) => _notifyAddressPreview(),
                          decoration: InputDecoration(
                            labelText: 'Cidade',
                            prefixIcon: const Icon(Icons.location_city_rounded),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 88,
                        child: TextField(
                          controller: _uf,
                          onChanged: (_) => _notifyAddressPreview(),
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 2,
                          decoration: InputDecoration(
                            labelText: 'UF',
                            counterText: '',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _quadraLote,
                    onChanged: (_) => _notifyAddressPreview(),
                    decoration: InputDecoration(
                      labelText: 'Quadra e lote (opcional)',
                      hintText: 'Ex.: Qd 5 Lt 12',
                      prefixIcon: const Icon(Icons.grid_on_rounded),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _referencia,
                    onChanged: (_) => _notifyAddressPreview(),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Ponto de referência (opcional)',
                      hintText: 'Ex.: próximo ao mercado, fundos do salão…',
                      prefixIcon: const Icon(Icons.flag_outlined),
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _addressPreviewTick,
                      builder: (context, _, __) {
                        final resumo = _montarEnderecoManual();
                        final empty = resumo.isEmpty;
                        return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Resumo do local',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Colors.grey.shade700)),
                        const SizedBox(height: 6),
                        Text(
                          empty ? '(preencha os campos acima)' : resumo,
                          style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: empty
                                  ? Colors.grey.shade500
                                  : Colors.grey.shade900),
                        ),
                      ],
                    );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Icon(Icons.event_busy_rounded,
                            size: 20, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('Data de validade (opcional)',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade700))),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                initialDate: _validUntil ??
                                    DateTime.now()
                                        .add(const Duration(days: 30)),
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 365 * 3)),
                                locale: const Locale('pt', 'BR'),
                                helpText: 'Até quando exibir o evento',
                                cancelText: 'Cancelar',
                                confirmText: 'OK',
                              );
                              if (d != null && mounted)
                                setState(() => _validUntil = d);
                            },
                            icon: const Icon(Icons.calendar_today_rounded,
                                size: 18),
                            label: Text(
                                _validUntil == null
                                    ? 'Permanente'
                                    : '${_validUntil!.day.toString().padLeft(2, '0')}/${_validUntil!.month.toString().padLeft(2, '0')}/${_validUntil!.year}',
                                overflow: TextOverflow.ellipsis),
                            style: OutlinedButton.styleFrom(
                                minimumSize:
                                    Size(0, ThemeCleanPremium.minTouchTarget)),
                          ),
                        ),
                        if (_validUntil != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Remover data de validade',
                            onPressed: () => setState(() => _validUntil = null),
                            icon: const Icon(Icons.close_rounded),
                            style: IconButton.styleFrom(
                                minimumSize: Size(minTouch, minTouch)),
                          ),
                        ],
                      ]),
                    ]),
              ]),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2563EB).withValues(alpha: 0.08),
                    const Color(0xFFDB2777).withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                ),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
              ),
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _publicSite,
                onChanged: (v) => setState(() => _publicSite = v),
                title: const Text(
                  'Publicar no site público',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  _publicSite
                      ? 'Visível no site da igreja com interações (padrão ligado).'
                      : 'Só no painel e no app da igreja.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.public_rounded,
                      color: Color(0xFF2563EB)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(height: max(120.0, minTouch * 0.25)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Período personalizado na lista «Próximos na programação» — digitar e/ou calendário.
// ═══════════════════════════════════════════════════════════════════════════════

class _UpcomingCustomPeriodDialog extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;

  const _UpcomingCustomPeriodDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  @override
  State<_UpcomingCustomPeriodDialog> createState() =>
      _UpcomingCustomPeriodDialogState();
}

class _UpcomingCustomPeriodDialogState extends State<_UpcomingCustomPeriodDialog> {
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(
      text: formatBrDateDdMmYyyy(widget.initialStart),
    );
    _endCtrl = TextEditingController(
      text: formatBrDateDdMmYyyy(widget.initialEnd),
    );
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _openStartCalendar() async {
    final now = DateTime.now();
    final parsed = parseBrDateDdMmYyyy(_startCtrl.text);
    final initial = parsed ?? widget.initialStart;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 4, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: ThemeCleanPremium.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: ThemeCleanPremium.onSurface,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _startCtrl.text = formatBrDateDdMmYyyy(picked));
    }
  }

  Future<void> _openEndCalendar() async {
    final now = DateTime.now();
    final startP = parseBrDateDdMmYyyy(_startCtrl.text);
    final endP = parseBrDateDdMmYyyy(_endCtrl.text);
    final initial = endP ?? startP ?? widget.initialEnd;
    final first = startP ?? DateTime(now.year - 2);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(now.year + 4, 12, 31),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: ThemeCleanPremium.primary,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: ThemeCleanPremium.onSurface,
          ),
        ),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _endCtrl.text = formatBrDateDdMmYyyy(picked));
    }
  }

  void _apply() {
    final s = parseBrDateDdMmYyyy(_startCtrl.text);
    final e = parseBrDateDdMmYyyy(_endCtrl.text);
    if (s == null || e == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe data inicial e final válidas (dd/mm/aaaa).'),
        ),
      );
      return;
    }
    if (e.isBefore(s)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A data final não pode ser anterior à data inicial.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      DateTimeRange(
        start: DateTime(s.year, s.month, s.day),
        end: DateTime(e.year, e.month, e.day),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
      ),
      title: const Text('Período personalizado'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Digite as datas ou toque nos ícones para abrir primeiro o calendário da data inicial e depois o da final.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _startCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [BrDateDdMmYyyyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Data inicial',
                hintText: 'dd/mm/aaaa',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Abrir calendário (início)',
                  icon: Icon(Icons.calendar_today_rounded,
                      color: ThemeCleanPremium.primary),
                  onPressed: _openStartCalendar,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _endCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [BrDateDdMmYyyyInputFormatter()],
              decoration: InputDecoration(
                labelText: 'Data final',
                hintText: 'dd/mm/aaaa',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Abrir calendário (fim)',
                  icon: Icon(Icons.calendar_month_rounded,
                      color: ThemeCleanPremium.primary),
                  onPressed: _openEndCalendar,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _apply,
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Aba Eventos Fixos — leitura pontual para evitar INTERNAL ASSERTION FAILED.
// ═══════════════════════════════════════════════════════════════════════════════
class _FixosTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> templates;
  final CollectionReference<Map<String, dynamic>> noticias;
  final bool canWrite;
  final void Function({DocumentSnapshot<Map<String, dynamic>>? doc}) onEdit;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onDelete;
  final void Function(DocumentSnapshot<Map<String, dynamic>>) onGenerate;
  final void Function(DocumentSnapshot<Map<String, dynamic>> doc)
      onOpenNoticiaEvento;
  const _FixosTab(
      {super.key,
      required this.templates,
      required this.noticias,
      required this.canWrite,
      required this.onEdit,
      required this.onDelete,
      required this.onGenerate,
      required this.onOpenNoticiaEvento});

  @override
  State<_FixosTab> createState() => _FixosTabState();
}

/// Retorna URL da foto do evento fixo — extração centralizada.
String _templateImageUrl(Map<String, dynamic> m) => imageUrlFromMap(m);

class _FixosTabState extends State<_FixosTab> {
  static const _wn = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  static const _wdEvento = ['', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  late Future<QuerySnapshot<Map<String, dynamic>>> _templatesFuture;
  QuerySnapshot<Map<String, dynamic>>? _lastGoodTemplatesSnap;
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _proximosNoticiasFuture;
  String _fixFilterPeriod = 'all';
  bool _selectMode = false;
  final Set<String> _selectedTemplateIds = <String>{};

  /// Filtro da lista “Próximos na programação” (notícias `evento`): 7/15/30/mês/custom.
  String _upcomingViewFilter = '30';
  DateTime? _upcomingCustomStart;
  DateTime? _upcomingCustomEnd;
  bool _upcomingSelectMode = false;
  final Set<String> _selectedNoticiaIds = <String>{};
  int _proximosNoticiasLimit = YahwehPerformanceV4.defaultPageSize;
  bool _proximosNoticiasLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _templatesFuture = _seedOrLoadTemplates();
    _proximosNoticiasFuture = _loadProximosNoticias();
    unawaited(_primeTemplatesFromCache());
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _seedOrLoadTemplates() {
    final tid = widget.templates.parent?.id ?? '';
    if (tid.isEmpty) return _load();

    final ram = _EventTemplatesRamCache.peek(tid);
    if (ram != null && ram.isNotEmpty) {
      final snap = MergedFirestoreQuerySnapshot(ram);
      _lastGoodTemplatesSnap = snap;
      return Future.value(snap);
    }

    final mem = FirestoreReadResilience.peekLastGoodQuery(
      _eventTemplatesMemKey(tid),
    );
    if (mem != null && mem.docs.isNotEmpty) {
      _lastGoodTemplatesSnap = mem;
      return Future.value(mem);
    }

    return _load();
  }

  @override
  void didUpdateWidget(covariant _FixosTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldTid = oldWidget.templates.parent?.id ?? '';
    final newTid = widget.templates.parent?.id ?? '';
    if (oldTid != newTid && newTid.isNotEmpty) {
      _templatesFuture = _seedOrLoadTemplates();
      _proximosNoticiasFuture = _loadProximosNoticias();
      unawaited(_primeTemplatesFromCache());
      setState(() {});
    }
  }

  Future<void> _primeTemplatesFromCache() async {
    final tid = widget.templates.parent?.id ?? '';
    if (tid.isEmpty) return;

    try {
      final snap = await ChurchTenantResilientReads.eventTemplates(tid).timeout(
        const Duration(milliseconds: 1800),
      );
      if (!mounted || snap.docs.isEmpty) return;
      _EventTemplatesRamCache.put(tid, snap.docs);
      setState(() {
        _lastGoodTemplatesSnap = snap;
        _templatesFuture = Future.value(snap);
      });
    } catch (_) {}

    if (_lastGoodTemplatesSnap != null) return;

    try {
      final snap = await widget.templates
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (!mounted || snap.docs.isEmpty) return;
      _EventTemplatesRamCache.put(tid, snap.docs);
      setState(() {
        _lastGoodTemplatesSnap = snap;
        _templatesFuture = Future.value(snap);
      });
    } catch (_) {}
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _load() async {
    final tid = widget.templates.parent?.id ?? '';
    if (tid.isEmpty) return const MergedFirestoreQuerySnapshot([]);
    final snap = await FirestoreWebGuard.runWithWebRecovery(
      () => ChurchTenantResilientReads.eventTemplates(tid),
    );
    if (snap.docs.isNotEmpty) {
      _EventTemplatesRamCache.put(tid, snap.docs);
      _lastGoodTemplatesSnap = snap;
    }
    return snap;
  }

  static int _timeSortMinutes(String t) {
    final p = t.split(':');
    final h = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0;
    final m = int.tryParse(p.length > 1 ? p[1] : '') ?? 0;
    return h * 60 + m;
  }

  static int _compareTemplates(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ma = a.data();
    final mb = b.data();
    final wa =
        (ma['weekday'] is int) ? (ma['weekday'] as int).clamp(1, 7) : 7;
    final wb =
        (mb['weekday'] is int) ? (mb['weekday'] as int).clamp(1, 7) : 7;
    if (wa != wb) return wa.compareTo(wb);
    final ta = _timeSortMinutes(ma['time']?.toString() ?? '19:30');
    final tb = _timeSortMinutes(mb['time']?.toString() ?? '19:30');
    if (ta != tb) return ta.compareTo(tb);
    return (ma['title'] ?? '')
        .toString()
        .toLowerCase()
        .compareTo((mb['title'] ?? '').toString().toLowerCase());
  }

  /// Próximos eventos em [noticias]: feed (especiais), agenda/gerados e instâncias com data.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _loadProximosNoticias() async {
    final now = DateTime.now();
    final rangeStart = DateTime(now.year, now.month, now.day);
    final rangeEnd = rangeStart.add(const Duration(days: 400));
    try {
      final snap = await widget.noticias
          .where('type', isEqualTo: 'evento')
          .where('startAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(rangeStart))
          .where('startAt', isLessThanOrEqualTo: Timestamp.fromDate(rangeEnd))
          .orderBy('startAt')
          .limit(_proximosNoticiasLimit)
          .get();
      return snap.docs;
    } catch (_) {
      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await widget.noticias
            .orderBy('startAt', descending: false)
            .limit(_proximosNoticiasLimit)
            .get();
      } catch (_) {
        snap = await widget.noticias.limit(_proximosNoticiasLimit).get();
      }
      final out = snap.docs.where((d) {
        if ((d.data()['type'] ?? '').toString() != 'evento') return false;
        final sa = d.data()['startAt'];
        if (sa is! Timestamp) return false;
        final dt = sa.toDate();
        return !dt.isBefore(rangeStart) && !dt.isAfter(rangeEnd);
      }).toList();
      out.sort((a, b) {
        final ta = a.data()['startAt'];
        final tb = b.data()['startAt'];
        if (ta is Timestamp && tb is Timestamp) return ta.compareTo(tb);
        return 0;
      });
      return out;
    }
  }

  Future<void> _loadMoreProximosNoticias() async {
    if (_proximosNoticiasLoadingMore) return;
    setState(() {
      _proximosNoticiasLoadingMore = true;
      _proximosNoticiasLimit += YahwehPerformanceV4.defaultPageSize;
    });
    final f = _loadProximosNoticias();
    setState(() => _proximosNoticiasFuture = f);
    await f;
    if (mounted) setState(() => _proximosNoticiasLoadingMore = false);
  }

  Widget _buildProximosLoadMoreFooter(int rawFetched) {
    return LazyLoadMoreFooter(
      visible: rawFetched >= _proximosNoticiasLimit,
      loading: _proximosNoticiasLoadingMore,
      label: 'Carregar mais eventos',
      onLoadMore: () => unawaited(_loadMoreProximosNoticias()),
    );
  }

  String _formatNoticiaEventoDataLinha(Map<String, dynamic> data) {
    final startTs = data['startAt'];
    if (startTs is! Timestamp) return '';
    final dt = startTs.toDate();
    if (data['allDay'] == true) {
      final w = dt.weekday >= 1 && dt.weekday <= 7
          ? _wdEvento[dt.weekday]
          : '';
      return '$w ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} — dia inteiro';
    }
    final w =
        dt.weekday >= 1 && dt.weekday <= 7 ? _wdEvento[dt.weekday] : '';
    return '$w ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  /// Filtro de templates por data de criação/atualização (alinhado a “excluir por período”).
  DateTime? _templateCreatedOrUpdated(Map<String, dynamic> m) {
    final c = m['createdAt'];
    if (c is Timestamp) return c.toDate();
    final u = m['updatedAt'];
    if (u is Timestamp) return u.toDate();
    return null;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _filteredTemplates(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_fixFilterPeriod == 'all') return docs;
    return docs.where((d) {
      final dt = _templateCreatedOrUpdated(d.data());
      if (dt == null) return false;
      return _isWithinPeriod(dt, _fixFilterPeriod);
    }).toList();
  }

  /// Filtro de eventos da agenda (notícias `type: evento`) por intervalo de [startAt].
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applyUpcomingFilter(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    late DateTime start;
    late DateTime end;

    switch (_upcomingViewFilter) {
      case '7':
        start = today;
        end = today.add(const Duration(days: 7));
        break;
      case '15':
        start = today;
        end = today.add(const Duration(days: 15));
        break;
      case '30':
        start = today;
        end = today.add(const Duration(days: 30));
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case 'last_month':
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0, 23, 59, 59);
        break;
      case 'custom':
        if (_upcomingCustomStart != null && _upcomingCustomEnd != null) {
          start = DateTime(_upcomingCustomStart!.year,
              _upcomingCustomStart!.month, _upcomingCustomStart!.day);
          end = DateTime(_upcomingCustomEnd!.year, _upcomingCustomEnd!.month,
              _upcomingCustomEnd!.day, 23, 59, 59);
        } else {
          start = today;
          end = today.add(const Duration(days: 30));
        }
        break;
      default:
        start = today;
        end = today.add(const Duration(days: 30));
    }

    return docs.where((d) {
      final sa = d.data()['startAt'];
      if (sa is! Timestamp) return false;
      final dt = sa.toDate();
      return !dt.isBefore(start) && !dt.isAfter(end);
    }).toList();
  }

  Future<void> _pickUpcomingCustomRange() async {
    final now = DateTime.now();
    final initialStart = _upcomingCustomStart ?? now;
    final initialEnd = _upcomingCustomEnd ?? now.add(const Duration(days: 30));
    final range = await showDialog<DateTimeRange>(
      context: context,
      builder: (ctx) => _UpcomingCustomPeriodDialog(
        initialStart: initialStart,
        initialEnd: initialEnd,
      ),
    );
    if (range == null || !mounted) return;
    setState(() {
      _upcomingViewFilter = 'custom';
      _upcomingCustomStart = range.start;
      _upcomingCustomEnd = range.end;
      _selectedNoticiaIds.clear();
    });
  }

  Future<void> _deleteNoticiaRefs(
    List<DocumentReference<Map<String, dynamic>>> refs) async {
    if (!widget.canWrite || refs.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir eventos da agenda'),
        content: Text(
            'Deseja excluir ${refs.length} evento(s) da agenda/feed? '
            'Itens gerados por culto fixo podem ser recriados ao gerar de novo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    const int chunkSize = 400;
    for (var i = 0; i < refs.length; i += chunkSize) {
      final batch = ChurchRepository.batch();
      final chunk = refs.sublist(
          i, i + chunkSize > refs.length ? refs.length : i + chunkSize);
      for (final r in chunk) {
        batch.delete(r);
      }
      await batch.commit();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Evento(s) removido(s) da agenda.'));
      setState(() {
        _selectedNoticiaIds.clear();
        _upcomingSelectMode = false;
        _proximosNoticiasFuture = _loadProximosNoticias();
      });
    }
  }

  Future<void> _deleteSelectedNoticias() async {
    final refs = _selectedNoticiaIds
        .map((id) => widget.noticias.doc(id))
        .toList();
    await _deleteNoticiaRefs(refs);
  }

  Future<void> _deleteVisibleNoticias(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> visible) async {
    if (visible.isEmpty) return;
    await _deleteNoticiaRefs(visible.map((e) => e.reference).toList());
  }

  void _toggleUpcomingSelectMode() {
    setState(() {
      _upcomingSelectMode = !_upcomingSelectMode;
      _selectedNoticiaIds.clear();
    });
  }

  Widget _buildUpcomingFilterChips() {
    Widget chip(String id, String label) {
      final sel = _upcomingViewFilter == id;
      return FilterChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => setState(() {
          _upcomingViewFilter = id;
          _selectedNoticiaIds.clear();
        }),
        selectedColor: ThemeCleanPremium.primary.withValues(alpha: 0.2),
        checkmarkColor: ThemeCleanPremium.primary,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: sel ? ThemeCleanPremium.primary : Colors.grey.shade800,
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              chip('7', '7 dias'),
              chip('15', '15 dias'),
              chip('30', '30 dias'),
              chip('month', 'Este mês'),
              chip('last_month', 'Mês anterior'),
              ActionChip(
                avatar: Icon(Icons.date_range_rounded,
                    size: 18, color: ThemeCleanPremium.primary),
                label: const Text('Período…'),
                onPressed: _pickUpcomingCustomRange,
              ),
            ],
          ),
          if (_upcomingViewFilter == 'custom' &&
              _upcomingCustomStart != null &&
              _upcomingCustomEnd != null) ...[
            const SizedBox(height: 6),
            Text(
              'Período: ${_upcomingCustomStart!.day.toString().padLeft(2, '0')}/${_upcomingCustomStart!.month.toString().padLeft(2, '0')}/${_upcomingCustomStart!.year} '
              '– ${_upcomingCustomEnd!.day.toString().padLeft(2, '0')}/${_upcomingCustomEnd!.month.toString().padLeft(2, '0')}/${_upcomingCustomEnd!.year}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUpcomingActionRow(
    int visibleCount,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> visible,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: _toggleUpcomingSelectMode,
            icon: Icon(
              _upcomingSelectMode
                  ? Icons.close_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 18,
            ),
            label: Text(
                _upcomingSelectMode ? 'Cancelar seleção' : 'Selecionar'),
          ),
          if (_upcomingSelectMode && visible.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  if (_selectedNoticiaIds.length == visible.length) {
                    _selectedNoticiaIds.clear();
                  } else {
                    _selectedNoticiaIds
                      ..clear()
                      ..addAll(visible.map((e) => e.id));
                  }
                });
              },
              child: Text(
                _selectedNoticiaIds.length == visible.length
                    ? 'Desmarcar todos'
                    : 'Selecionar todos',
              ),
            ),
          if (_upcomingSelectMode && _selectedNoticiaIds.isNotEmpty)
            TextButton(
              onPressed: () =>
                  setState(() => _selectedNoticiaIds.clear()),
              child: const Text('Limpar seleção'),
            ),
          if (_upcomingSelectMode)
            FilledButton.icon(
              onPressed: _selectedNoticiaIds.isEmpty
                  ? null
                  : _deleteSelectedNoticias,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text('Excluir (${_selectedNoticiaIds.length})'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error,
                foregroundColor: Colors.white,
              ),
            )
          else
            FilledButton.icon(
              onPressed:
                  visible.isEmpty ? null : () => _deleteVisibleNoticias(visible),
              icon: const Icon(Icons.delete_sweep_rounded, size: 18),
              label: Text('Excluir visíveis ($visibleCount)'),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  void _refresh() => setState(() {
        _templatesFuture = _load();
        _proximosNoticiasFuture = _loadProximosNoticias();
      });

  void _toggleFixSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedTemplateIds.clear();
    });
  }

  bool _isWithinPeriod(DateTime dt, String period) {
    if (period == 'all') return true;
    final now = DateTime.now();
    final startOfWeek = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 7));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final startLastMonth = DateTime(now.year, now.month - 1, 1);
    final endLastMonth = DateTime(now.year, now.month, 0, 23, 59, 59);
    final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);

    if (period == 'week') return !dt.isBefore(now) && dt.isBefore(endOfWeek);
    if (period == 'month')
      return dt.isAfter(startOfMonth.subtract(const Duration(days: 1))) &&
          dt.isBefore(endOfMonth.add(const Duration(days: 1)));
    if (period == 'last_month')
      return !dt.isBefore(startLastMonth) && !dt.isAfter(endLastMonth);
    if (period == 'year') return !dt.isBefore(now) && !dt.isAfter(endOfYear);
    return true;
  }

  Future<void> _deleteTemplateRefs(
      List<DocumentReference<Map<String, dynamic>>> refs) async {
    if (refs.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Nada para excluir.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir eventos fixos'),
        content: Text('Deseja excluir ${refs.length} evento(s) fixo(s)?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: ThemeCleanPremium.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    const int chunkSize = 400;
    for (var i = 0; i < refs.length; i += chunkSize) {
      final batch = ChurchRepository.batch();
      final chunk = refs.sublist(
          i, i + chunkSize > refs.length ? refs.length : i + chunkSize);
      for (final r in chunk) {
        batch.delete(r);
      }
      await batch.commit();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Eventos fixos excluídos.'));
      _selectedTemplateIds.clear();
      _selectMode = false;
      _refresh();
    }
  }

  Future<void> _deleteSelectedTemplates() async {
    final refs =
        _selectedTemplateIds.map((id) => widget.templates.doc(id)).toList();
    await _deleteTemplateRefs(refs);
  }

  Future<void> _deleteTemplatesByPeriod() async {
    final snap = await _load();
    final docs = snap.docs;
    final toDelete = <DocumentReference<Map<String, dynamic>>>[];
    for (final d in docs) {
      if (_fixFilterPeriod == 'all') {
        toDelete.add(d.reference);
      } else {
        final dt = _templateCreatedOrUpdated(d.data());
        if (dt != null && _isWithinPeriod(dt, _fixFilterPeriod)) {
          toDelete.add(d.reference);
        }
      }
    }
    await _deleteTemplateRefs(toDelete);
  }

  /// Cartão de evento da agenda (coleção notícias) — mesma interação da lista sem templates.
  Widget _buildUpcomingNoticiaCard(
      QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final title = (m['title'] ?? 'Evento').toString().trim();
    final linha = _formatNoticiaEventoDataLinha(m);
    final ehFeed =
        !noticiaEventoEhRotinaOuGeradoAutomatico(m, d.id);
    final rotulo = ehFeed ? 'Feed' : 'Agenda / gerado';
    final sel = _selectedNoticiaIds.contains(d.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: _upcomingSelectMode && sel
            ? Border.all(color: ThemeCleanPremium.primary, width: 1.5)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          onTap: () {
            if (_upcomingSelectMode && widget.canWrite) {
              setState(() {
                if (sel) {
                  _selectedNoticiaIds.remove(d.id);
                } else {
                  _selectedNoticiaIds.add(d.id);
                }
              });
            } else {
              widget.onOpenNoticiaEvento(d);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_upcomingSelectMode && widget.canWrite)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 10),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: sel,
                        onChanged: (_) {
                          setState(() {
                            if (sel) {
                              _selectedNoticiaIds.remove(d.id);
                            } else {
                              _selectedNoticiaIds.add(d.id);
                            }
                          });
                        },
                      ),
                    ),
                  ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ThemeCleanPremium.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.event_rounded,
                    color: ThemeCleanPremium.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? 'Evento' : title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      if (linha.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          linha,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          rotulo,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_upcomingSelectMode)
                  Icon(Icons.chevron_right_rounded,
                      color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Botão no estilo do módulo Património (+ Novo Bem).
  Widget _buildNovoEventoFixoPremiumButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onEdit(),
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            gradient: LinearGradient(
              colors: [
                ThemeCleanPremium.primary,
                ThemeCleanPremium.primaryLight,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              ...ThemeCleanPremium.softUiCardShadow,
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, color: Colors.white, size: 22),
                SizedBox(width: 8),
                Text(
                  'Novo evento fixo',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openEventoFixoDetail(
      BuildContext context, DocumentSnapshot<Map<String, dynamic>> doc) {
    final tid = widget.noticias.parent?.id ?? '';
    if (tid.isNotEmpty) {
      unawaited(
        AppResumeStateService.saveOpenEvent(
          tenantId: tid,
          eventDocId: doc.id,
        ),
      );
    }
    final dm = doc.data() ?? {};
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _EventoFixoDetailPage(
        doc: doc,
        canEdit: widget.canWrite,
        onEdit: () {
          Navigator.of(context).pop();
          widget.onEdit(doc: doc);
        },
        onDelete: () {
          Navigator.of(context).pop();
          widget.onDelete(doc);
        },
        onGenerate: eventTemplateIncludeInAgenda(dm)
            ? () {
                Navigator.of(context).pop();
                widget.onGenerate(doc);
              }
            : null,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: _templatesFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: 'Não foi possível carregar os eventos fixos',
            error: snap.error,
            onRetry: _refresh,
          );
        }
        QuerySnapshot<Map<String, dynamic>>? effectiveSnap = snap.data;
        if ((snap.connectionState != ConnectionState.done || !snap.hasData) &&
            _lastGoodTemplatesSnap != null &&
            _lastGoodTemplatesSnap!.docs.isNotEmpty) {
          effectiveSnap = _lastGoodTemplatesSnap;
        }
        if (effectiveSnap == null) {
          return const ChurchPanelLoadingBody();
        }
        final docs = effectiveSnap.docs.toList()..sort(_compareTemplates);
        if (docs.isEmpty) {
          return FutureBuilder<
              List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            future: _proximosNoticiasFuture,
            builder: (context, proxSnap) {
              if (proxSnap.hasError) {
                return ChurchPanelErrorBody(
                  title: 'Não foi possível carregar agenda e feed',
                  error: proxSnap.error,
                  onRetry: () => setState(() {
                    _proximosNoticiasFuture = _loadProximosNoticias();
                  }),
                );
              }
              if (proxSnap.connectionState != ConnectionState.done ||
                  !proxSnap.hasData) {
                return const ChurchPanelLoadingBody();
              }
              final upcoming = proxSnap.data!;
              final vis = _applyUpcomingFilter(upcoming);
              return RefreshIndicator(
                onRefresh: () async {
                  setState(() {
                    _templatesFuture = _load();
                    _proximosNoticiasFuture = _loadProximosNoticias();
                  });
                  await _proximosNoticiasFuture;
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.event_repeat_rounded,
                                size: 56,
                                color: ThemeCleanPremium.primary
                                    .withOpacity(0.85)),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhum modelo de culto fixo',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.grey.shade900),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enquanto isso, veja abaixo os próximos eventos da agenda, do feed e instâncias geradas — ou crie cada culto fixo com «Novo evento fixo».',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: Colors.grey.shade600),
                            ),
                            if (widget.canWrite) ...[
                              const SizedBox(height: 16),
                              Center(child: _buildNovoEventoFixoPremiumButton()),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                upcoming.isEmpty
                                    ? 'Programação'
                                    : vis.length == upcoming.length
                                        ? 'Próximos na programação (${upcoming.length})'
                                        : 'Próximos na programação (${vis.length} de ${upcoming.length} no filtro)',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade800),
                              ),
                            ),
                            if (upcoming.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              _buildUpcomingFilterChips(),
                              if (widget.canWrite) ...[
                                const SizedBox(height: 10),
                                _buildUpcomingActionRow(vis.length, vis),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (upcoming.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 88),
                          child: Center(
                            child: Text(
                              'Nenhum evento com data nos próximos ~400 dias. Use a aba Feed ou Agenda para publicar eventos.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                      )
                    else if (vis.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 88),
                          child: Center(
                            child: Text(
                              'Nenhum evento no período selecionado. Ajuste o filtro (7, 15, 30 dias, este mês, mês anterior ou período personalizado).',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey.shade600),
                            ),
                          ),
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) {
                              return _buildUpcomingNoticiaCard(vis[i]);
                            },
                            childCount: vis.length,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _buildProximosLoadMoreFooter(upcoming.length),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        }
        final filtered = _filteredTemplates(docs);
        return RefreshIndicator(
          onRefresh: () async {
            _refresh();
          },
          child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
              itemCount: filtered.length + 2,
              itemBuilder: (context, i) {
                if (i == 0)
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                _fixFilterPeriod == 'all'
                                    ? '${docs.length} evento(s) fixo(s)'
                                    : '${filtered.length} de ${docs.length} evento(s) fixo(s) (filtro)',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (widget.canWrite)
                              _buildNovoEventoFixoPremiumButton(),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'O período filtra a lista abaixo e define quais modelos entram em “Excluir por período”. Em “Todos”, esse botão exclui todos os modelos.',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1.25,
                              color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _toggleFixSelectMode,
                              icon: Icon(
                                  _selectMode
                                      ? Icons.close_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 18),
                              label: Text(_selectMode
                                  ? 'Cancelar seleção'
                                  : 'Selecionar'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(
                                    0, ThemeCleanPremium.minTouchTarget),
                                side: BorderSide(
                                    color: ThemeCleanPremium.primary
                                        .withOpacity(0.25)),
                                backgroundColor: Colors.white,
                                foregroundColor: ThemeCleanPremium.primary,
                              ),
                            ),
                            if (_selectMode && filtered.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    final ids =
                                        filtered.map((e) => e.id).toList();
                                    final allSel = ids.every(
                                        _selectedTemplateIds.contains);
                                    if (allSel) {
                                      for (final id in ids) {
                                        _selectedTemplateIds.remove(id);
                                      }
                                    } else {
                                      for (final id in ids) {
                                        _selectedTemplateIds.add(id);
                                      }
                                    }
                                  });
                                },
                                child: Text(
                                  filtered.isNotEmpty &&
                                          filtered.every((e) =>
                                              _selectedTemplateIds
                                                  .contains(e.id))
                                      ? 'Desmarcar visíveis'
                                      : 'Selecionar visíveis',
                                ),
                              ),
                            if (_selectMode && _selectedTemplateIds.isNotEmpty)
                              TextButton(
                                onPressed: () => setState(
                                    () => _selectedTemplateIds.clear()),
                                child: const Text('Limpar seleção'),
                              ),
                            SizedBox(
                              width: 160,
                              child: DropdownButtonFormField<String>(
                                value: _fixFilterPeriod,
                                decoration: const InputDecoration(
                                    labelText: 'Período', isDense: true),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'all', child: Text('Todos')),
                                  DropdownMenuItem(
                                      value: 'week',
                                      child: Text('Esta semana')),
                                  DropdownMenuItem(
                                      value: 'month', child: Text('Este mês')),
                                  DropdownMenuItem(
                                      value: 'last_month',
                                      child: Text('Mês anterior')),
                                  DropdownMenuItem(
                                      value: 'year', child: Text('Este ano')),
                                ],
                                onChanged: (v) => setState(() {
                                  _fixFilterPeriod = v ?? 'all';
                                  _selectedTemplateIds.clear();
                                }),
                              ),
                            ),
                            if (_selectMode)
                              FilledButton.icon(
                                onPressed: _selectedTemplateIds.isEmpty
                                    ? null
                                    : _deleteSelectedTemplates,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: Text(
                                    'Excluir (${_selectedTemplateIds.length})'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.error,
                                  minimumSize: const Size(
                                      0, ThemeCleanPremium.minTouchTarget),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                ),
                              )
                            else
                              FilledButton.icon(
                                onPressed: _deleteTemplatesByPeriod,
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Excluir por período'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.error,
                                  minimumSize: const Size(
                                      0, ThemeCleanPremium.minTouchTarget),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                if (i == filtered.length + 1) {
                  return FutureBuilder<
                      List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    future: _proximosNoticiasFuture,
                    builder: (context, proxSnap) {
                      if (proxSnap.connectionState != ConnectionState.done ||
                          !proxSnap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final upcoming = proxSnap.data!;
                      final vis = _applyUpcomingFilter(upcoming);
                      if (upcoming.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Divider(height: 28),
                            Text(
                              vis.length == upcoming.length
                                  ? 'Próximos na programação (${upcoming.length})'
                                  : 'Próximos na programação (${vis.length} de ${upcoming.length} no filtro)',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey.shade800),
                            ),
                            const SizedBox(height: 10),
                            _buildUpcomingFilterChips(),
                            if (widget.canWrite) ...[
                              const SizedBox(height: 8),
                              _buildUpcomingActionRow(vis.length, vis),
                            ],
                            const SizedBox(height: 8),
                            if (vis.isEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Text(
                                  'Nenhum evento no período selecionado.',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                              )
                            else ...[
                              ...vis.map(_buildUpcomingNoticiaCard),
                              _buildProximosLoadMoreFooter(upcoming.length),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                }
                final idx = i - 1;
                final d = filtered[idx];
                final m = d.data();
                final selected = _selectedTemplateIds.contains(d.id);
                final title = (m['title'] ?? '').toString();
                final weekday = (m['weekday'] ?? 1) as int;
                final time = (m['time'] ?? '').toString();
                final rec = (m['recurrence'] ?? 'weekly').toString();
                final dayName = weekday > 0 && weekday < 8 ? _wn[weekday] : '?';
                final photoUrl = _templateImageUrl(m);
                return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        boxShadow: ThemeCleanPremium.softUiCardShadow),
                    child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                            borderRadius: BorderRadius.circular(
                                ThemeCleanPremium.radiusMd),
                            onTap: _selectMode
                                ? null
                                : () => _openEventoFixoDetail(context, d),
                            child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(children: [
                                  if (_selectMode)
                                    SizedBox(
                                      width: ThemeCleanPremium.minTouchTarget,
                                      height: ThemeCleanPremium.minTouchTarget,
                                      child: Checkbox(
                                        value: selected,
                                        onChanged: (_) {
                                          setState(() {
                                            if (selected) {
                                              _selectedTemplateIds.remove(d.id);
                                            } else {
                                              _selectedTemplateIds.add(d.id);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  if (_selectMode) const SizedBox(width: 12),
                                  Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                          color: ThemeCleanPremium.primary
                                              .withOpacity(0.08),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(dayName,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                    color: ThemeCleanPremium
                                                        .primary)),
                                            Text(time,
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: ThemeCleanPremium
                                                        .primary
                                                        .withOpacity(0.7)))
                                          ])),
                                  const SizedBox(width: 14),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                        Text(
                                            rec == 'weekly'
                                                ? 'Semanal'
                                                : rec == 'biweekly'
                                                    ? 'Quinzenal'
                                                    : 'Mensal',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600))
                                      ])),
                                  SizedBox(
                                    width: 52,
                                    height: 52,
                                    child: photoUrl.isNotEmpty
                                        ? ClipOval(
                                            child: SafeNetworkImage(
                                              imageUrl: photoUrl,
                                              width: 52,
                                              height: 52,
                                              fit: BoxFit.cover,
                                              placeholder: Container(
                                                  color: Colors.grey.shade200,
                                                  child: Icon(
                                                      Icons.event_rounded,
                                                      color: ThemeCleanPremium
                                                          .primary,
                                                      size: 26)),
                                              errorWidget: Container(
                                                  color: ThemeCleanPremium
                                                      .primary
                                                      .withOpacity(0.12),
                                                  child: Icon(
                                                      Icons.event_rounded,
                                                      color: ThemeCleanPremium
                                                          .primary,
                                                      size: 26)),
                                            ),
                                          )
                                        : CircleAvatar(
                                            radius: 26,
                                            backgroundColor: ThemeCleanPremium
                                                .primary
                                                .withOpacity(0.12),
                                            child: Icon(Icons.event_rounded,
                                                color:
                                                    ThemeCleanPremium.primary,
                                                size: 26)),
                                  ),
                                  const SizedBox(width: 8),
                                  if (widget.canWrite && !_selectMode)
                                    PopupMenuButton<String>(
                                      tooltip: 'Ver, editar, excluir',
                                      icon: const Icon(Icons.more_vert_rounded),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              ThemeCleanPremium.radiusSm)),
                                      onSelected: (value) {
                                        switch (value) {
                                          case 'ver':
                                            _openEventoFixoDetail(context, d);
                                            break;
                                          case 'editar':
                                            if (widget.canWrite)
                                              widget.onEdit(doc: d);
                                            break;
                                          case 'excluir':
                                            if (widget.canWrite)
                                              widget.onDelete(d);
                                            break;
                                          case 'gerar':
                                            widget.onGenerate(d);
                                            break;
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                            value: 'ver',
                                            child: Row(children: [
                                              Icon(Icons.visibility_rounded,
                                                  size: 20),
                                              SizedBox(width: 10),
                                              Text('Ver')
                                            ])),
                                        if (widget.canWrite)
                                          const PopupMenuItem(
                                              value: 'editar',
                                              child: Row(children: [
                                                Icon(Icons.edit_rounded,
                                                    size: 20),
                                                SizedBox(width: 10),
                                                Text('Editar')
                                              ])),
                                        if (widget.canWrite)
                                          const PopupMenuItem(
                                              value: 'excluir',
                                              child: Row(children: [
                                                Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 20,
                                                    color: Colors.red),
                                                SizedBox(width: 10),
                                                Text('Excluir',
                                                    style: TextStyle(
                                                        color: Colors.red))
                                              ])),
                                        if (eventTemplateIncludeInAgenda(
                                            d.data()))
                                          const PopupMenuItem(
                                              value: 'gerar',
                                              child: Row(children: [
                                                Icon(Icons.auto_awesome_rounded,
                                                    size: 20),
                                                SizedBox(width: 10),
                                                Text('Gerar no feed')
                                              ])),
                                      ],
                                    ),
                                ])))));
              }),
        );
      },
    );
  }
}

/// Tela de detalhes do evento fixo: data, local, dados e foto. Editar só para gestores/adm; ao tocar vai ao módulo (abre o editor).
class _EventoFixoDetailPage extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>> doc;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onGenerate;
  const _EventoFixoDetailPage(
      {required this.doc,
      required this.canEdit,
      required this.onEdit,
      this.onDelete,
      this.onGenerate});

  static const _wn = [
    '',
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo'
  ];

  @override
  Widget build(BuildContext context) {
    final m = doc.data() ?? {};
    final title = (m['title'] ?? '').toString();
    final weekday = (m['weekday'] ?? 7) as int;
    final time = (m['time'] ?? '19:30').toString();
    final location = (m['location'] ?? '').toString();
    final rec = (m['recurrence'] ?? 'weekly').toString();
    final dayName = weekday > 0 && weekday < 8 ? _wn[weekday] : '—';
    final recLabel = rec == 'weekly'
        ? 'Semanal'
        : rec == 'biweekly'
            ? 'Quinzenal'
            : 'Mensal';
    final photoUrl = _templateImageUrl(m);

    return Scaffold(
      backgroundColor: ThemeCleanPremium.surfaceVariant,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Voltar',
        ),
        title: Text(title.isNotEmpty ? title : 'Evento fixo'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: ThemeCleanPremium.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photoUrl.isNotEmpty) ...[
                Center(
                  child: ClipOval(
                    child: SafeNetworkImage(
                      imageUrl: photoUrl,
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      placeholder: Container(
                          width: 200,
                          height: 200,
                          color: Colors.grey.shade200,
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: ThemeCleanPremium.primary))),
                      errorWidget: Container(
                          width: 200,
                          height: 200,
                          color: ThemeCleanPremium.primary.withOpacity(0.15),
                          child: Icon(Icons.event_rounded,
                              size: 80, color: ThemeCleanPremium.primary)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ] else
                Center(
                  child: CircleAvatar(
                      radius: 60,
                      backgroundColor:
                          ThemeCleanPremium.primary.withOpacity(0.12),
                      child: Icon(Icons.event_rounded,
                          size: 64, color: ThemeCleanPremium.primary)),
                ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    boxShadow: ThemeCleanPremium.softUiCardShadow),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 16),
                      _detailRow(Icons.calendar_today_rounded, 'Data',
                          '$dayName às $time'),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _detailRow(
                            Icons.location_on_outlined, 'Local', location)
                      ],
                      const SizedBox(height: 12),
                      _detailRow(Icons.repeat_rounded, 'Recorrência', recLabel),
                      const SizedBox(height: 12),
                      _detailRow(
                        Icons.event_available_rounded,
                        'Agenda e programação pública',
                        eventTemplateIncludeInAgenda(m)
                            ? 'Sim — datas na agenda e «Gerar no feed»'
                            : 'Não — só no resumo de horários do site',
                      ),
                    ]),
              ),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        label: const Text('Voltar'))),
                if (canEdit) ...[
                  const SizedBox(width: 12),
                  Expanded(
                      child: FilledButton.icon(
                          onPressed: () => onEdit(),
                          icon: const Icon(Icons.edit_rounded, size: 20),
                          label: const Text('Editar'),
                          style: FilledButton.styleFrom(
                              backgroundColor: ThemeCleanPremium.primary))),
                ],
              ]),
              if (canEdit && onDelete != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                        onPressed: () => onDelete!(),
                        icon:
                            const Icon(Icons.delete_outline_rounded, size: 20),
                        label: const Text('Excluir'),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: ThemeCleanPremium.error))),
              ],
              if (onGenerate != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => onGenerate!(),
                    icon:
                        const Icon(Icons.auto_awesome_rounded, size: 20),
                    label: const Text('Gerar no feed'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: ThemeCleanPremium.primary),
      const SizedBox(width: 10),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))
      ])),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Dashboard Eventos — gráficos de confirmações, curtidas e comentários por evento
// ═══════════════════════════════════════════════════════════════════════════════
class _DashboardEventosTab extends StatefulWidget {
  final CollectionReference<Map<String, dynamic>> noticias;
  final bool canWrite;

  const _DashboardEventosTab({required this.noticias, this.canWrite = false});

  @override
  State<_DashboardEventosTab> createState() => _DashboardEventosTabState();
}

class _DashboardEventosTabState extends State<_DashboardEventosTab> {
  static const int _maxEvents = 20;
  List<_EventStats> _stats = [];
  List<PieChartSectionData> _categoryPieSections = [];
  List<({String name, int count, Color color})> _categoryLegend = [];
  bool _loading = true;
  String? _error;

  Future<void> _load() async {
    if (_stats.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final tid = widget.noticias.parent?.id ?? '';
    try {
      QuerySnapshot<Map<String, dynamic>> snap;
      final ram = tid.isNotEmpty ? _EventosNoticiasRamCache.peek(tid) : null;
      if (ram != null && ram.isNotEmpty) {
        snap = MergedFirestoreQuerySnapshot(ram);
      } else {
        final mem = tid.isNotEmpty
            ? FirestoreReadResilience.peekLastGoodQuery(
                _eventosNoticiasMemKey(
                  tid,
                  YahwehPerformanceV4.dashboardStatsSampleLimit,
                ),
              )
            : null;
        if (mem != null && mem.docs.isNotEmpty) {
          snap = mem;
        } else {
          try {
            snap = await FirestoreWebGuard.runWithWebRecovery(
              () => FirestoreReadResilience.getQuery(
                widget.noticias
                    .orderBy('startAt', descending: true)
                    .limit(YahwehPerformanceV4.dashboardStatsSampleLimit),
                cacheKey: '${tid}_eventos_dashboard_stats',
              ),
            );
          } catch (_) {
            snap = await FirestoreWebGuard.runWithWebRecovery(
              () => FirestoreReadResilience.getQuery(
                widget.noticias.limit(
                  YahwehPerformanceV4.dashboardStatsSampleLimit,
                ),
                cacheKey: '${tid}_eventos_dashboard_plain',
              ),
            );
          }
        }
      }
      if (snap.docs.isNotEmpty && tid.isNotEmpty) {
        _EventosNoticiasRamCache.put(tid, snap.docs);
      }
      var allSorted = snap.docs.where(noticiaDocEhEventoSpecialFeed).toList();
      if (allSorted.length > 1 &&
          snap.docs.isNotEmpty &&
          snap.docs.first.data().containsKey('startAt')) {
        allSorted.sort((a, b) {
          final ta = a.data()['startAt'];
          final tb = b.data()['startAt'];
          if (ta is Timestamp && tb is Timestamp) return tb.compareTo(ta);
          return 0;
        });
      }
      final catMap = <String, int>{};
      for (final d in allSorted) {
        final data = d.data();
        final raw = (data['eventCategoryName'] ?? '').toString().trim();
        final key = raw.isEmpty ? 'Sem categoria' : raw;
        catMap[key] = (catMap[key] ?? 0) + 1;
      }
      final pieColors = <Color>[
        ThemeCleanPremium.primary,
        ThemeCleanPremium.success,
        Colors.orange.shade600,
        Colors.purple.shade400,
        const Color(0xFF0EA5E9),
        Colors.pink.shade400,
        Colors.teal.shade600,
        Colors.brown.shade400,
      ];
      final pieSections = <PieChartSectionData>[];
      final legend = <({String name, int count, Color color})>[];
      var ci = 0;
      for (final e in catMap.entries) {
        final sliceColor = pieColors[ci % pieColors.length];
        pieSections.add(PieChartSectionData(
          value: e.value.toDouble(),
          title: '',
          color: sliceColor,
          radius: 52,
        ));
        legend.add((name: e.key, count: e.value, color: sliceColor));
        ci++;
      }
      legend.sort((a, b) => b.count.compareTo(a.count));
      var eventDocs = allSorted.take(_maxEvents).toList();
      final list = <_EventStats>[];
      for (final d in eventDocs) {
        final data = d.data();
        final title = (data['title'] ?? 'Evento').toString();
        final rsvp = (data['rsvp'] as List?)?.length ?? 0;
        final likes = (data['likes'] as List?)?.length ?? 0;
        list.add(_EventStats(
            title: title,
            rsvp: rsvp,
            likes: likes,
            comments: 0,
            eventRef: d.reference));
      }
      if (mounted) {
        setState(() {
          _stats = list;
          _categoryPieSections = pieSections;
          _categoryLegend = legend;
          _loading = false;
        });
      }
      unawaited(_enrichDashboardCommentCounts(eventDocs, list));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _enrichDashboardCommentCounts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> eventDocs,
    List<_EventStats> base,
  ) async {
    if (eventDocs.isEmpty || !mounted) return;
    try {
      final commentCounts = await Future.wait<int>(
        eventDocs.map((d) async {
          try {
            final countSnap =
                await d.reference.collection('comentarios').count().get();
            return countSnap.count ?? 0;
          } catch (_) {
            return 0;
          }
        }),
      );
      if (!mounted) return;
      final enriched = <_EventStats>[];
      for (var i = 0; i < eventDocs.length; i++) {
        final b = base[i];
        enriched.add(_EventStats(
          title: b.title,
          rsvp: b.rsvp,
          likes: b.likes,
          comments: commentCounts[i],
          eventRef: b.eventRef,
        ));
      }
      setState(() => _stats = enriched);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _stats.isEmpty) {
      return const ChurchPanelLoadingBody();
    }
    if (_error != null) {
      return ChurchPanelErrorBody(
        title: 'Não foi possível carregar as estatísticas dos eventos',
        error: _error,
        onRetry: _load,
      );
    }
    if (_stats.isEmpty) {
      return ThemeCleanPremium.premiumEmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'Nenhum evento para exibir',
        subtitle:
            'Publique eventos no Feed para ver estatísticas de RSVP, curtidas e comentários aqui.',
      );
    }
    final padding = ThemeCleanPremium.pagePadding(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding:
            EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, 80),
        children: [
          const SizedBox(height: 8),
          if (_categoryPieSections.isNotEmpty) ...[
            _ChartCard(
              title: 'Eventos por categoria (amostra dos últimos registros)',
              icon: Icons.pie_chart_outline_rounded,
              color: const Color(0xFF7C3AED),
              onTap: null,
              child: _CategoryPiePanel(legend: _categoryLegend),
            ),
            const SizedBox(height: ThemeCleanPremium.spaceLg),
          ],
          _DashboardTotalsRow(stats: _stats),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _ChartCard(
            title: 'Confirmações de presença (RSVP) por evento',
            icon: Icons.check_circle_rounded,
            color: ThemeCleanPremium.success,
            onTap: () => _showNamesSheet(context, 'rsvp'),
            child: _EventMetricBars(
              stats: _stats,
              valueOf: (e) => e.rsvp,
              color: ThemeCleanPremium.success,
              maxItems: _dashboardChartMaxItems(context),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _ChartCard(
            title: 'Curtidas por evento',
            icon: Icons.favorite_rounded,
            color: Colors.red.shade400,
            onTap: () => _showNamesSheet(context, 'likes'),
            child: _EventMetricBars(
              stats: _stats,
              valueOf: (e) => e.likes,
              color: Colors.red.shade400,
              maxItems: _dashboardChartMaxItems(context),
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceLg),
          _ChartCard(
            title: 'Comentários por evento',
            icon: Icons.comment_rounded,
            color: const Color(0xFF0EA5E9),
            onTap: () => _showNamesSheet(context, 'comments'),
            child: _EventMetricBars(
              stats: _stats,
              valueOf: (e) => e.comments,
              color: const Color(0xFF0EA5E9),
              maxItems: _dashboardChartMaxItems(context),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showNamesSheet(BuildContext context, String type) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _EventNamesSheet(
          stats: _stats, type: type, canDeleteComments: widget.canWrite),
    );
  }

  int _dashboardChartMaxItems(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1100) return 15;
    if (w >= 720) return 12;
    return 8;
  }
}

/// Resumo rápido no topo do dashboard.
class _DashboardTotalsRow extends StatelessWidget {
  final List<_EventStats> stats;

  const _DashboardTotalsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    var rsvp = 0;
    var likes = 0;
    var comments = 0;
    for (final s in stats) {
      rsvp += s.rsvp;
      likes += s.likes;
      comments += s.comments;
    }
    final narrow = MediaQuery.sizeOf(context).width < 520;
    Widget chip(IconData icon, String label, String value, Color color) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
                height: 1.2,
              ),
            ),
          ],
        ),
      );
    }

    Widget chipExpanded(
      IconData icon,
      String label,
      String value,
      Color color,
    ) {
      return Expanded(child: chip(icon, label, value, color));
    }

    if (narrow) {
      return Column(
        children: [
          chip(Icons.check_circle_rounded, 'RSVP total', '$rsvp',
              ThemeCleanPremium.success),
          const SizedBox(height: 8),
          Row(
            children: [
              chipExpanded(Icons.favorite_rounded, 'Curtidas', '$likes',
                  Colors.red.shade400),
              const SizedBox(width: 10),
              chipExpanded(Icons.comment_rounded, 'Comentários', '$comments',
                  const Color(0xFF0EA5E9)),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        chipExpanded(Icons.check_circle_rounded, 'RSVP total', '$rsvp',
            ThemeCleanPremium.success),
        const SizedBox(width: 10),
        chipExpanded(Icons.favorite_rounded, 'Curtidas', '$likes',
            Colors.red.shade400),
        const SizedBox(width: 10),
        chipExpanded(Icons.comment_rounded, 'Comentários', '$comments',
            const Color(0xFF0EA5E9)),
      ],
    );
  }
}

/// Barras horizontais — nomes completos, sem tooltips sobrepostos (web / iOS / Android).
class _EventMetricBars extends StatelessWidget {
  final List<_EventStats> stats;
  final int Function(_EventStats) valueOf;
  final Color color;
  final int maxItems;

  const _EventMetricBars({
    required this.stats,
    required this.valueOf,
    required this.color,
    required this.maxItems,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = List<_EventStats>.from(stats)
      ..sort((a, b) => valueOf(b).compareTo(valueOf(a)));
    final top = sorted.take(maxItems).toList();
    if (top.isEmpty) {
      return Text(
        'Sem dados para exibir.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
        ),
      );
    }
    final maxVal = top.map(valueOf).fold<int>(0, (a, b) => a > b ? a : b);
    final scale = maxVal <= 0 ? 1 : maxVal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Top ${top.length} — maior valor primeiro',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < top.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _EventMetricBarRow(
            rank: i + 1,
            title: top[i].title,
            value: valueOf(top[i]),
            fraction: valueOf(top[i]) / scale,
            color: color,
          ),
        ],
        if (stats.length > maxItems)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '+ ${stats.length - maxItems} evento(s) fora do gráfico — toque no cartão para ver a lista completa.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
                height: 1.35,
              ),
            ),
          ),
      ],
    );
  }
}

class _EventMetricBarRow extends StatelessWidget {
  final int rank;
  final String title;
  final int value;
  final double fraction;
  final Color color;

  const _EventMetricBarRow({
    required this.rank,
    required this.title,
    required this.value,
    required this.fraction,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final barFraction = fraction.clamp(0.0, 1.0);
    return Semantics(
      label: '$title: $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    color: ThemeCleanPremium.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth * barFraction;
              return Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    height: 10,
                    width: w < 4 && value > 0 ? 4 : w,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.85),
                          color,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
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
    );
  }
}

/// Pizza + legenda lateral (sem texto sobreposto nas fatias).
class _CategoryPiePanel extends StatelessWidget {
  final List<({String name, int count, Color color})> legend;

  const _CategoryPiePanel({required this.legend});

  @override
  Widget build(BuildContext context) {
    if (legend.isEmpty) return const SizedBox.shrink();
    final sections = legend
        .map(
          (e) => PieChartSectionData(
            value: e.count.toDouble(),
            title: '',
            color: e.color,
            radius: 52,
          ),
        )
        .toList();
    final total = legend.fold<int>(0, (a, e) => a + e.count);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 520;
        final pie = SizedBox(
          height: wide ? 200 : 180,
          width: wide ? 200 : double.infinity,
          child: PieChart(
            PieChartData(
              sections: sections,
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              startDegreeOffset: -90,
            ),
          ),
        );
        if (!wide) {
          return Column(
            children: [
              pie,
              const SizedBox(height: 12),
              _CategoryLegend(legend: legend, total: total),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            pie,
            const SizedBox(width: 16),
            Expanded(
              child: _CategoryLegend(legend: legend, total: total),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  final List<({String name, int count, Color color})> legend;
  final int total;

  const _CategoryLegend({
    required this.legend,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < legend.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(
                  color: legend[i].color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  legend[i].name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${legend[i].count} (${total > 0 ? ((legend[i].count / total) * 100).round() : 0}%)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EventStats {
  final String title;
  final int rsvp;
  final int likes;
  final int comments;
  final DocumentReference<Map<String, dynamic>> eventRef;
  _EventStats(
      {required this.title,
      required this.rsvp,
      required this.likes,
      required this.comments,
      required this.eventRef});
}

/// Sheet: selecionar evento e ver nomes (RSVP, curtidas) ou lista de comentários com opção de excluir.
class _EventNamesSheet extends StatefulWidget {
  final List<_EventStats> stats;
  final String type;
  final bool canDeleteComments;

  const _EventNamesSheet(
      {required this.stats,
      required this.type,
      this.canDeleteComments = false});

  @override
  State<_EventNamesSheet> createState() => _EventNamesSheetState();
}

class _EventNamesSheetState extends State<_EventNamesSheet> {
  int _selectedIndex = 0;
  List<String> _names = [];
  bool _loading = false;
  String? _error;
  int _commentsStreamKey = 0;

  _EventStats get _selected =>
      widget.stats[_selectedIndex.clamp(0, widget.stats.length - 1)];

  Future<void> _loadNames() async {
    if (widget.stats.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _names = [];
    });
    try {
      final ref = _selected.eventRef;
      final snap = await ref.get();
      final data = snap.data() ?? {};
      if (widget.type == 'rsvp') {
        final uids = (data['rsvp'] as List?)
                ?.map((e) => e?.toString().trim())
                .where((s) => s != null && s!.isNotEmpty)
                .cast<String>()
                .toList() ??
            [];
        final list = <String>[];
        for (final uid in uids) {
          try {
            final u = await firebaseDefaultFirestore
                .collection('users')
                .doc(uid)
                .get();
            final n = (u.data()?['nome'] ??
                    u.data()?['name'] ??
                    u.data()?['displayName'] ??
                    'Membro')
                .toString();
            list.add(n.isNotEmpty ? n : uid);
          } catch (_) {
            list.add(uid);
          }
        }
        if (mounted)
          setState(() {
            _names = list;
            _loading = false;
          });
      } else if (widget.type == 'likes') {
        final uids = (data['likes'] as List?)
                ?.map((e) => e?.toString().trim())
                .where((s) => s != null && s!.isNotEmpty)
                .cast<String>()
                .toList() ??
            [];
        final list = <String>[];
        for (final uid in uids) {
          try {
            final u = await firebaseDefaultFirestore
                .collection('users')
                .doc(uid)
                .get();
            final n = (u.data()?['nome'] ??
                    u.data()?['name'] ??
                    u.data()?['displayName'] ??
                    'Membro')
                .toString();
            list.add(n.isNotEmpty ? n : uid);
          } catch (_) {
            list.add(uid);
          }
        }
        if (mounted)
          setState(() {
            _names = list;
            _loading = false;
          });
      } else {
        if (mounted)
          setState(() {
            _loading = false;
          });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.type != 'comments') _loadNames();
  }

  @override
  void didUpdateWidget(covariant _EventNamesSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats != widget.stats ||
        _selectedIndex >= widget.stats.length) _selectedIndex = 0;
  }

  String get _titleLabel {
    switch (widget.type) {
      case 'rsvp':
        return 'Confirmações de presença';
      case 'likes':
        return 'Curtidas';
      case 'comments':
        return 'Comentários';
      default:
        return 'Lista';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stats.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Nenhum evento disponível.')));
    }
    final canDelete = widget.type == 'comments' && widget.canDeleteComments;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 8),
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_titleLabel,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<int>(
              value: _selectedIndex.clamp(0, widget.stats.length - 1),
              decoration: InputDecoration(
                  labelText: 'Evento',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12))),
              items: List.generate(
                  widget.stats.length,
                  (i) => DropdownMenuItem(
                      value: i,
                      child: Text(widget.stats[i].title,
                          overflow: TextOverflow.ellipsis))),
              onChanged: (v) {
                if (v != null)
                  setState(() {
                    _selectedIndex = v;
                  });
                if (widget.type != 'comments') _loadNames();
              },
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: Colors.grey.shade200),
          Expanded(
            child: widget.type == 'comments'
                ? StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey('com_sheet_$_commentsStreamKey'),
                    stream: _selected.eventRef
                        .collection('comentarios')
                        .watchSafe(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return ChurchPanelErrorBody(
                          title: 'Não foi possível carregar os comentários',
                          error: snap.error,
                          onRetry: () =>
                              setState(() => _commentsStreamKey++),
                        );
                      }
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return const ChurchPanelLoadingBody();
                      }
                      var docs = snap.data?.docs ?? [];
                      docs = List.from(docs);
                      docs.sort((a, b) {
                        final ta = a.data()['createdAt'];
                        final tb = b.data()['createdAt'];
                        if (ta is Timestamp && tb is Timestamp)
                          return ta.compareTo(tb);
                        return 0;
                      });
                      if (docs.isEmpty)
                        return Center(
                            child: Text('Nenhum comentário neste evento.',
                                style: TextStyle(color: Colors.grey.shade600)));
                      return ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final c = docs[i].data();
                          final name = (c['authorName'] ?? 'Membro').toString();
                          final text =
                              (c['text'] ?? c['texto'] ?? '').toString();
                          final ts = c['createdAt'];
                          String timeAgo = '';
                          if (ts is Timestamp) {
                            final d = DateTime.now().difference(ts.toDate());
                            if (d.inDays > 0)
                              timeAgo = '${d.inDays}d';
                            else if (d.inHours > 0)
                              timeAgo = '${d.inHours}h';
                            else if (d.inMinutes > 0)
                              timeAgo = '${d.inMinutes}min';
                            else
                              timeAgo = 'agora';
                          }
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(text),
                                    const SizedBox(height: 4),
                                    Text(timeAgo,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500))
                                  ]),
                              trailing: canDelete
                                  ? IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          color: Colors.red),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                                  title: const Text(
                                                      'Excluir comentário'),
                                                  content: const Text(
                                                      'Deseja excluir este comentário?'),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, false),
                                                        child: const Text(
                                                            'Cancelar')),
                                                    FilledButton(
                                                        style: FilledButton
                                                            .styleFrom(
                                                                backgroundColor:
                                                                    ThemeCleanPremium
                                                                        .error),
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, true),
                                                        child: const Text(
                                                            'Excluir'))
                                                  ],
                                                ));
                                        if (ok == true)
                                          await docs[i].reference.delete();
                                      },
                                      tooltip: 'Excluir comentário')
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                  )
                : _loading
                    ? const ChurchPanelLoadingBody()
                    : _error != null
                        ? ChurchPanelErrorBody(
                            title: 'Não foi possível carregar a lista',
                            error: _error,
                            onRetry: _loadNames,
                          )
                        : _names.isEmpty
                            ? Center(
                                child: Text('Nenhum registro.',
                                    style:
                                        TextStyle(color: Colors.grey.shade600)))
                            : ListView.builder(
                                controller: scrollCtrl,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: _names.length,
                                itemBuilder: (_, i) => ListTile(
                                    leading: CircleAvatar(
                                        backgroundColor: ThemeCleanPremium
                                            .primary
                                            .withOpacity(0.12),
                                        child: Text(
                                            _names[i].isNotEmpty
                                                ? _names[i][0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700))),
                                    title: Text(_names[i])),
                              ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  const _ChartCard(
      {required this.title,
      required this.icon,
      required this.color,
      required this.child,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
          decoration: BoxDecoration(
            color: ThemeCleanPremium.cardBackground,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm)),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: ThemeCleanPremium.onSurface))),
                  if (onTap != null)
                    Icon(Icons.visibility_rounded,
                        size: 18, color: Colors.grey.shade500),
                ],
              ),
              if (onTap != null)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        'Toque no cartão para ver nomes e detalhes',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600))),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Só monta abas pesadas (Galeria, Fixos, Dashboard) quando o utilizador as abre.
class _LazyEventsTabGate extends StatefulWidget {
  final int tabIndex;
  final TabController controller;
  final Widget child;

  const _LazyEventsTabGate({
    required this.tabIndex,
    required this.controller,
    required this.child,
  });

  @override
  State<_LazyEventsTabGate> createState() => _LazyEventsTabGateState();
}

class _LazyEventsTabGateState extends State<_LazyEventsTabGate> {
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    _activated = widget.controller.index == widget.tabIndex;
    widget.controller.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (!_activated && widget.controller.index == widget.tabIndex) {
      setState(() => _activated = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_activated) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}
