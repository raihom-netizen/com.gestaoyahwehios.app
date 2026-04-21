import 'dart:async' show Stream, StreamSubscription, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaPhotoUrls,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaVideosFromDoc,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaExternalVideoUrl,
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaFeedCoverHintUrl,
        eventNoticiaImageStoragePath,
        eventNoticiaPostHasFeedCoverRow,
        eventNoticiaThumbStoragePath,
        looksLikeHostedVideoFileUrl,
        postFeedCarouselAspectRatioForIndex;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        FreshFirebaseStorageImage,
        SafeNetworkImage,
        churchTenantLogoUrl,
        sanitizeImageUrl,
        isValidImageUrl,
        memCacheExtentForLogicalSize,
        preloadNetworkImages;
import 'package:gestao_yahweh/core/noticia_event_feed.dart'
    show noticiaDocEhEventoSpecialFeed;
import 'package:gestao_yahweh/app_version.dart'
    show appVersion, appVersionLabel;
import 'package:gestao_yahweh/ui/widgets/version_footer.dart'
    show kVersiculoRef, kVersiculoRodape;
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_institutional_video.dart';
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_premium_ui.dart'
    show
        ChurchPublicConstrainedMedia,
        ChurchPublicFeedItemWidth,
        ChurchPublicPremiumScheduleEventCard,
        ChurchPublicPremiumSection,
        churchPublicCoverMemCache,
        churchPublicFeedMediaMaxHeight;
import 'package:gestao_yahweh/ui/widgets/lazy_viewport_media.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart';
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_feed_video.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_social_post_bar.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_event_detail_sheet.dart';
import 'package:gestao_yahweh/ui/site_publico_igreja/church_public_site_shell.dart';
import 'package:gestao_yahweh/ui/site_publico_igreja/church_public_donation_sheet.dart';
import 'package:gestao_yahweh/ui/site_publico_igreja/church_public_proximo_culto.dart';
import 'package:gestao_yahweh/services/public_site_analytics.dart';
import 'package:gestao_yahweh/ui/web/church_public_seo.dart';
import 'package:gestao_yahweh/ui/web/open_external_url.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/services/subscription_guard.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/event_template_schedule.dart';
import 'package:gestao_yahweh/core/event_gallery_archive.dart';
import 'package:gestao_yahweh/ui/site_publico_igreja/church_public_social_portal.dart';
import 'package:gestao_yahweh/ui/pages/legal_pages.dart'
    show
        showGestaoYahwehLegalPreview,
        kLegalSupportEmail,
        kLegalSupportWhatsAppDisplay,
        kLegalSupportWhatsAppWaMe,
        kDeveloperPublicName;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Capa para site público — mesma lógica centralizada em [eventNoticiaFeedCoverHintUrl].
String _churchPublicNoticiaCoverUrl(Map<String, dynamic> p) =>
    eventNoticiaFeedCoverHintUrl(p);

bool _churchPublicDocIsAviso(
  QueryDocumentSnapshot<Map<String, dynamic>> d,
) =>
    d.reference.path
        .contains('/${ChurchTenantPostsCollections.avisos}/');

bool _churchPublicDocIsNoticiaEvento(
  QueryDocumentSnapshot<Map<String, dynamic>> d,
) =>
    d.reference.path
        .contains('/${ChurchTenantPostsCollections.noticias}/');

/// Site público: oculta após validade ou expiração de aviso (documento excluído some do stream).
bool _churchPublicDocStillActive(Map<String, dynamic> m, DateTime now) {
  // Eventos marcados para galeria permanente continuam visíveis no site público
  // via seção de arquivo, mesmo quando já passaram da validade padrão.
  if (eventShouldMoveToGalleryArchive(m, now)) return true;
  final v = m['validUntil'];
  if (v is Timestamp && !v.toDate().isAfter(now)) return false;
  final type = (m['type'] ?? 'aviso').toString();
  if (type == 'aviso') {
    final exp = m['avisoExpiresAt'];
    if (exp is Timestamp && !exp.toDate().isAfter(now)) return false;
  }
  return true;
}

/// Eventos em `noticias` + avisos em `avisos`, ordenados por `createdAt`.
Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    _churchPublicMergedPublicacoesStream(String igrejaId, {int limit = 48}) {
  return Stream.multi((controller) {
    var noticiasOk = true;
    var avisosOk = true;
    QuerySnapshot<Map<String, dynamic>>? snapNoticias;
    QuerySnapshot<Map<String, dynamic>>? snapAvisos;

    void emit() {
      if ((noticiasOk && snapNoticias == null) ||
          (avisosOk && snapAvisos == null)) {
        return;
      }
      final merged = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final now = DateTime.now();

      final notDocs = noticiasOk ? snapNoticias!.docs : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      final aviDocs = avisosOk ? snapAvisos!.docs : <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (final d in notDocs) {
        final m = d.data();
        if ((m['type'] ?? '').toString() != 'evento') continue;
        if (m['publicSite'] == false) continue;
        if (!_churchPublicDocStillActive(m, now)) continue;
        if (!noticiaDocEhEventoSpecialFeed(d)) continue;
        merged.add(d);
      }
      for (final d in aviDocs) {
        final m = d.data();
        if (m['publicSite'] == false) continue;
        if (!_churchPublicDocStillActive(m, now)) continue;
        merged.add(d);
      }
      merged.sort((a, b) {
        final ca = a.data()['createdAt'];
        final cb = b.data()['createdAt'];
        final ta = ca is Timestamp ? ca.toDate() : null;
        final tb = cb is Timestamp ? cb.toDate() : null;
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });
      controller.add(merged);
    }

    // Só documentos com publicSite == true: o Firestore exige que a query não possa
    // devolver posts privados (publicSite == false); senão visitante sem login leva
    // permission-denied em listas sem filtro — mesmo que o app filtre depois no cliente.
    final base = FirebaseFirestore.instance.collection('igrejas').doc(igrejaId);
    final sub1 = base
        .collection(ChurchTenantPostsCollections.noticias)
        .where('publicSite', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .listen((s) {
      snapNoticias = s;
      emit();
    }, onError: (_) {
      noticiasOk = false;
      emit();
    });
    final sub2 = base
        .collection(ChurchTenantPostsCollections.avisos)
        .where('publicSite', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .listen((s) {
      snapAvisos = s;
      emit();
    }, onError: (_) {
      avisosOk = false;
      emit();
    });

    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
    };
  });
}

/// Mural público como [SliverList] lazy (evita [ListView] com shrinkWrap a construir tudo).
class _ChurchPublicMuralStreamSliver extends StatefulWidget {
  final String igrejaId;
  final String slugClean;
  final Color accent;
  final GlobalKey sectionAvisosKey;
  final GlobalKey sectionDestaquesKey;
  final Future<void> Function(BuildContext context, Map<String, dynamic> p)
      onOpenHostedVideoFromMap;
  final void Function(String action)? onChurchPublicAction;

  const _ChurchPublicMuralStreamSliver({
    required this.igrejaId,
    required this.slugClean,
    required this.accent,
    required this.sectionAvisosKey,
    required this.sectionDestaquesKey,
    required this.onOpenHostedVideoFromMap,
    this.onChurchPublicAction,
  });

  @override
  State<_ChurchPublicMuralStreamSliver> createState() =>
      _ChurchPublicMuralStreamSliverState();
}

class _ChurchPublicMuralStreamSliverState
    extends State<_ChurchPublicMuralStreamSliver> {
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _sub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>>? _items;
  Object? _error;
  bool _didWarmup = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = _churchPublicMergedPublicacoesStream(widget.igrejaId, limit: 48)
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list;
          _error = null;
        });
        if (!_didWarmup && list.isNotEmpty) {
          _didWarmup = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final ev = list.where(_churchPublicDocIsNoticiaEvento).take(8);
            final warm = ev.isNotEmpty
                ? ev.map((d) => d.data()).toList()
                : list.take(8).map((d) => d.data()).toList();
            unawaited(scheduleFeedMediaWarmup(
              context,
              warm,
              maxDocs: 8,
            ));
          });
        }
      },
      onError: (e) {
        if (mounted) setState(() => _error = e);
      },
    );
  }

  @override
  void didUpdateWidget(covariant _ChurchPublicMuralStreamSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.igrejaId != widget.igrejaId) {
      _didWarmup = false;
      _items = null;
      _error = null;
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SliverToBoxAdapter(
        child: ChurchPublicFeedItemWidth(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Erro ao carregar o mural: $_error',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ),
      );
    }
    if (_items == null) {
      return SliverToBoxAdapter(
        child: ChurchPublicFeedItemWidth(
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: LinearProgressIndicator(),
          ),
        ),
      );
    }
    final items = _items!;
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: ChurchPublicFeedItemWidth(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.forum_rounded,
                    size: 40,
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Nenhuma publicação ainda',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'O gestor pode publicar avisos, fotos e vídeos pelo painel da igreja.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        widget.onChurchPublicAction
                            ?.call('signup_church_empty_mural');
                        Navigator.pushNamed(context, '/signup');
                      },
                      icon: const Icon(Icons.church_rounded),
                      label: const Text('Cadastrar igreja'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () {
                        widget.onChurchPublicAction
                            ?.call('admin_empty_mural');
                        Navigator.pushNamed(context, '/admin');
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Área administrativa'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final mem = churchPublicCoverMemCache(context);
    final memW = mem.$1;
    final memH = mem.$2;
    final avisos = items.where(_churchPublicDocIsAviso).toList();
    final eventos = items.where(_churchPublicDocIsNoticiaEvento).toList();
    final now = DateTime.now();
    final eventosArquivo = eventos
        .where((e) => eventShouldMoveToGalleryArchive(e.data(), now))
        .toList();
    final eventosAtivos = eventos
        .where((e) => !eventShouldMoveToGalleryArchive(e.data(), now))
        .toList();
    const avisosAccent = Color(0xFF7C3AED);

    Widget feedTile(
      QueryDocumentSnapshot<Map<String, dynamic>> doc, {
      bool galleryArchivePremium = false,
    }) {
      return RepaintBoundary(
        child: churchPublicSocialFeedTile(
          context: context,
          doc: doc,
          igrejaId: widget.igrejaId,
          churchSlug: widget.slugClean,
          accent: widget.accent,
          memCacheW: memW,
          memCacheH: memH,
          galleryArchivePremiumLayout: galleryArchivePremium,
          onOpenHostedVideo: (ctx, p, __) async {
            await widget.onOpenHostedVideoFromMap(ctx, p);
          },
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) {
            return KeyedSubtree(
              key: widget.sectionAvisosKey,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 22),
                child: ChurchPublicFeedItemWidth(
                  child: ChurchPublicPremiumSection(
                    kicker: 'Comunicação',
                    title: 'Avisos',
                    subtitle:
                        'Comunicados oficiais da igreja. Conteúdo separado do mural de eventos com fotos e vídeos.',
                    icon: Icons.campaign_rounded,
                    accentColor: avisosAccent,
                    child: avisos.isEmpty
                        ? const _ChurchPublicEmptySubsection(
                            icon: Icons.notifications_none_rounded,
                            message:
                                'Nenhum aviso público no momento. Volte em breve ou fale com a secretaria.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = 0; i < avisos.length; i++) ...[
                                if (i > 0) const SizedBox(height: 18),
                                feedTile(avisos[i]),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            );
          }
          if (index == 1) {
            return KeyedSubtree(
              key: widget.sectionDestaquesKey,
              child: ChurchPublicFeedItemWidth(
                child: ChurchPublicPremiumSection(
                  kicker: 'Eventos',
                  title: 'Fotos e vídeos',
                  subtitle:
                      'Mural com mídia: cultos especiais, confraternizações e campanhas. Após o evento, fica 1 dia no destaque e depois vai para a galeria de arquivo.',
                  icon: Icons.photo_library_rounded,
                  accentColor: widget.accent,
                  child: eventos.isEmpty
                      ? const _ChurchPublicEmptySubsection(
                          icon: Icons.perm_media_outlined,
                          message:
                              'Nenhum evento com mídia público ainda. O gestor publica pelo painel em Mural de eventos.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (eventosAtivos.isNotEmpty) ...[
                              for (var j = 0; j < eventosAtivos.length; j++) ...[
                                if (j > 0) const SizedBox(height: 18),
                                feedTile(eventosAtivos[j]),
                              ],
                            ],
                            if (eventosArquivo.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  'Arquivo da Galeria de Eventos',
                                  style: TextStyle(
                                    color: widget.accent,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (var j = 0;
                                  j < (eventosArquivo.length > 6
                                      ? 6
                                      : eventosArquivo.length);
                                  j++) ...[
                              if (j > 0) const SizedBox(height: 18),
                                feedTile(
                                  eventosArquivo[j],
                                  galleryArchivePremium: true,
                                ),
                              ],
                              if (eventosArquivo.length > 6) ...[
                                const SizedBox(height: 10),
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _PublicEventsGalleryPage(
                                          docs: eventosArquivo,
                                          accent: widget.accent,
                                          igrejaId: widget.igrejaId,
                                          churchSlug: widget.slugClean,
                                          memCacheW: memW,
                                          memCacheH: memH,
                                          onOpenHostedVideoFromMap:
                                              widget.onOpenHostedVideoFromMap,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.open_in_new_rounded),
                                  label: Text(
                                      'Ver galeria completa (${eventosArquivo.length})'),
                                ),
                              ],
                            ],
                          ],
                        ),
                ),
              ),
            );
          }
          return ChurchPublicFeedItemWidth(
            child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      widget.onChurchPublicAction?.call('login_mural_footer');
                      Navigator.pushNamed(context, '/igreja/login');
                    },
                    icon: const Icon(Icons.login),
                    label: const Text('Acessar Sistema'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      widget.onChurchPublicAction?.call('admin_mural_footer');
                      Navigator.pushNamed(context, '/admin');
                    },
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                    label: const Text('Sou administrador'),
                  ),
                ],
              ),
            ),
          );
        },
        childCount: 3,
      ),
    );
  }
}

/// Estado vazio dentro de uma subsecção do site público (avisos / destaques).
class _ChurchPublicEmptySubsection extends StatelessWidget {
  final IconData icon;
  final String message;

  const _ChurchPublicEmptySubsection({
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.grey.shade500, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicEventsGalleryPage extends StatefulWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final Color accent;
  final String igrejaId;
  final String churchSlug;
  final int memCacheW;
  final int memCacheH;
  final Future<void> Function(BuildContext context, Map<String, dynamic> p)
      onOpenHostedVideoFromMap;

  const _PublicEventsGalleryPage({
    required this.docs,
    required this.accent,
    required this.igrejaId,
    required this.churchSlug,
    required this.memCacheW,
    required this.memCacheH,
    required this.onOpenHostedVideoFromMap,
  });

  @override
  State<_PublicEventsGalleryPage> createState() => _PublicEventsGalleryPageState();
}

class _PublicEventsGalleryPageState extends State<_PublicEventsGalleryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _order = 'recent_first';
  String _mediaType = 'all';
  String _monthYear = 'all';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  DateTime? _eventDate(Map<String, dynamic> p) {
    final d = eventArchiveBaseDate(p);
    if (d != null) return d;
    final c = p['createdAt'];
    if (c is Timestamp) return c.toDate();
    return null;
  }

  String _monthYearKey(DateTime? d) {
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}';
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

  @override
  Widget build(BuildContext context) {
    var docs = widget.docs.toList();
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      docs = docs.where((d) {
        final p = d.data();
        final t = (p['title'] ?? '').toString().toLowerCase();
        final body = (p['text'] ?? '').toString().toLowerCase();
        return t.contains(q) || body.contains(q);
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
    final monthOptions = <MapEntry<String, String>>[];
    final monthSeen = <String>{};
    for (final d in docs) {
      final key = _monthYearKey(_eventDate(d.data()));
      if (key.isEmpty || monthSeen.contains(key)) continue;
      monthSeen.add(key);
      monthOptions.add(MapEntry(key, _monthYearLabel(_eventDate(d.data()))));
    }
    monthOptions.sort((a, b) => b.key.compareTo(a.key));
    if (_monthYear != 'all') {
      docs = docs
          .where((d) => _monthYearKey(_eventDate(d.data())) == _monthYear)
          .toList();
    }
    docs.sort((a, b) {
      final da = _eventDate(a.data()) ?? DateTime(1900);
      final db = _eventDate(b.data()) ?? DateTime(1900);
      final cmp = db.compareTo(da);
      return _order == 'recent_first' ? cmp : -cmp;
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Galeria de Eventos'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Voltar',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Pesquisar evento',
                    prefixIcon: Icon(Icons.search_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _order,
                        decoration: const InputDecoration(
                          labelText: 'Ordem',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'recent_first',
                              child: Text('Último -> antigo')),
                          DropdownMenuItem(
                              value: 'old_first',
                              child: Text('Antigo -> último')),
                        ],
                        onChanged: (v) =>
                            setState(() => _order = v ?? 'recent_first'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _mediaType,
                        decoration: const InputDecoration(
                          labelText: 'Mídia',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Todas')),
                          DropdownMenuItem(value: 'photos', child: Text('Fotos')),
                          DropdownMenuItem(value: 'videos', child: Text('Vídeos')),
                        ],
                        onChanged: (v) =>
                            setState(() => _mediaType = v ?? 'all'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _monthYear,
                  decoration: const InputDecoration(
                    labelText: 'Ano/Mês específico',
                    border: OutlineInputBorder(),
                    isDense: true,
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
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (docs.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: Text('Nenhum evento encontrado.')),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 18),
              itemBuilder: (context, i) {
                final doc = docs[i];
                return churchPublicSocialFeedTile(
                  context: context,
                  doc: doc,
                  igrejaId: widget.igrejaId,
                  churchSlug: widget.churchSlug,
                  accent: widget.accent,
                  memCacheW: widget.memCacheW,
                  memCacheH: widget.memCacheH,
                  galleryArchivePremiumLayout: true,
                  onOpenHostedVideo: (ctx, p, _) async {
                    await widget.onOpenHostedVideoFromMap(ctx, p);
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}

String _churchPublicWeekdayPt(int weekday) {
  const names = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  if (weekday < 1 || weekday > 7) return '';
  return names[weekday - 1];
}

Color _churchAccentFromData(Map<String, dynamic> data) {
  for (final k in [
    'sitePrimaryHex',
    'sitePrimaryColor',
    'corSite',
    'primaryHex'
  ]) {
    final v = (data[k] ?? '').toString().trim();
    if (v.isEmpty) continue;
    var s = v.replaceFirst('#', '').replaceAll(RegExp(r'\s'), '');
    if (s.length == 6) s = 'FF$s';
    if (s.length == 8) {
      final n = int.tryParse(s, radix: 16);
      if (n != null) return Color(n);
    }
  }
  return const Color(0xFF2563EB);
}

Future<void> _launchVideoFast(String rawUrl) async {
  final cleaned = sanitizeImageUrl(rawUrl);
  if (cleaned.isEmpty) return;
  final u =
      Uri.tryParse(cleaned.startsWith('http') ? cleaned : 'https://$cleaned');
  if (u == null) return;
  if (!await canLaunchUrl(u)) return;
  // Web/PWA: abre direto e rápido na mesma navegação/plataforma padrão.
  await launchUrl(u, mode: LaunchMode.platformDefault);
}

bool _isYoutubeOrVimeoUrl(String url) {
  final low = url.toLowerCase();
  return low.contains('youtube.com') ||
      low.contains('youtu.be') ||
      low.contains('vimeo.com');
}

class _PublicSocialProofStats {
  final int activeMembers;
  final int monthPosts;
  const _PublicSocialProofStats({
    required this.activeMembers,
    required this.monthPosts,
  });
}

Future<_PublicSocialProofStats> _loadPublicSocialProofStats(
    String igrejaId) async {
  final db = FirebaseFirestore.instance;
  try {
    final membersAgg = await db
        .collection('igrejas')
        .doc(igrejaId)
        .collection('membros')
        .where('status', isEqualTo: 'ativo')
        .count()
        .get();
    final from =
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));
    final postsNoticias = await db
        .collection('igrejas')
        .doc(igrejaId)
        .collection(ChurchTenantPostsCollections.noticias)
        .where('publicSite', isEqualTo: true)
        .where('createdAt', isGreaterThanOrEqualTo: from)
        .count()
        .get();
    final postsAvisos = await db
        .collection('igrejas')
        .doc(igrejaId)
        .collection(ChurchTenantPostsCollections.avisos)
        .where('publicSite', isEqualTo: true)
        .where('createdAt', isGreaterThanOrEqualTo: from)
        .count()
        .get();
    return _PublicSocialProofStats(
      activeMembers: membersAgg.count ?? 0,
      monthPosts: (postsNoticias.count ?? 0) + (postsAvisos.count ?? 0),
    );
  } catch (_) {
    return const _PublicSocialProofStats(activeMembers: 0, monthPosts: 0);
  }
}

Future<void> _openPublicVideo(
  BuildContext context,
  String rawUrl, {
  String? thumbnailUrl,
  String title = '',
}) async {
  final cleaned = sanitizeImageUrl(rawUrl);
  if (cleaned.isEmpty) return;
  if (_isYoutubeOrVimeoUrl(cleaned)) {
    await _launchVideoFast(cleaned);
    return;
  }
  final resolved = await StorageMediaService.freshPlayableMediaUrl(cleaned);
  final base = sanitizeImageUrl(resolved);
  if (!(base.startsWith('http://') || base.startsWith('https://'))) return;
  if (Uri.tryParse(base) == null) return;
  if (!context.mounted) return;
  final thumb = sanitizeImageUrl(thumbnailUrl);
  await showChurchHostedVideoDialog(
    context,
    videoUrl: base,
    thumbnailUrl: isValidImageUrl(thumb) ? thumb : null,
    autoPlay: true,
    title: title,
  );
}

Future<void> _churchPublicOpenNoticiaVideoFromMap(
  BuildContext context,
  Map<String, dynamic> p,
) async {
  final hostedV = eventNoticiaHostedVideoPlayUrl(p);
  final extVid = eventNoticiaExternalVideoUrl(p);
  final legacyVideoUrl = (p['videoUrl'] ?? '').toString().trim();
  final raw = (hostedV != null && hostedV.isNotEmpty)
      ? hostedV
      : ((extVid != null && extVid.isNotEmpty) ? extVid : legacyVideoUrl);
  if (raw.isEmpty) return;
  final td = sanitizeImageUrl(eventNoticiaDisplayVideoThumbnailUrl(p) ?? '');
  final cv = sanitizeImageUrl(_churchPublicNoticiaCoverUrl(p));
  final thumb = isValidImageUrl(td) ? td : (isValidImageUrl(cv) ? cv : null);
  final t =
      (p['titulo'] ?? p['titulo_evento'] ?? '').toString().trim();
  await _openPublicVideo(context, raw, thumbnailUrl: thumb, title: t);
}

/// Pré-resolve a URL da logo (memoizada em [AppStorageImageService]) para o badge aparecer mais cedo.
class _ChurchPublicLogoWarmup extends StatefulWidget {
  final String tenantId;
  final Map<String, dynamic> churchData;
  final Widget child;

  const _ChurchPublicLogoWarmup({
    required this.tenantId,
    required this.churchData,
    required this.child,
  });

  @override
  State<_ChurchPublicLogoWarmup> createState() => _ChurchPublicLogoWarmupState();
}

class _ChurchPublicLogoWarmupState extends State<_ChurchPublicLogoWarmup> {
  void _warm() {
    final pref = churchTenantLogoUrl(widget.churchData);
    final path = ChurchImageFields.logoStoragePath(widget.churchData);
    unawaited(
      AppStorageImageService.instance.resolveChurchTenantLogoUrl(
        tenantId: widget.tenantId,
        tenantData: widget.churchData,
        preferImageUrl: pref.isNotEmpty ? pref : null,
        preferStoragePath: path,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _warm();
  }

  @override
  void didUpdateWidget(covariant _ChurchPublicLogoWarmup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        _cacheSigFor(oldWidget) != _cacheSigFor(widget)) {
      _warm();
    }
  }

  String _cacheSigFor(_ChurchPublicLogoWarmup w) {
    final pref = churchTenantLogoUrl(w.churchData);
    final path = ChurchImageFields.logoStoragePath(w.churchData);
    return AppStorageImageService.churchTenantLogoCacheKey(
      tenantId: w.tenantId,
      tenantData: w.churchData,
      preferImageUrl: pref.isNotEmpty ? pref : null,
      preferStoragePath: path,
      preferGsUrl: null,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dispara [PublicSiteAnalytics.logChurchPublicOpen] uma vez por igreja montada.
class _ChurchPublicOpenAnalyticsBinder extends StatefulWidget {
  final String slug;
  final String tenantId;
  final Widget child;

  const _ChurchPublicOpenAnalyticsBinder({
    required this.slug,
    required this.tenantId,
    required this.child,
  });

  @override
  State<_ChurchPublicOpenAnalyticsBinder> createState() =>
      _ChurchPublicOpenAnalyticsBinderState();
}

class _ChurchPublicOpenAnalyticsBinderState
    extends State<_ChurchPublicOpenAnalyticsBinder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PublicSiteAnalytics.logChurchPublicOpen(
        slug: widget.slug,
        tenantId: widget.tenantId,
      ));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ChurchPublicPageInner extends StatelessWidget {
  final String slug;

  /// Abre detalhe da publicação ao carregar (rota `/{slug}/{noticiaId}`).
  final String? openNoticiaId;
  final GlobalKey sectionInicioKey;
  final GlobalKey sectionAvisosKey;
  final GlobalKey sectionDestaquesKey;
  final GlobalKey sectionEventosKey;
  final VoidCallback onScrollInicio;
  final VoidCallback onScrollAvisos;
  final VoidCallback onScrollDestaques;
  final VoidCallback onScrollEventos;

  const _ChurchPublicPageInner({
    super.key,
    required this.slug,
    this.openNoticiaId,
    required this.sectionInicioKey,
    required this.sectionAvisosKey,
    required this.sectionDestaquesKey,
    required this.sectionEventosKey,
    required this.onScrollInicio,
    required this.onScrollAvisos,
    required this.onScrollDestaques,
    required this.onScrollEventos,
  });

  String _prettyName(String s) {
    final clean = s.replaceAll(RegExp(r'[^a-zA-Z0-9\-\s_]'), '');
    final parts = clean
        .replaceAll('_', '-')
        .split('-')
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Minha Igreja';
    return parts.map((p) {
      final t = p.trim();
      return t.isEmpty ? '' : '${t[0].toUpperCase()}${t.substring(1)}';
    }).join(' ');
  }

  Future<void> _launchExternal(BuildContext context, Uri uri) async {
    try {
      final ok = await openExternalApplicationUrl(uri);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir: ${uri.toString()}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir link: $e')),
        );
      }
    }
  }

  Uri _whatsAppUri(String raw, {String? churchName}) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    // padrão Brasil: se vier 55 já mantém, senão adiciona 55
    final phone = digits.startsWith('55') ? digits : '55$digits';
    final safeChurch = (churchName ?? '').trim();
    final msg = safeChurch.isEmpty
        ? 'Olá! Vi o site no Gestão YAHWEH e gostaria de mais informações.'
        : 'Olá! Vi o site da $safeChurch no Gestão YAHWEH e gostaria de mais informações.';
    return Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(msg)}');
  }

  /// Abre Google Maps: com lat/lng (pin exato) ou busca por endereço.
  Uri _mapsUri(String address, {double? latitude, double? longitude}) {
    if (latitude != null && longitude != null) {
      return Uri.parse('https://www.google.com/maps?q=$latitude,$longitude');
    }
    final q = Uri.encodeComponent(address);
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
  }

  @override
  Widget build(BuildContext context) {
    final slugClean = slug.trim().isEmpty ? 'minha-igreja' : slug.trim();

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFF8FAFC),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('igrejas')
              .where('slug', isEqualTo: slugClean)
              .limit(1)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return _ErrorBox(
                title: 'Não foi possível carregar esta igreja',
                message: 'Erro: ${snap.error}',
              );
            }
            if (!snap.hasData) {
              return ChurchPublicSiteScaffoldBackground(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 52,
                            height: 52,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: ThemeCleanPremium.primary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'A carregar o site da igreja…',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _prettyName(slugClean),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return _ChurchTenantFallback(
                slugClean: slugClean,
                prettyName: _prettyName(slugClean),
              );
            }

            final docSnap = docs.first;
            final igrejaId = docSnap.id;
            final data = docSnap.data();
            final churchDataWithId = Map<String, dynamic>.from(data)
              ..['id'] = igrejaId;
            final subscriptionState = SubscriptionGuard.evaluate(church: data);
            if (subscriptionState.blocked) {
              return _ChurchPublicMaintenanceView(
                churchName:
                    (data['nome'] ?? data['name'] ?? '').toString().trim(),
              );
            }
            final nome =
                (data['nome'] ?? data['name'] ?? _prettyName(slugClean))
                    .toString();
            final ativa = (data['ativa'] ?? true) == true;
            final doc = (data['cnpjCpf'] ?? '').toString().trim();
            final whatsapp = (data['whatsappIgreja'] ??
                    data['whatsapp_igreja'] ??
                    data['whatsapp'] ??
                    data['telefoneIgreja'] ??
                    data['telefone'] ??
                    data['phone'] ??
                    '')
                .toString()
                .trim();
            final gestorEmail = (data['gestorEmail'] ??
                    data['gestor_email'] ??
                    data['email'] ??
                    '')
                .toString()
                .trim();
            final gestorTelefone = (data['whatsappGestor'] ??
                    data['whatsapp_gestor'] ??
                    data['gestorWhatsapp'] ??
                    data['gestorTelefone'] ??
                    data['gestor_telefone'] ??
                    '')
                .toString()
                .trim();
            final whatsappContato =
                whatsapp.isNotEmpty ? whatsapp : gestorTelefone;
            final linkGoogleMaps =
                (data['linkGoogleMaps'] ?? data['googleMapsLink'] ?? '')
                    .toString()
                    .trim();
            final waLaunchUri = churchPublicWhatsappLaunchUri(
              data,
              fallbackPhoneRaw: whatsappContato,
              churchName: nome,
            );
            final waPrayerUri = churchPublicWhatsappPrayerUri(
              data,
              churchPhoneRaw: whatsapp,
              gestorPhoneRaw: gestorTelefone,
            );
            final endereco = churchPublicFormattedAddress(data);
            final lat = data['latitude'];
            final lng = data['longitude'];
            final latitude = lat is num
                ? lat.toDouble()
                : (lat != null ? double.tryParse(lat.toString()) : null);
            final longitude = lng is num
                ? lng.toDouble()
                : (lng != null ? double.tryParse(lng.toString()) : null);
            final horariosFromIgreja =
                (data['horariosCulto'] ?? data['horarios'] ?? '')
                    .toString()
                    .trim();
            final logoUrl = sanitizeImageUrl(churchTenantLogoUrl(data));

            final instagramUri = churchPublicSocialHttpUri(data, const [
              'instagramUrl',
              'instagram',
              'linkInstagram',
              'instagram_link',
            ]);
            final youtubeUri = churchPublicSocialHttpUri(data, const [
              'youtubeUrl',
              'youtube',
              'linkYoutube',
              'youtube_link',
            ]);
            final facebookUri = churchPublicSocialHttpUri(data, const [
              'facebookUrl',
              'facebook',
              'linkFacebook',
              'facebook_link',
            ]);

            final accent = _churchAccentFromData(data);
            final baseTh = Theme.of(context);
            final descParts = <String>[];
            if (endereco.isNotEmpty) descParts.add(endereco);
            if (horariosFromIgreja.isNotEmpty)
              descParts.add(horariosFromIgreja);
            final descMeta = descParts.join(' · ');
            final seoTitle = '$nome - Portal da Família';
            final canonicalUrl = AppConstants.publicChurchHomeUrlForChurch(
              slugClean,
              church: data,
            );

            void logChurchPublic(String action) {
              unawaited(PublicSiteAnalytics.logChurchPublicAction(
                action,
                slug: slugClean,
                tenantId: igrejaId,
              ));
            }

            return _ChurchPublicOpenAnalyticsBinder(
              slug: slugClean,
              tenantId: igrejaId,
              child: Theme(
                data: baseTh.copyWith(
                  colorScheme: ColorScheme.fromSeed(
                    seedColor: accent,
                    brightness: Brightness.light,
                  ),
                ),
                child: Builder(
                  builder: (context) {
                    return ChurchPublicSiteScaffoldBackground(
                      child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _ChurchPublicSeoBinder(
                          key: ValueKey('seo-$igrejaId'),
                          title: seoTitle,
                          description: descMeta.isEmpty
                              ? 'Site público — $nome. Mural, carteirinha e cultos — Gestão YAHWEH.'
                              : descMeta,
                          ogImageUrl: logoUrl.isNotEmpty ? logoUrl : null,
                          canonicalUrl: canonicalUrl,
                        ),
                        if (openNoticiaId != null &&
                            openNoticiaId!.trim().isNotEmpty)
                          _PublicNoticiaDeepLinkOpener(
                            igrejaId: igrejaId,
                            openNoticiaId: openNoticiaId!.trim(),
                          ),
                        _ChurchPublicLogoWarmup(
                          tenantId: igrejaId,
                          churchData: churchDataWithId,
                          child: CustomScrollView(
                          key: ValueKey(igrejaId),
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          slivers: [
                            ChurchPublicSiteSliverAppBar(
                              nome: nome,
                              tenantId: igrejaId,
                              churchData: churchDataWithId,
                              accentColor: accent,
                              onAcessar: () {
                                logChurchPublic('app_bar_access_system');
                                Navigator.pushNamed(context, '/igreja/login');
                              },
                              onDoacao: () {
                                logChurchPublic('app_bar_doacao');
                                showChurchPublicDonationSheet(
                                  context,
                                  tenantId: igrejaId,
                                  accentColor: accent,
                                  slugClean: slugClean,
                                );
                              },
                            ),
                            ChurchPublicPortalNavSliver(
                              accent: accent,
                              onInicio: onScrollInicio,
                              onAvisos: onScrollAvisos,
                              onDestaques: onScrollDestaques,
                              onEventos: onScrollEventos,
                              onAcessarSistema: () {
                                logChurchPublic('nav_access_system');
                                Navigator.pushNamed(context, '/igreja/login');
                              },
                            ),
                            SliverToBoxAdapter(
                              child: ChurchPublicWelcomeStrip(
                                churchName: nome,
                                accentColor: accent,
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: ChurchPublicFeedItemWidth(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 8, 12, 4),
                                  child: ChurchPublicContactBar(
                                    accentColor: accent,
                                    phoneLine: churchPublicFormattedPhone(data),
                                    addressLine: endereco,
                                    onWhatsApp: waLaunchUri == null
                                        ? null
                                        : () {
                                            logChurchPublic(
                                                'contact_bar_whatsapp');
                                            _launchExternal(
                                                context, waLaunchUri);
                                          },
                                    onMaps: (linkGoogleMaps.isNotEmpty ||
                                            (latitude != null &&
                                                longitude != null) ||
                                            endereco.trim().isNotEmpty)
                                        ? () {
                                            logChurchPublic(
                                                'contact_bar_maps');
                                            _launchExternal(
                                              context,
                                              linkGoogleMaps.isNotEmpty
                                                  ? (Uri.tryParse(
                                                          linkGoogleMaps) ??
                                                      _mapsUri(
                                                        endereco,
                                                        latitude: latitude,
                                                        longitude: longitude,
                                                      ))
                                                  : _mapsUri(
                                                      endereco,
                                                      latitude: latitude,
                                                      longitude: longitude,
                                                    ),
                                            );
                                          }
                                        : null,
                                    onEmail: gestorEmail.isEmpty
                                        ? null
                                        : () {
                                            logChurchPublic(
                                                'contact_bar_email');
                                            _launchExternal(
                                              context,
                                              Uri.parse(
                                                'mailto:${gestorEmail.trim()}',
                                              ),
                                            );
                                          },
                                    onInstagram: instagramUri == null
                                        ? null
                                        : () {
                                            logChurchPublic(
                                                'contact_bar_instagram');
                                            _launchExternal(
                                                context,
                                                instagramUri,
                                              );
                                          },
                                    onYoutube: youtubeUri == null
                                        ? null
                                        : () {
                                            logChurchPublic(
                                                'contact_bar_youtube');
                                            _launchExternal(
                                                context,
                                                youtubeUri,
                                              );
                                          },
                                    onFacebook: facebookUri == null
                                        ? null
                                        : () {
                                            logChurchPublic(
                                                'contact_bar_facebook');
                                            _launchExternal(
                                                context,
                                                facebookUri,
                                              );
                                          },
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
                              sliver: SliverToBoxAdapter(
                                child: ChurchPublicFeedItemWidth(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      KeyedSubtree(
                                        key: sectionInicioKey,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            ChurchPublicSiteHero(
                                              accentColor: accent,
                                              onMemberSignup: () {
                                                logChurchPublic(
                                                    'hero_member_signup');
                                                Navigator.pushNamed(context,
                                                    '/$slugClean/cadastro-membro');
                                              },
                                              onMemberLogin: () {
                                                logChurchPublic(
                                                    'hero_member_login');
                                                Navigator.pushNamed(
                                                    context, '/igreja/login');
                                              },
                                              onTalkChurch: waLaunchUri == null
                                                  ? null
                                                  : () {
                                                      logChurchPublic(
                                                          'hero_whatsapp');
                                                      _launchExternal(
                                                        context,
                                                        waLaunchUri,
                                                      );
                                                    },
                                              onOpenMaps: (linkGoogleMaps
                                                          .isNotEmpty ||
                                                      (latitude != null &&
                                                          longitude != null) ||
                                                      endereco
                                                          .trim()
                                                          .isNotEmpty)
                                                  ? () {
                                                      logChurchPublic(
                                                          'hero_maps');
                                                      _launchExternal(
                                                        context,
                                                        linkGoogleMaps
                                                                .isNotEmpty
                                                            ? (Uri.tryParse(
                                                                    linkGoogleMaps) ??
                                                                _mapsUri(
                                                                  endereco,
                                                                  latitude:
                                                                      latitude,
                                                                  longitude:
                                                                      longitude,
                                                                ))
                                                            : _mapsUri(
                                                                endereco,
                                                                latitude:
                                                                    latitude,
                                                                longitude:
                                                                    longitude,
                                                              ),
                                                      );
                                                    }
                                                  : null,
                                            ),
                                            const SizedBox(height: 16),
                                            ChurchPublicProximoCultoCard(
                                              igrejaId: igrejaId,
                                              churchName: nome,
                                              churchSlug: slugClean,
                                              accentColor: accent,
                                              enderecoIgreja: endereco,
                                              latitude: latitude,
                                              longitude: longitude,
                                              linkGoogleMaps: linkGoogleMaps,
                                              horariosText: horariosFromIgreja,
                                            ),
                                            if (mapHasInstitutionalVideo(
                                                data)) ...[
                                              const SizedBox(height: 28),
                                              PremiumInstitutionalVideoCard
                                                  .fromChurchDoc(
                                                data,
                                                height:
                                                    churchPublicFeedMediaMaxHeight(
                                                        MediaQuery.sizeOf(
                                                            context)),
                                                caption: 'VÍDEO INSTITUCIONAL',
                                                hintBelow:
                                                    'Assista em alta qualidade (até 4K quando o arquivo permitir).',
                                                heroAutoplay: true,
                                              ),
                                            ] else ...[
                                              const SizedBox(height: 28),
                                              Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.all(18),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x12000000),
                                                      blurRadius: 16,
                                                      offset: Offset(0, 8),
                                                    ),
                                                  ],
                                                  border: Border.all(
                                                      color: const Color(
                                                          0xFFE5E7EB)),
                                                ),
                                                child: Row(
                                                  children: [
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              10),
                                                      child: Image.asset(
                                                        'assets/LOGO_GESTAO_YAHWEH.png',
                                                        width: 54,
                                                        height: 54,
                                                        fit: BoxFit.contain,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: const [
                                                          Text(
                                                            'Bem-vindo ao site da igreja',
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                            ),
                                                          ),
                                                          SizedBox(height: 4),
                                                          Text(
                                                            'Conteúdo em destaque será publicado em breve.',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: Color(
                                                                  0xFF6B7280),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 24),
                                            FutureBuilder<
                                                _PublicSocialProofStats>(
                                              future:
                                                  _loadPublicSocialProofStats(
                                                      igrejaId),
                                              builder: (context, statsSnap) {
                                                final stats = statsSnap.data ??
                                                    const _PublicSocialProofStats(
                                                      activeMembers: 0,
                                                      monthPosts: 0,
                                                    );
                                                return Wrap(
                                                  spacing: 10,
                                                  runSpacing: 10,
                                                  children: [
                                                    _ProofChip(
                                                      icon: Icons
                                                          .groups_2_rounded,
                                                      text:
                                                          '${stats.activeMembers} membros ativos',
                                                    ),
                                                    _ProofChip(
                                                      icon: Icons
                                                          .campaign_rounded,
                                                      text:
                                                          '${stats.monthPosts} publicações no mês',
                                                    ),
                                                    const _ProofChip(
                                                      icon: Icons
                                                          .verified_rounded,
                                                      text:
                                                          'Comunidade online ativa',
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 16),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              sliver: _ChurchPublicMuralStreamSliver(
                                igrejaId: igrejaId,
                                slugClean: slugClean,
                                accent: accent,
                                sectionAvisosKey: sectionAvisosKey,
                                sectionDestaquesKey: sectionDestaquesKey,
                                onOpenHostedVideoFromMap:
                                    _churchPublicOpenNoticiaVideoFromMap,
                                onChurchPublicAction: logChurchPublic,
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                              sliver: SliverToBoxAdapter(
                                child: ChurchPublicFeedItemWidth(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const SizedBox(height: 16),
                                      KeyedSubtree(
                                        key: sectionEventosKey,
                                        child: _PublicEventosSection(
                                          igrejaId: igrejaId,
                                          churchSlug: slugClean,
                                          churchVenueAddress: endereco,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      _HorariosCultoSection(
                                        igrejaId: igrejaId,
                                        horariosIniciais: horariosFromIgreja,
                                      ),
                                      const SizedBox(height: 28),
                                      _SectionCard(
                                        title: 'Baixar aplicativo',
                                        icon: Icons.get_app_rounded,
                                        accentColor: const Color(0xFF6366F1),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Android: Play Store (botão Android). '
                                              'iPhone: siga o TestFlight — toque em Apple abaixo; depois instale Gestão Yahweh - Igrejas.',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade700,
                                                  height: 1.4),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              AppConstants
                                                  .marketingDownloadIosTestFlightHint,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                                height: 1.35,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            StreamBuilder<
                                                DocumentSnapshot<
                                                    Map<String, dynamic>>>(
                                              stream: FirebaseFirestore.instance
                                                  .doc('config/appDownloads')
                                                  .snapshots(),
                                              builder: (context, dlSnap) {
                                                final data =
                                                    dlSnap.data?.data() ?? {};
                                                final folderUrl =
                                                    (data['driveFolderUrl'] ??
                                                            '')
                                                        .toString();
                                                final androidEffective =
                                                    AppConstants
                                                        .effectiveAppDownloadsAndroidUrl(
                                                            data);
                                                final iosEffective = AppConstants
                                                    .effectiveAppDownloadsIosUrl(
                                                        data);

                                                return Wrap(
                                                  spacing: 10,
                                                  runSpacing: 10,
                                                  children: [
                                                    FilledButton.icon(
                                                      onPressed: () {
                                                        logChurchPublic(
                                                            'download_android');
                                                        _launchExternal(
                                                          context,
                                                          Uri.parse(
                                                              androidEffective),
                                                        );
                                                      },
                                                      icon: const Icon(
                                                          Icons.android),
                                                      label:
                                                          const Text('Android'),
                                                    ),
                                                    FilledButton.tonalIcon(
                                                      onPressed: iosEffective
                                                              .isEmpty
                                                          ? null
                                                          : () {
                                                              logChurchPublic(
                                                                  'download_ios');
                                                              _launchExternal(
                                                                context,
                                                                Uri.parse(
                                                                    iosEffective,
                                                                ),
                                                              );
                                                            },
                                                      icon: const Icon(
                                                          Icons.apple),
                                                      label: const Text(
                                                          'iPhone (TestFlight)'),
                                                    ),
                                                    OutlinedButton.icon(
                                                      onPressed: folderUrl
                                                              .isEmpty
                                                          ? null
                                                          : () {
                                                              logChurchPublic(
                                                                  'download_folder');
                                                              _launchExternal(
                                                                context,
                                                                Uri.parse(
                                                                    folderUrl),
                                                              );
                                                            },
                                                      icon: const Icon(
                                                          Icons.folder_open),
                                                      label: const Text(
                                                          'Pasta de downloads'),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 36),
                                      _PublicFooter(
                                        onAdquirirSistema: () {
                                          logChurchPublic(
                                              'footer_adquirir_sistema');
                                          Navigator.pushNamed(
                                              context, '/planos');
                                        },
                                        onDeveloperWhatsApp: () {
                                          logChurchPublic(
                                              'footer_dev_whatsapp');
                                          _launchExternal(
                                            context,
                                            Uri.parse(
                                              'https://wa.me/$kLegalSupportWhatsAppWaMe?text=${Uri.encodeComponent('Olá! Vim pelo site público da igreja (Gestão YAHWEH).')}',
                                            ),
                                          );
                                        },
                                        onDeveloperEmail: () {
                                          logChurchPublic(
                                              'footer_dev_email');
                                          _launchExternal(
                                            context,
                                            Uri.parse(
                                              'mailto:$kLegalSupportEmail?subject=${Uri.encodeComponent('Gestão YAHWEH — site público')}',
                                            ),
                                          );
                                        },
                                      ),
                                      // Espaço para não cobrir o rodapé com os FABs
                                      SizedBox(
                                          height: MediaQuery.paddingOf(context)
                                                  .bottom +
                                              96),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        ),
                        Positioned(
                          right: 12,
                          bottom: MediaQuery.paddingOf(context).bottom + 12,
                          child: YahwehPublicFloatingActions(
                            brandBlue: accent,
                            onLogin: () {
                              logChurchPublic('fab_bar_login');
                              Navigator.pushNamed(context, '/igreja/login');
                            },
                            onMaps: (latitude != null && longitude != null) ||
                                    endereco.trim().isNotEmpty ||
                                    linkGoogleMaps.isNotEmpty
                                ? () {
                                    logChurchPublic('fab_bar_maps');
                                    _launchExternal(
                                      context,
                                      linkGoogleMaps.isNotEmpty
                                          ? (Uri.tryParse(linkGoogleMaps) ??
                                              _mapsUri(endereco,
                                                  latitude: latitude,
                                                  longitude: longitude))
                                          : _mapsUri(endereco,
                                              latitude: latitude,
                                              longitude: longitude),
                                    );
                                  }
                                : null,
                            onPrayer: waPrayerUri == null
                                ? null
                                : () {
                                    logChurchPublic('fab_bar_prayer_whatsapp');
                                    _launchExternal(context, waPrayerUri);
                                  },
                          ),
                        ),
                        if (waLaunchUri != null)
                          Positioned(
                            right: 16,
                            bottom: MediaQuery.paddingOf(context).bottom + 84,
                            child: FloatingActionButton(
                              heroTag: 'public_whatsapp_fab',
                              backgroundColor: const Color(0xFF16A34A),
                              onPressed: () {
                                logChurchPublic('fab_whatsapp_chat');
                                _launchExternal(context, waLaunchUri);
                              },
                              child: const Icon(Icons.chat_rounded,
                                  color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            );
          },
        ),
      ),
    );
  }
}

/// Atualiza título / meta uma vez por montagem (web).
class _ChurchPublicSeoBinder extends StatefulWidget {
  final String title;
  final String description;
  final String? ogImageUrl;
  final String? canonicalUrl;

  const _ChurchPublicSeoBinder({
    super.key,
    required this.title,
    required this.description,
    this.ogImageUrl,
    this.canonicalUrl,
  });

  @override
  State<_ChurchPublicSeoBinder> createState() => _ChurchPublicSeoBinderState();
}

class _ChurchPublicSeoBinderState extends State<_ChurchPublicSeoBinder> {
  bool _didPrecacheLogo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) return;
      updateChurchPublicSeoWeb(
        title: widget.title,
        description: widget.description,
        ogImageUrl: widget.ogImageUrl,
        canonicalUrl: widget.canonicalUrl,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb || _didPrecacheLogo) return;
    final u = widget.ogImageUrl;
    if (u != null &&
        u.isNotEmpty &&
        (u.startsWith('http://') || u.startsWith('https://'))) {
      _didPrecacheLogo = true;
      // Igual ao feed: na web, URLs do Storage não usam NetworkImage (CORS/CanvasKit).
      unawaited(preloadNetworkImages(context, [u], maxItems: 1));
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Abre publicação quando a URL traz `openNoticiaId`.
class _PublicNoticiaDeepLinkOpener extends StatefulWidget {
  final String igrejaId;
  final String openNoticiaId;

  const _PublicNoticiaDeepLinkOpener({
    required this.igrejaId,
    required this.openNoticiaId,
  });

  @override
  State<_PublicNoticiaDeepLinkOpener> createState() =>
      _PublicNoticiaDeepLinkOpenerState();
}

class _PublicNoticiaDeepLinkOpenerState
    extends State<_PublicNoticiaDeepLinkOpener> {
  String? _handledKey;
  bool _inFlight = false;

  @override
  void didUpdateWidget(covariant _PublicNoticiaDeepLinkOpener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.igrejaId != widget.igrejaId ||
        oldWidget.openNoticiaId != widget.openNoticiaId) {
      _handledKey = null;
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = '${widget.igrejaId}|${widget.openNoticiaId}';
    if (_handledKey == key) return const SizedBox.shrink();
    if (!_inFlight) {
      _inFlight = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(key));
    }
    return const SizedBox.shrink();
  }

  Future<void> _open(String key) async {
    try {
      if (!mounted) return;
      var snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.igrejaId)
          .collection(ChurchTenantPostsCollections.avisos)
          .doc(widget.openNoticiaId)
          .get();
      if (!snap.exists) {
        snap = await FirebaseFirestore.instance
            .collection('igrejas')
            .doc(widget.igrejaId)
            .collection(ChurchTenantPostsCollections.noticias)
            .doc(widget.openNoticiaId)
            .get();
      }
      if (!mounted) return;
      if (!snap.exists) {
        _handledKey = key;
        return;
      }
      final p = snap.data() ?? {};
      final title = (p['title'] ?? 'Publicação').toString();
      final body = (p['body'] ?? p['text'] ?? '').toString();
      final cover = _churchPublicNoticiaCoverUrl(p);
      final u = sanitizeImageUrl(cover);
      if (!context.mounted) return;
      if (kIsWeb) {
        final desc = body.trim();
        final short = desc.length > 200 ? '${desc.substring(0, 197)}…' : desc;
        updateChurchPublicSeoWeb(
          title: title,
          description: short.isEmpty ? 'Publicação — Gestão YAHWEH.' : short,
          ogImageUrl: u.isNotEmpty && isValidImageUrl(u) ? u : null,
        );
      }
      _handledKey = key;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          initialChildSize: 0.72,
          minChildSize: 0.35,
          maxChildSize: 0.94,
          expand: false,
          builder: (_, scrollCtrl) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: ListView(
              controller: scrollCtrl,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                if (u.isNotEmpty && isValidImageUrl(u)) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: LayoutBuilder(
                      builder: (ctx, c) {
                        final w = c.maxWidth.isFinite && c.maxWidth > 0
                            ? c.maxWidth
                            : MediaQuery.sizeOf(ctx).width - 40;
                        final nPhotos = eventNoticiaPhotoUrls(p)
                            .where((x) =>
                                sanitizeImageUrl(x.toString()).isNotEmpty)
                            .length;
                        final ar = postFeedCarouselAspectRatioForIndex(
                          p,
                          0,
                          nPhotos > 0 ? nPhotos : 1,
                        );
                        final maxH = MediaQuery.sizeOf(ctx).height * 0.58;
                        final h = (w / ar).clamp(160.0, maxH);
                        return SizedBox(
                          width: w,
                          height: h,
                          child: ColoredBox(
                            color: const Color(0xFFF1F5F9),
                            child: FreshFirebaseStorageImage(
                              imageUrl: u,
                              fit: BoxFit.contain,
                              width: w,
                              height: h,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      _inFlight = false;
    }
  }
}

/* =========================
   UI pieces — Site público Super Premium
========================= */

const List<String> _weekdayNames = [
  'Seg',
  'Ter',
  'Qua',
  'Qui',
  'Sex',
  'Sáb',
  'Dom'
];

/// Nome completo (detalhe do evento no site público).
const List<String> _weekdayNamesLong = [
  'Segunda-feira',
  'Terça-feira',
  'Quarta-feira',
  'Quinta-feira',
  'Sexta-feira',
  'Sábado',
  'Domingo',
];

/// Barra superior fina: logo da igreja (ou Gestão YAHWEH) + Acessar (visual premium).
class _PublicTopBarSlim extends StatelessWidget {
  final String logoUrl;
  final String logoProcessedUrl;
  final VoidCallback onAcessar;

  const _PublicTopBarSlim({
    required this.logoUrl,
    required this.logoProcessedUrl,
    required this.onAcessar,
  });

  @override
  Widget build(BuildContext context) {
    final hasChurchLogo = (logoProcessedUrl.trim().isNotEmpty &&
            isValidImageUrl(sanitizeImageUrl(logoProcessedUrl))) ||
        (logoUrl.trim().isNotEmpty &&
            isValidImageUrl(sanitizeImageUrl(logoUrl)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(
            color: ThemeCleanPremium.primary.withOpacity(0.08), width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (hasChurchLogo)
            _Logo(logoUrl: logoUrl, processedUrl: logoProcessedUrl, size: 44)
          else
            Text(
              'Gestão YAHWEH',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: ThemeCleanPremium.primary,
                letterSpacing: -0.3,
              ),
            ),
          _PublicPremiumActionButton(
            label: 'Acessar sistema',
            icon: Icons.login_rounded,
            onPressed: onAcessar,
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

/// Card de seção com título e ícone (horários, mural, app). [accentColor] deixa a seção mais viva.
class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color? accentColor;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? ThemeCleanPremium.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(color: color.withOpacity(0.12), width: 1),
        boxShadow: [
          ...ThemeCleanPremium.softUiCardShadow,
          BoxShadow(
              color: color.withOpacity(0.05),
              blurRadius: 24,
              offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 22, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color),
              ),
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

/// Faixa compacta estilo feed (título + data do evento + chip).
class _PublicFeedTitleStrip extends StatelessWidget {
  final bool isEvento;
  final String title;
  final String eventDateStr;
  final String createdWhen;
  final VoidCallback? onShare;

  const _PublicFeedTitleStrip({
    required this.isEvento,
    required this.title,
    required this.eventDateStr,
    required this.createdWhen,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final hasTitleOrDate = title.isNotEmpty || eventDateStr.isNotEmpty;
    if (!hasTitleOrDate && createdWhen.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!hasTitleOrDate) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isEvento
                    ? const Color(0xFFFFF7ED)
                    : const Color(0xFFF5F3FF)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isEvento ? 'Evento' : 'Aviso',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isEvento
                      ? const Color(0xFFC2410C)
                      : const Color(0xFF6D28D9),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const Spacer(),
            if (onShare != null)
              IconButton(
                tooltip: 'Compartilhar',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: ThemeCleanPremium.minTouchTarget,
                  minHeight: ThemeCleanPremium.minTouchTarget,
                ),
                icon: Icon(Icons.share_rounded,
                    size: 20, color: Colors.grey.shade600),
                onPressed: onShare,
              ),
            Text(createdWhen,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x06000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isEvento
                        ? const Color(0xFFFFF7ED)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isEvento ? 'Evento' : 'Aviso',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: isEvento
                          ? const Color(0xFFC2410C)
                          : const Color(0xFF2563EB),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const Spacer(),
                if (onShare != null)
                  IconButton(
                    tooltip: 'Compartilhar',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: ThemeCleanPremium.minTouchTarget,
                      minHeight: ThemeCleanPremium.minTouchTarget,
                    ),
                    icon: Icon(Icons.ios_share_rounded,
                        size: 22, color: Colors.grey.shade600),
                    onPressed: onShare,
                  ),
                if (createdWhen.isNotEmpty)
                  Text(
                    createdWhen,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w600),
                  ),
              ],
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
            ],
            if (eventDateStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.event_rounded,
                      size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      eventDateStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Horários de culto: usa texto do doc ou do tenant; se vazio, resumo semanal a partir dos eventos fixos ([event_templates]).
class _HorariosCultoSection extends StatelessWidget {
  final String igrejaId;
  final String horariosIniciais;

  const _HorariosCultoSection(
      {required this.igrejaId, required this.horariosIniciais});

  @override
  Widget build(BuildContext context) {
    if (horariosIniciais.isNotEmpty) {
      return _SectionCard(
        title: 'Horários de culto',
        icon: Icons.schedule_rounded,
        accentColor: const Color(0xFF059669),
        child: Text(
          horariosIniciais,
          style:
              TextStyle(fontSize: 15, height: 1.6, color: Colors.grey.shade800),
        ),
      );
    }
    return _SectionCard(
      title: 'Horários de culto',
      icon: Icons.schedule_rounded,
      accentColor: const Color(0xFF059669),
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance
            .collection('igrejas')
            .doc(igrejaId)
            .get(),
        builder: (context, tenantSnap) {
          final tenantHorarios = (tenantSnap.data?.data()?['horariosCulto'] ??
                  tenantSnap.data?.data()?['horarios'] ??
                  '')
              .toString()
              .trim();
          if (tenantHorarios.isNotEmpty) {
            return Text(tenantHorarios,
                style: TextStyle(
                    fontSize: 15, height: 1.6, color: Colors.grey.shade800));
          }
          return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: FirebaseFirestore.instance
                .collection('igrejas')
                .doc(igrejaId)
                .collection('event_templates')
                .where('active', isEqualTo: true)
                .get(),
            builder: (context, tplSnap) {
              final docs = tplSnap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Text(
                  'Informe os horários no painel da igreja (Cadastro da Igreja ou Eventos fixos).',
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: Colors.grey.shade700),
                );
              }
              final weekly = <({int weekday, String title, String timeStr})>[];
              for (final d in docs) {
                final m = d.data();
                final title = (m['title'] ?? 'Culto').toString().trim();
                if (title.isEmpty) continue;
                final wd =
                    (m['weekday'] is int) ? (m['weekday'] as int).clamp(1, 7) : 7;
                final timeRaw = (m['time'] ?? '19:30').toString();
                final tp = timeRaw.split(':');
                final hh = int.tryParse(tp.isNotEmpty ? tp[0] : '') ?? 19;
                final mm = int.tryParse(tp.length > 1 ? tp[1] : '') ?? 30;
                final timeStr =
                    '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
                weekly.add((weekday: wd, title: title, timeStr: timeStr));
              }
              weekly.sort((a, b) {
                final c = a.weekday.compareTo(b.weekday);
                if (c != 0) return c;
                final ct = a.timeStr.compareTo(b.timeStr);
                if (ct != 0) return ct;
                return a.title.compareTo(b.title);
              });
              if (weekly.isEmpty) {
                return Text(
                  'Não foi possível montar o resumo. Verifique os eventos fixos.',
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: Colors.grey.shade700),
                );
              }
              return _HorariosCultoGrid(rows: weekly);
            },
          );
        },
      ),
    );
  }
}

/// Resumo semanal a partir de [event_templates]: dia da semana → programação → hora (sem listar datas).
class _HorariosCultoGrid extends StatelessWidget {
  final List<({int weekday, String title, String timeStr})> rows;

  const _HorariosCultoGrid({required this.rows});

  static String _cap(String s) {
    if (s.isEmpty) return s;
    return '${s[0].toUpperCase()}${s.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF059669);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Table(
          border: TableBorder.symmetric(
            inside: BorderSide(color: Colors.grey.shade200),
          ),
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(1.45),
            2: FlexColumnWidth(0.7),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
              ),
              children: [
                _horCell('Dia', header: true, accent: accent),
                _horCell('Programação', header: true, accent: accent),
                _horCell('Hora', header: true, accent: accent),
              ],
            ),
            for (final r in rows)
              TableRow(
                children: [
                  _horCell(
                    _cap(weekdayLongNameFromIsoWeekday(r.weekday)),
                    accent: accent,
                  ),
                  _horCell(r.title, accent: accent),
                  _horCell(r.timeStr, accent: accent),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _horCell(String text, {required Color accent, bool header = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: header ? 10 : 10,
        vertical: header ? 11 : 12,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: header ? FontWeight.w900 : FontWeight.w600,
          fontSize: header ? 11.5 : 13.5,
          height: 1.25,
          color: header ? accent : const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

/// Programação pública com filtros (+7, +15 e +30 dias) e detalhe clicável.
class _PublicEventosSection extends StatefulWidget {
  final String igrejaId;
  final String churchSlug;
  /// Endereço formatado do cadastro — para não repetir em cada card quando for o mesmo local.
  final String churchVenueAddress;

  const _PublicEventosSection({
    required this.igrejaId,
    this.churchSlug = '',
    this.churchVenueAddress = '',
  });

  @override
  State<_PublicEventosSection> createState() => _PublicEventosSectionState();
}

class _PublicEventosSectionState extends State<_PublicEventosSection> {
  int _selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    const accentEvento = Color(0xFF2563EB);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadPublicProgramacao(widget.igrejaId, _selectedDays),
      builder: (context, fixSnap) {
        final fixos = fixSnap.data ?? [];
        if (fixos.isEmpty) {
          return const SizedBox.shrink();
        }
        final preloadUrls = fixos
            .map((m) => (m['imageUrl'] ?? '').toString().trim())
            .where((u) => u.isNotEmpty)
            .take(12)
            .toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          preloadNetworkImages(context, preloadUrls, maxItems: 8);
        });
        return ChurchPublicPremiumSection(
          kicker: 'Programação',
          title: 'Agenda de cultos e reuniões',
          subtitle:
              'Capas com tratamento editorial, data e horário em pastilhas — toque no cartão para ver detalhes e local.',
          icon: Icons.event_repeat_rounded,
          accentColor: accentEvento,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [7, 15, 30].map((d) {
                  final selected = d == _selectedDays;
                  return FilterChip(
                    label: Text('$d dias'),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedDays = d),
                    showCheckmark: false,
                    selectedColor: accentEvento.withValues(alpha: 0.2),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: selected
                          ? accentEvento
                          : const Color(0xFFE2E8F0),
                      width: selected ? 1.5 : 1,
                    ),
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color:
                          selected ? accentEvento : Colors.grey.shade700,
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 2),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              ...fixos.map((m) {
                final title = (m['title'] ?? '').toString();
                final loc = (m['location'] ?? '').toString().trim();
                final locFallback = widget.churchVenueAddress.trim();
                final locFinal = loc.isNotEmpty ? loc : locFallback;
                final body = (m['text'] ?? '').toString().trim();
                final imageUrl = (m['imageUrl'] ?? '').toString().trim();
                final videoUrl = (m['videoUrl'] ?? '').toString().trim();
                final photoPath =
                    (m['photoStoragePath'] ?? '').toString().trim();
                final itemId = (m['id'] ?? '').toString().trim();
                DateTime? dt = m['startAt'] is Timestamp
                    ? (m['startAt'] as Timestamp).toDate()
                    : null;
                final dayName = dt != null ? _weekdayNames[dt.weekday - 1] : '';
                final dayNameLong = dt != null && dt.weekday >= 1 && dt.weekday <= 7
                    ? _weekdayNamesLong[dt.weekday - 1]
                    : '';
                final time = dt != null
                    ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
                    : '';
                final dateStr = dt != null ? formatPublicDatePt(dt) : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ChurchPublicPremiumScheduleEventCard(
                    title: title,
                    weekdayLabel: dayName,
                    weekdayLongLabel: dayNameLong,
                    dateShort: dateStr,
                    timeLabel: time,
                    location: locFinal,
                    churchDefaultAddress: widget.churchVenueAddress,
                    imageUrl: imageUrl,
                    accent: accentEvento,
                    onTap: () {
                      final hasSchedule = dayName.isNotEmpty ||
                          dateStr.isNotEmpty ||
                          time.isNotEmpty ||
                          loc.isNotEmpty;
                      showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => ChurchPublicEventDetailSheet(
                          title: title,
                          subtitle: hasSchedule ? '' : '—',
                          weekdayLabel:
                              dayNameLong.isEmpty ? null : dayNameLong,
                          dateLabel: dateStr.isEmpty ? null : dateStr,
                          timeLabel: time.isEmpty ? null : time,
                          locationLine: locFinal.isEmpty ? null : locFinal,
                          body: body,
                          imageUrl: imageUrl,
                          videoUrl: videoUrl,
                          photoStoragePath:
                              photoPath.isNotEmpty ? photoPath : null,
                          accentColor: accentEvento,
                          mapsUrl: locFinal.isEmpty
                              ? null
                              : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(locFinal)}',
                          shareText: (() {
                            final when =
                                dt != null ? DateFormat('dd/MM/yyyy').format(dt) : '';
                            final base = StringBuffer()
                              ..write(title.trim().isEmpty
                                  ? 'Programação da igreja'
                                  : title.trim());
                            if (when.isNotEmpty) base.write('\nData: $when');
                            if (time.isNotEmpty) base.write('\nHora: $time');
                            if (locFinal.isNotEmpty) base.write('\nLocal: $locFinal');
                            final isRealPost =
                                itemId.isNotEmpty && !itemId.startsWith('virt_');
                            if (isRealPost && widget.churchSlug.trim().isNotEmpty) {
                              final link = AppConstants.shareNoticiaSocialPreviewUrl(
                                widget.churchSlug.trim(),
                                itemId,
                                widget.igrejaId,
                              );
                              base.write('\n\nMais detalhes: $link');
                            }
                            return base.toString();
                          })(),
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

/// Capa do evento fixo (Eventos fixos no painel): `defaultImageUrl` / `imageUrl` / lista.
String _publicEventTemplateCoverUrl(Map<String, dynamic> m) {
  var u = (m['defaultImageUrl'] ?? m['imageUrl'] ?? '').toString().trim();
  if (u.isEmpty && m['imageUrls'] is List) {
    for (final e in m['imageUrls'] as List) {
      u = e.toString().trim();
      if (u.isNotEmpty) break;
    }
  }
  if (u.isEmpty) return '';
  return sanitizeImageUrl(u);
}

Future<List<Map<String, dynamic>>> _loadPublicProgramacao(
    String igrejaId, int days) async {
  try {
    final now = DateTime.now();
    final end = now.add(Duration(days: days));
    final noticiasRef = FirebaseFirestore.instance
        .collection('igrejas')
        .doc(igrejaId)
        .collection('noticias');
    final eventosSnap = await noticiasRef
        .where('type', isEqualTo: 'evento')
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('startAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('startAt')
        .limit(60)
        .get();
    final itens = <Map<String, dynamic>>[];
    final seenTplDay = <String>{};
    for (final d in eventosSnap.docs) {
      final data = d.data();
      final photos = eventNoticiaPhotoUrls(data);
      final videos = eventNoticiaVideosFromDoc(data);
      final path0 = eventNoticiaPhotoStoragePathAt(data, 0);
      final title = (data['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final sa = data['startAt'];
      if (sa is Timestamp) {
        final dk = DateFormat('yyyy-MM-dd').format(sa.toDate());
        final tpl = (data['templateId'] ?? '').toString();
        if (tpl.isNotEmpty) {
          seenTplDay.add('${tpl}_$dk');
        }
      }
      itens.add(<String, dynamic>{
        'id': d.id,
        'title': title,
        'text': (data['text'] ?? '').toString().trim(),
        'location': (data['location'] ?? '').toString().trim(),
        'startAt': data['startAt'],
        'imageUrl': photos.isNotEmpty ? sanitizeImageUrl(photos.first) : '',
        'videoUrl': videos.isNotEmpty ? videos.first : '',
        'photoStoragePath': path0 != null && path0.isNotEmpty ? path0 : '',
      });
    }
    final tplSnap = await FirebaseFirestore.instance
        .collection('igrejas')
        .doc(igrejaId)
        .collection('event_templates')
        .where('active', isEqualTo: true)
        .get();
    for (final d in tplSnap.docs) {
      final m = d.data();
      if (!eventTemplateIncludeInAgenda(m)) continue;
      final title = (m['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      final wd = (m['weekday'] is int) ? (m['weekday'] as int).clamp(1, 7) : 7;
      final time = (m['time'] ?? '19:30').toString();
      final rec = (m['recurrence'] ?? 'weekly').toString();
      final dates = expandTemplateOccurrencesInRange(
        weekday: wd,
        timeHHmm: time,
        recurrence: rec,
        rangeStart: now,
        rangeEnd: end,
      );
      for (final dt in dates) {
        final dk = '${d.id}_${DateFormat('yyyy-MM-dd').format(dt)}';
        if (seenTplDay.contains(dk)) continue;
        seenTplDay.add(dk);
        final img = _publicEventTemplateCoverUrl(m);
        itens.add(<String, dynamic>{
          'id': 'virt_${d.id}_${DateFormat('yyyy-MM-dd').format(dt)}',
          'title': title,
          'text': (m['description'] ?? '').toString(),
          'location': (m['location'] ?? '').toString().trim(),
          'startAt': Timestamp.fromDate(dt),
          'imageUrl': img,
          'videoUrl': '',
          'photoStoragePath': '',
        });
      }
    }
    itens.sort((a, b) {
      final ta = a['startAt'];
      final tb = b['startAt'];
      if (ta is! Timestamp || tb is! Timestamp) return 0;
      return ta.compareTo(tb);
    });
    return itens;
  } catch (_) {
    return [];
  }
}

/// Topo: logo, nome completo, telefone, endereço, localização + menu Contato, WhatsApp, E-mail.
class _PublicTopBar extends StatelessWidget {
  final String nome;
  final String slugClean;
  final String logoUrl;
  final String logoProcessedUrl;
  final String telefone;
  final String endereco;
  final double? latitude;
  final double? longitude;
  final String email;
  final VoidCallback onMaps;
  final VoidCallback onWhatsApp;
  final VoidCallback onLogin;
  final VoidCallback onMemberSignup;

  const _PublicTopBar({
    required this.nome,
    required this.slugClean,
    required this.logoUrl,
    required this.logoProcessedUrl,
    required this.telefone,
    required this.endereco,
    this.latitude,
    this.longitude,
    required this.email,
    required this.onMaps,
    required this.onWhatsApp,
    required this.onLogin,
    required this.onMemberSignup,
  });

  @override
  Widget build(BuildContext context) {
    final logoFinal =
        (logoProcessedUrl.isNotEmpty ? logoProcessedUrl : logoUrl).trim();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Logo(logoUrl: logoUrl, processedUrl: logoProcessedUrl),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1a1a2e),
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (telefone.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined,
                              size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          SelectableText(telefone,
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade700)),
                        ],
                      ),
                    ],
                    if (endereco.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 18, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                              child: SelectableText(endereco,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (endereco.isNotEmpty)
                _PublicPremiumActionButton(
                  label: 'Localização',
                  icon: Icons.map_outlined,
                  onPressed: onMaps,
                ),
              _PublicPremiumActionButton(
                label: 'Cadastro de membro',
                icon: Icons.person_add_rounded,
                onPressed: onMemberSignup,
              ),
              _PublicPremiumActionButton(
                label: 'Acessar Sistema',
                icon: Icons.login_rounded,
                onPressed: onLogin,
                emphasize: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              if (telefone.isNotEmpty)
                _PublicPremiumActionButton(
                  label: 'WhatsApp',
                  icon: Icons.chat_rounded,
                  onPressed: onWhatsApp,
                ),
              if (email.isNotEmpty)
                _PublicPremiumActionButton(
                  label: 'E-mail',
                  icon: Icons.email_outlined,
                  onPressed: () async {
                    final uri = Uri.parse('mailto:${email.trim()}');
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip de contato (WhatsApp / e-mail) — vidro suave + sombra premium.
class _PublicFooterContactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final Color border;
  final Color iconColor;
  final VoidCallback onTap;

  const _PublicFooterContactChip({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.border,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = ThemeCleanPremium.radiusLg;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            border: Border.all(color: border, width: 1.15),
            boxShadow: [
              BoxShadow(
                color: iconColor.withValues(alpha: 0.14),
                blurRadius: 22,
                offset: const Offset(0, 9),
                spreadRadius: -1,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: -0.3,
                      color: const Color(0xFF0F172A),
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
}

class _PublicFooterPrimaryCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PublicFooterPrimaryCta({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = ThemeCleanPremium.radiusLg;
    final deep =
        Color.lerp(ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.3)!;
    final hi = Color.lerp(ThemeCleanPremium.primary, Colors.white, 0.12)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 1.1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(hi, Colors.white, 0.08)!,
                hi,
                deep,
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.34),
                blurRadius: 32,
                offset: const Offset(0, 14),
                spreadRadius: -3,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ThemeCleanPremium.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      letterSpacing: -0.4,
                      color: Colors.white,
                      height: 1.1,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
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
  }
}

class _PublicFooterOutlineCta extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color foreground;
  final VoidCallback onTap;

  const _PublicFooterOutlineCta({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = ThemeCleanPremium.radiusLg;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                const Color(0xFFF8FAFC),
                ThemeCleanPremium.primaryLight.withValues(alpha: 0.35),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.26),
              width: 1.15,
            ),
            boxShadow: [
              ...ThemeCleanPremium.softUiCardShadow,
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: ThemeCleanPremium.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 21, color: ThemeCleanPremium.primary),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      letterSpacing: -0.35,
                      color: foreground,
                      height: 1.1,
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

/// Rodapé do site público da igreja: marca Gestão YAHWEH, desenvolvedor e links legais.
class _PublicFooter extends StatelessWidget {
  final VoidCallback onAdquirirSistema;
  final VoidCallback onDeveloperWhatsApp;
  final VoidCallback onDeveloperEmail;

  const _PublicFooter({
    required this.onAdquirirSistema,
    required this.onDeveloperWhatsApp,
    required this.onDeveloperEmail,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 520;
    final deep = const Color(0xFF0F172A);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: 28,
        horizontal: isNarrow ? 16 : 24,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFFF8FAFC),
            Color.lerp(
                  ThemeCleanPremium.primary,
                  Colors.white,
                  0.92,
                ) ??
                const Color(0xFFEFF6FF),
            Colors.white,
          ],
        ),
        border: Border.all(
          color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
          ...ThemeCleanPremium.softUiCardShadow,
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Gestão YAHWEH',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: ThemeCleanPremium.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Plataforma para a sua igreja',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Desenvolvedor: $kDeveloperPublicName',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: deep,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              _PublicFooterContactChip(
                icon: Icons.chat_rounded,
                label: kLegalSupportWhatsAppDisplay,
                gradient: const [
                  Color(0xFFECFDF5),
                  Color(0xFFD1FAE5),
                ],
                border: const Color(0xFF6EE7B7),
                iconColor: const Color(0xFF047857),
                onTap: onDeveloperWhatsApp,
              ),
              _PublicFooterContactChip(
                icon: Icons.email_outlined,
                label: kLegalSupportEmail,
                gradient: [
                  Colors.white,
                  ThemeCleanPremium.primaryLight.withValues(alpha: 0.35),
                ],
                border: ThemeCleanPremium.primary.withValues(alpha: 0.28),
                iconColor: ThemeCleanPremium.primary,
                onTap: onDeveloperEmail,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.45,
                  color: Colors.grey.shade700,
                ),
                children: [
                  TextSpan(
                    text: '"$kVersiculoRodape" ',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  TextSpan(
                    text: '— $kVersiculoRef',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ThemeCleanPremium.primary,
                      fontStyle: FontStyle.normal,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              _PublicFooterPrimaryCta(
                label: 'Adquirir sistema',
                icon: Icons.shopping_bag_outlined,
                onTap: onAdquirirSistema,
              ),
              _PublicFooterOutlineCta(
                label: 'Desenvolvedor $kDeveloperPublicName',
                icon: Icons.code_rounded,
                foreground: deep,
                onTap: onDeveloperWhatsApp,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () => unawaited(showGestaoYahwehLegalPreview(
                  context,
                  isPoliticaPrivacidade: false,
                )),
                child: const Text('Termos de uso'),
              ),
              Text(
                '·',
                style: TextStyle(color: Colors.grey.shade400),
              ),
              TextButton(
                onPressed: () => unawaited(showGestaoYahwehLegalPreview(
                  context,
                  isPoliticaPrivacidade: true,
                )),
                child: const Text('Privacidade'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            appVersionLabel.isNotEmpty ? appVersionLabel : 'v$appVersion',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final String nome;
  final String slug;
  final bool ativa;
  final String doc;
  final String logoUrl;
  final String logoProcessedUrl;
  final VoidCallback onLogin;
  final VoidCallback onCadastro;
  final VoidCallback onMemberSignup;
  final VoidCallback onAdmin;

  const _HeroCard({
    required this.nome,
    required this.slug,
    required this.ativa,
    required this.doc,
    required this.logoUrl,
    required this.logoProcessedUrl,
    required this.onLogin,
    required this.onCadastro,
    required this.onMemberSignup,
    required this.onAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Logo(logoUrl: logoUrl, processedUrl: logoProcessedUrl),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        nome,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900),
                      ),
                      _Pill(
                        text: ativa ? 'ATIVA' : 'INATIVA',
                        color: ativa ? Colors.green : Colors.red,
                      ),
                      _Pill(text: 'slug: $slug', color: Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    doc.isEmpty
                        ? 'Documento: (nao informado)'
                        : 'Documento: $doc',
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: onLogin,
                        icon: const Icon(Icons.login),
                        label: const Text('Acessar Sistema'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: onMemberSignup,
                        icon: const Icon(Icons.app_registration),
                        label: const Text('Cadastro de membro'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onCadastro,
                        icon: const Icon(Icons.app_registration),
                        label: const Text('Cadastrar igreja'),
                      ),
                      TextButton(
                        onPressed: onAdmin,
                        child: const Text('Sou administrador'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo legada (telas admin / cartões): prioriza [ChurchPublicSiteLogoBadge] com tenantId.
class _Logo extends StatelessWidget {
  final String logoUrl;
  final String? processedUrl;
  final Map<String, dynamic>? churchData;
  final String? tenantId;
  final double size;

  const _Logo({
    required this.logoUrl,
    this.processedUrl,
    this.churchData,
    this.tenantId,
    this.size = 72,
  });

  static String? _effectiveTenantId(String? t, Map<String, dynamic>? m) {
    final x = t?.trim();
    if (x != null && x.isNotEmpty) return x;
    if (m == null) return null;
    for (final k in ['id', 'tenantId', 'igrejaId', 'churchId']) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  static String? _mergedHttpsFromChurch(
    Map<String, dynamic> m,
    String processed,
    String fallbackUrl,
  ) {
    if (processed.isNotEmpty) {
      final sp = sanitizeImageUrl(processed);
      if (isValidImageUrl(sp)) return sp;
    }
    if (fallbackUrl.trim().isNotEmpty) {
      final sf = sanitizeImageUrl(fallbackUrl);
      if (isValidImageUrl(sf)) return sf;
    }
    final ct = churchTenantLogoUrl(m);
    if (ct.isNotEmpty) {
      final sc = sanitizeImageUrl(ct);
      if (isValidImageUrl(sc)) return sc;
    }
    return null;
  }

  Widget _yahwehAsset(double s) {
    return Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFFF7F8FA),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: EdgeInsets.all(s * 0.16),
        child:
            Image.asset('assets/LOGO_GESTAO_YAHWEH.png', fit: BoxFit.contain),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = size;
    final md = churchData;
    final tid = _effectiveTenantId(tenantId, md);
    final y = _yahwehAsset(s);

    if (tid != null && tid.isNotEmpty) {
      return ChurchPublicSiteLogoBadge(
        tenantId: tid,
        churchData: md,
        size: s,
        borderRadius: 20,
        logoFit: BoxFit.contain,
      );
    }

    if (md != null) {
      final sp = ChurchImageFields.logoStoragePath(md);
      final merged = _mergedHttpsFromChurch(
        md,
        (processedUrl ?? '').trim(),
        logoUrl,
      );
      if ((sp != null && sp.isNotEmpty) ||
          (merged != null && merged.isNotEmpty)) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cache = memCacheExtentForLogicalSize(s, dpr, maxPx: 1024);
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: StableStorageImage(
            storagePath: sp,
            imageUrl: merged,
            width: s,
            height: s,
            fit: BoxFit.contain,
            memCacheWidth: cache,
            memCacheHeight: cache,
            placeholder: ColoredBox(
              color: const Color(0xFFF7F8FA),
              child: YahwehPremiumFeedShimmer.logo(s),
            ),
            errorWidget: y,
          ),
        );
      }
    }

    for (final raw in [(processedUrl ?? '').trim(), logoUrl.trim()]) {
      final u = sanitizeImageUrl(raw);
      if (u.isNotEmpty && isValidImageUrl(u)) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cache = memCacheExtentForLogicalSize(s, dpr, maxPx: 1024);
        return ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SafeNetworkImage(
            imageUrl: u,
            width: s,
            height: s,
            fit: BoxFit.contain,
            memCacheWidth: cache,
            memCacheHeight: cache,
            placeholder: YahwehPremiumFeedShimmer.logo(s),
            errorWidget: y,
            skipFreshDisplayUrl: false,
          ),
        );
      }
    }
    return y;
  }
}

class _PublicPremiumActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasize;

  const _PublicPremiumActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = ThemeCleanPremium.radiusLg;
    final tap = onPressed;
    if (emphasize) {
      final deep =
          Color.lerp(ThemeCleanPremium.primary, const Color(0xFF0F172A), 0.32)!;
      final top = Color.lerp(ThemeCleanPremium.primary, Colors.white, 0.14)!;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: tap,
          borderRadius: BorderRadius.circular(r),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 1.1,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(top, Colors.white, 0.1)!,
                  top,
                  deep,
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.38),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                  spreadRadius: -3,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.09),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 48,
                minHeight: ThemeCleanPremium.minTouchTarget,
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: -0.38,
                        color: Colors.white,
                        height: 1.15,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
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
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(r),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(r),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                const Color(0xFFF8FAFC),
                ThemeCleanPremium.primaryLight.withValues(alpha: 0.28),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
            border: Border.all(
              color: ThemeCleanPremium.primary.withValues(alpha: 0.14),
              width: 1.1,
            ),
            boxShadow: [
              ...ThemeCleanPremium.softUiCardShadow,
              BoxShadow(
                color: ThemeCleanPremium.primary.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 48,
              minHeight: ThemeCleanPremium.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 19, color: const Color(0xFF1E3A5F)),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      letterSpacing: -0.2,
                      color: const Color(0xFF1E293B),
                      height: 1.2,
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

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String body;
  final Widget? trailing;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.body,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(body, style: const TextStyle(height: 1.3)),
              if (trailing != null) ...[
                const SizedBox(height: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Quando igrejas não tem o slug, tenta buscar em tenants e exibe a página completa (eventos, horários, mural).
class _ChurchTenantFallback extends StatelessWidget {
  final String slugClean;
  final String prettyName;

  const _ChurchTenantFallback(
      {required this.slugClean, required this.prettyName});

  Future<DocumentSnapshot<Map<String, dynamic>>?> _loadTenant() async {
    final db = FirebaseFirestore.instance;
    var q = await db
        .collection('igrejas')
        .where('slug', isEqualTo: slugClean)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) return q.docs.first;
    final doc = await db.collection('igrejas').doc(slugClean).get();
    return doc.exists ? doc : null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
      future: _loadTenant(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final tenantDoc = snap.data;
        if (tenantDoc == null || !tenantDoc.exists) {
          return _NotFound(slug: slugClean, prettyName: prettyName);
        }
        final data = tenantDoc.data() ?? {};
        final igrejaId = tenantDoc.id;
        void logChurchPublicLocal(String action) {
          unawaited(PublicSiteAnalytics.logChurchPublicAction(
            action,
            slug: slugClean,
            tenantId: igrejaId,
          ));
        }

        Future<void> launchExternalLocal(BuildContext ctx, Uri uri) async {
          try {
            final ok = await openExternalApplicationUrl(uri);
            if (!ok && ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(
                    content: Text('Não foi possível abrir: ${uri.toString()}')),
              );
            }
          } catch (e) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('Erro ao abrir link: $e')),
              );
            }
          }
        }

        final nome = (data['name'] ?? data['nome'] ?? prettyName).toString();
        final gestorEmail =
            (data['gestorEmail'] ?? data['gestor_email'] ?? data['email'] ?? '')
                .toString()
                .trim();
        final gestorTelefone =
            (data['gestorTelefone'] ?? data['gestor_telefone'] ?? '')
                .toString()
                .trim();
        final endereco = churchPublicFormattedAddress(data);
        final lat = data['latitude'];
        final lng = data['longitude'];
        final latitude = lat is num
            ? lat.toDouble()
            : (lat != null ? double.tryParse(lat.toString()) : null);
        final longitude = lng is num
            ? lng.toDouble()
            : (lng != null ? double.tryParse(lng.toString()) : null);
        final horariosFromIgreja =
            (data['horariosCulto'] ?? data['horarios'] ?? '').toString().trim();
        final linkGoogleMapsFb =
            (data['linkGoogleMaps'] ?? data['googleMapsLink'] ?? '')
                .toString()
                .trim();
        final whatsappIgrejaLinha = (data['whatsappIgreja'] ??
                data['whatsapp_igreja'] ??
                data['whatsapp'] ??
                data['telefoneIgreja'] ??
                data['telefone'] ??
                data['phone'] ??
                '')
            .toString()
            .trim();
        final whatsappContatoFallback = whatsappIgrejaLinha.isNotEmpty
            ? whatsappIgrejaLinha
            : gestorTelefone;
        final waLaunchUri = churchPublicWhatsappLaunchUri(
          data,
          fallbackPhoneRaw: whatsappContatoFallback,
          churchName: nome,
        );
        final instagramUriFb = churchPublicSocialHttpUri(data, const [
          'instagramUrl',
          'instagram',
          'linkInstagram',
          'instagram_link',
        ]);
        final youtubeUriFb = churchPublicSocialHttpUri(data, const [
          'youtubeUrl',
          'youtube',
          'linkYoutube',
          'youtube_link',
        ]);
        final facebookUriFb = churchPublicSocialHttpUri(data, const [
          'facebookUrl',
          'facebook',
          'linkFacebook',
          'facebook_link',
        ]);
        final accentFb = _churchAccentFromData(data);

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          key: ValueKey(igrejaId),
          children: [
            ChurchPublicWelcomeStrip(
              churchName: nome,
              accentColor: accentFb,
            ),
            const SizedBox(height: 8),
            ChurchPublicContactBar(
              accentColor: accentFb,
              phoneLine: churchPublicFormattedPhone(data),
              addressLine: endereco,
              onWhatsApp: waLaunchUri == null
                  ? null
                  : () => launchExternalLocal(context, waLaunchUri),
              onMaps: (linkGoogleMapsFb.isNotEmpty ||
                      (latitude != null && longitude != null) ||
                      endereco.trim().isNotEmpty)
                  ? () async {
                      final u = linkGoogleMapsFb.isNotEmpty
                          ? (Uri.tryParse(linkGoogleMapsFb) ??
                              Uri.parse(
                                'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}',
                              ))
                          : (latitude != null && longitude != null)
                              ? Uri.parse(
                                  'https://www.google.com/maps?q=$latitude,$longitude',
                                )
                              : Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}',
                                );
                      try {
                        await launchUrl(u,
                            mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    }
                  : null,
              onEmail: gestorEmail.isEmpty
                  ? null
                  : () async {
                      try {
                        await launchUrl(
                          Uri.parse('mailto:${gestorEmail.trim()}'),
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {}
                    },
              onInstagram: instagramUriFb == null
                  ? null
                  : () {
                      logChurchPublicLocal('contact_bar_instagram');
                      launchExternalLocal(context, instagramUriFb);
                    },
              onYoutube: youtubeUriFb == null
                  ? null
                  : () {
                      logChurchPublicLocal('contact_bar_youtube');
                      launchExternalLocal(context, youtubeUriFb);
                    },
              onFacebook: facebookUriFb == null
                  ? null
                  : () {
                      logChurchPublicLocal('contact_bar_facebook');
                      launchExternalLocal(context, facebookUriFb);
                    },
            ),
            const SizedBox(height: 16),
            ChurchPublicSiteHero(
              accentColor: accentFb,
              onMemberSignup: () =>
                  Navigator.pushNamed(context, '/$slugClean/cadastro-membro'),
              onMemberLogin: () =>
                  Navigator.pushNamed(context, '/igreja/login'),
              onTalkChurch: waLaunchUri == null
                  ? null
                  : () => launchExternalLocal(context, waLaunchUri),
              onOpenMaps: (latitude != null && longitude != null) ||
                      endereco.trim().isNotEmpty
                  ? () async {
                      final u = latitude != null && longitude != null
                          ? Uri.parse(
                              'https://www.google.com/maps?q=$latitude,$longitude',
                            )
                          : Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(endereco)}',
                            );
                      try {
                        await launchUrl(u, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            ChurchPublicProximoCultoCard(
              igrejaId: igrejaId,
              churchName: nome,
              churchSlug: slugClean,
              accentColor: accentFb,
              enderecoIgreja: endereco,
              latitude: latitude,
              longitude: longitude,
              linkGoogleMaps: linkGoogleMapsFb,
              horariosText: horariosFromIgreja,
            ),
            const SizedBox(height: 24),
            _HorariosCultoSection(
                igrejaId: igrejaId, horariosIniciais: horariosFromIgreja),
            const SizedBox(height: 24),
            _SectionCard(
              title: 'Baixar aplicativo',
              icon: Icons.get_app_rounded,
              accentColor: const Color(0xFF6366F1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Android: Play Store (Gestão Yahweh). iPhone: TestFlight — toque em Apple abaixo; depois instale Gestão Yahweh - Igrejas.',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                          height: 1.4)),
                  const SizedBox(height: 8),
                  Text(
                    AppConstants.marketingDownloadIosTestFlightHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .doc('config/appDownloads')
                        .snapshots(),
                    builder: (context, dlSnap) {
                      final data = dlSnap.data?.data() ?? {};
                      final androidEff = AppConstants
                          .effectiveAppDownloadsAndroidUrl(data);
                      final iosEff =
                          AppConstants.effectiveAppDownloadsIosUrl(data);
                      return Wrap(spacing: 10, runSpacing: 10, children: [
                        FilledButton.icon(
                            onPressed: () {
                              logChurchPublicLocal('download_android');
                              launchExternalLocal(
                                  context, Uri.parse(androidEff));
                            },
                            icon: const Icon(Icons.android),
                            label: const Text('Android')),
                        FilledButton.tonalIcon(
                            onPressed: iosEff.isEmpty
                                ? null
                                : () {
                                    logChurchPublicLocal('download_ios');
                                    launchExternalLocal(
                                        context, Uri.parse(iosEff));
                                  },
                            icon: const Icon(Icons.apple),
                            label: const Text('iPhone (TestFlight)')),
                      ]);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            StreamBuilder<
                List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              stream: _churchPublicMergedPublicacoesStream(igrejaId, limit: 12),
              builder: (context, newsSnap) {
                if (newsSnap.hasError)
                  return Text('Erro ao carregar publicações.',
                      style: TextStyle(color: Colors.red.shade700));
                if (!newsSnap.hasData)
                  return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: LinearProgressIndicator());
                final items = newsSnap.data ?? [];
                final preloadUrls = items
                    .map((d) => _churchPublicNoticiaCoverUrl(d.data()))
                    .where((u) => u.trim().isNotEmpty)
                    .take(10)
                    .toList();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  preloadNetworkImages(context, preloadUrls, maxItems: 12);
                  unawaited(scheduleFeedMediaWarmup(
                    context,
                    items.map((e) => e.data()).toList(),
                    maxDocs: 12,
                  ));
                });
                if (items.isEmpty)
                  return Text(
                      'Ainda não há publicações. Use o painel da igreja para postar avisos e eventos.',
                      style:
                          TextStyle(fontSize: 14, color: Colors.grey.shade700));
                final avisos = items
                    .where((d) =>
                        ChurchTenantPostsCollections.segmentFromPostRef(
                                d.reference) ==
                            ChurchTenantPostsCollections.avisos)
                    .toList();
                final eventos = items
                    .where((d) =>
                        ChurchTenantPostsCollections.segmentFromPostRef(
                                d.reference) ==
                            ChurchTenantPostsCollections.noticias)
                    .toList();

                Widget sectionTitle(String text, IconData icon) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10, top: 4),
                    child: Row(
                      children: [
                        Icon(icon, size: 20, color: const Color(0xFF1E3A8A)),
                        const SizedBox(width: 8),
                        Text(
                          text,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                Widget renderPublicacao(
                    QueryDocumentSnapshot<Map<String, dynamic>> d) {
                  final p = d.data();
                  final title = (p['title'] ?? 'Publicação').toString();
                  final body = (p['body'] ?? p['text'] ?? '').toString();
                  final seg = ChurchTenantPostsCollections.segmentFromPostRef(
                      d.reference);
                  final isEvento =
                      seg == ChurchTenantPostsCollections.noticias &&
                          (p['type'] ?? '').toString() == 'evento';
                  final media = <Widget>[];

                  if (isEvento) {
                    final photos = eventNoticiaPhotoUrls(p);
                    final cover = _churchPublicNoticiaCoverUrl(p);
                    final vidFile = eventNoticiaHostedVideoPlayUrl(p);
                    final extVid = eventNoticiaExternalVideoUrl(p);
                    final hasVideo = (vidFile != null && vidFile.isNotEmpty) ||
                        (extVid != null && extVid.isNotEmpty);

                    Future<void> openEventoVideo() async {
                      final raw = (vidFile != null && vidFile.isNotEmpty)
                          ? vidFile
                          : extVid;
                      if (raw == null || raw.isEmpty) return;
                      final td = sanitizeImageUrl(
                          eventNoticiaDisplayVideoThumbnailUrl(p) ?? '');
                      final cv = sanitizeImageUrl(cover);
                      final thumb = isValidImageUrl(td)
                          ? td
                          : (isValidImageUrl(cv) ? cv : null);
                      final t = (p['titulo'] ?? p['titulo_evento'] ?? '')
                          .toString()
                          .trim();
                      await _openPublicVideo(
                        context,
                        raw,
                        thumbnailUrl: thumb,
                        title: t,
                      );
                    }

                    if (photos.isNotEmpty) {
                      final u0 = sanitizeImageUrl(photos.first);
                      if (isValidImageUrl(u0) ||
                          eventNoticiaPhotoStoragePathAt(p, 0) != null) {
                        media.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: ChurchPublicConstrainedMedia(
                              child: LayoutBuilder(
                                builder: (ctx, c) {
                                  final w = c.maxWidth;
                                  final h = c.maxHeight;
                                  return LazyViewportBuilder(
                                    visibilityKey:
                                        'church-pub-${d.id}-evt-photo',
                                    placeholder: SizedBox.expand(
                                      child: YahwehPremiumFeedShimmer
                                          .mediaCover(),
                                    ),
                                    builder: () => StableStorageImage(
                                      storagePath:
                                          eventNoticiaPhotoStoragePathAt(
                                              p, 0),
                                      imageUrl:
                                          isValidImageUrl(u0) ? u0 : null,
                                      width: w,
                                      height: h,
                                      fit: BoxFit.contain,
                                      memCacheWidth: 900,
                                      memCacheHeight: 900,
                                      skipFreshDisplayUrl: false,
                                      errorWidget: Container(
                                        color: const Color(0xFFEEF2FF),
                                        alignment: Alignment.center,
                                        child: Icon(
                                            Icons.image_not_supported_rounded,
                                            size: 48,
                                            color: Colors.indigo.shade200),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      }
                      if (photos.length > 1) {
                        media.add(Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                              '+ ${photos.length - 1} foto(s) no app da igreja',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600)),
                        ));
                      }
                      if (hasVideo) {
                        media.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: FilledButton.icon(
                              onPressed: openEventoVideo,
                              icon:
                                  const Icon(Icons.play_circle_filled_rounded),
                              label: const Text('Assistir vídeo do evento'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626)),
                            ),
                          ),
                        );
                      }
                    }

                    if (photos.isEmpty && cover.isNotEmpty && hasVideo) {
                      final cov = sanitizeImageUrl(cover);
                      final vPlay =
                          vidFile != null ? sanitizeImageUrl(vidFile) : '';
                      if (kIsWeb &&
                          vidFile != null &&
                          vPlay.isNotEmpty &&
                          looksLikeHostedVideoFileUrl(vPlay)) {
                        media.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: ChurchPublicConstrainedMedia(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  PremiumHtmlFeedVideo(
                                    videoUrl: vPlay,
                                    visibilityKey: '${d.id}_pub_evt',
                                    showControls: true,
                                    posterUrl:
                                        isValidImageUrl(cov) ? cov : null,
                                    startLoadingImmediately: true,
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Material(
                                      color: Colors.black45,
                                      shape: const CircleBorder(),
                                      clipBehavior: Clip.antiAlias,
                                      child: IconButton(
                                        tooltip: 'Tela cheia',
                                        onPressed: openEventoVideo,
                                        icon: const Icon(
                                            Icons.fullscreen_rounded,
                                            color: Colors.white,
                                            size: 22),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      } else {
                        media.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: openEventoVideo,
                                borderRadius: BorderRadius.circular(14),
                                child: ChurchPublicConstrainedMedia(
                                  child: Stack(
                                    fit: StackFit.expand,
                                    alignment: Alignment.center,
                                    children: [
                                      LayoutBuilder(
                                        builder: (ctx, c) {
                                          return LazyViewportBuilder(
                                            visibilityKey:
                                                'church-pub-${d.id}-evt-thumb',
                                            placeholder: SizedBox.expand(
                                              child: YahwehPremiumFeedShimmer
                                                  .mediaCover(),
                                            ),
                                            builder: () => StableStorageImage(
                                              storagePath:
                                                  eventNoticiaThumbStoragePath(
                                                          p) ??
                                                      eventNoticiaImageStoragePath(
                                                          p),
                                              imageUrl: cover,
                                              width: c.maxWidth,
                                              height: c.maxHeight,
                                              fit: BoxFit.contain,
                                              memCacheWidth: 900,
                                              memCacheHeight: 900,
                                              errorWidget: Container(
                                                  color: const Color(
                                                      0xFF1E3A8A)),
                                            ),
                                          );
                                        },
                                      ),
                                      Container(color: Colors.black38),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.play_circle_filled_rounded,
                                              size: 64,
                                              color: Colors.white
                                                  .withOpacity(0.95)),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Assistir vídeo',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                              shadows: const [
                                                Shadow(
                                                    blurRadius: 8,
                                                    color: Colors.black54)
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    } else if (photos.isEmpty && hasVideo && cover.isEmpty) {
                      if (vidFile != null && vidFile.isNotEmpty) {
                        final v0 = sanitizeImageUrl(vidFile);
                        if (kIsWeb && looksLikeHostedVideoFileUrl(v0)) {
                          media.add(
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: ChurchPublicConstrainedMedia(
                                child: PremiumHtmlFeedVideo(
                                  videoUrl: v0,
                                  visibilityKey: '${d.id}_pub_evt_nc',
                                  showControls: true,
                                  startLoadingImmediately: true,
                                ),
                              ),
                            ),
                          );
                        } else {
                          media.add(
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: FilledButton.icon(
                                onPressed: openEventoVideo,
                                icon: const Icon(
                                    Icons.play_circle_outline_rounded),
                                label: const Text('Assistir vídeo do evento'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E3A8A)),
                              ),
                            ),
                          );
                        }
                      } else if (extVid != null && extVid.isNotEmpty) {
                        media.add(
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: FilledButton.icon(
                              onPressed: openEventoVideo,
                              icon: const Icon(Icons.ondemand_video_rounded),
                              label: const Text('Ver no YouTube / Vimeo'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white),
                            ),
                          ),
                        );
                      }
                    }
                  } else {
                    // Avisos: mesma cobertura de capa que o mural (fotoUrl, gs://, path) + path derivado de URL expirada.
                    if (eventNoticiaPostHasFeedCoverRow(p)) {
                      final hint =
                          sanitizeImageUrl(eventNoticiaFeedCoverHintUrl(p));
                      final path0 = eventNoticiaPhotoStoragePathAt(p, 0);
                      media.add(
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: ChurchPublicConstrainedMedia(
                            child: LayoutBuilder(
                              builder: (ctx, c) {
                                final dpr = MediaQuery.devicePixelRatioOf(ctx)
                                    .clamp(1.0, 3.0);
                                final mw = (c.maxWidth * dpr).round().clamp(400, 1400);
                                final mh = (c.maxHeight * dpr).round().clamp(400, 1400);
                                return LazyViewportBuilder(
                                  visibilityKey:
                                      'church-pub-${d.id}-aviso-cover',
                                  placeholder: SizedBox.expand(
                                    child: YahwehPremiumFeedShimmer
                                        .mediaCover(),
                                  ),
                                  builder: () => StableStorageImage(
                                    storagePath: path0,
                                    imageUrl:
                                        hint.isNotEmpty ? hint : null,
                                    width: c.maxWidth,
                                    height: c.maxHeight,
                                    fit: BoxFit.contain,
                                    memCacheWidth: mw,
                                    memCacheHeight: mh,
                                    skipFreshDisplayUrl: false,
                                    errorWidget: Container(
                                      color: const Color(0xFFEEF2FF),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.image_not_supported_rounded,
                                        size: 48,
                                        color: Colors.indigo.shade200,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FA),
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                          ...media,
                          if (body.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(body,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade800,
                                      height: 1.35)),
                            ),
                          YahwehSocialPostBar(
                            tenantId: igrejaId,
                            postId: d.id,
                            isEvento: isEvento,
                            churchSlug: slugClean,
                            postsParentCollection: seg,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionTitle('Avisos', Icons.campaign_rounded),
                    if (avisos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('Nenhum aviso disponível no momento.',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade700)),
                      )
                    else
                      ...avisos.map(renderPublicacao),
                    const SizedBox(height: 6),
                    sectionTitle('Eventos', Icons.event_rounded),
                    if (eventos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text('Nenhum evento disponível no momento.',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey.shade700)),
                      )
                    else
                      ...eventos.map(renderPublicacao),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            _PublicEventosSection(
              igrejaId: igrejaId,
              churchSlug: slugClean,
              churchVenueAddress: endereco,
            ),
            const SizedBox(height: 32),
            _PublicFooter(
              onAdquirirSistema: () {
                logChurchPublicLocal('footer_adquirir_sistema');
                Navigator.pushNamed(context, '/planos');
              },
              onDeveloperWhatsApp: () {
                logChurchPublicLocal('footer_dev_whatsapp');
                launchExternalLocal(
                  context,
                  Uri.parse(
                    'https://wa.me/$kLegalSupportWhatsAppWaMe?text=${Uri.encodeComponent('Olá! Vim pelo site público da igreja (Gestão YAHWEH).')}',
                  ),
                );
              },
              onDeveloperEmail: () {
                logChurchPublicLocal('footer_dev_email');
                launchExternalLocal(
                  context,
                  Uri.parse(
                    'mailto:$kLegalSupportEmail?subject=${Uri.encodeComponent('Gestão YAHWEH — site público')}',
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProofChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ProofChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ThemeCleanPremium.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Site público por slug. Na web, garante sessão anônima para o Firebase Storage exibir logo, fotos e vídeos.
class ChurchPublicPage extends StatefulWidget {
  final String slug;

  /// Abre detalhe da publicação ao carregar (rota `/{slug}/{noticiaId}`).
  final String? openNoticiaId;
  const ChurchPublicPage({super.key, required this.slug, this.openNoticiaId});

  @override
  State<ChurchPublicPage> createState() => _ChurchPublicPageState();
}

class _ChurchPublicPageState extends State<ChurchPublicPage> {
  final GlobalKey _sectionInicioKey = GlobalKey();
  final GlobalKey _sectionAvisosKey = GlobalKey();
  final GlobalKey _sectionDestaquesKey = GlobalKey();
  final GlobalKey _sectionEventosKey = GlobalKey();

  void _scrollToSection(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 460),
          curve: Curves.easeOutCubic,
          alignment: 0.06,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(PublicSiteMediaAuth.ensureWebAnonymousForStorage());
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ChurchPublicPageInner(
      slug: widget.slug,
      openNoticiaId: widget.openNoticiaId,
      sectionInicioKey: _sectionInicioKey,
      sectionAvisosKey: _sectionAvisosKey,
      sectionDestaquesKey: _sectionDestaquesKey,
      sectionEventosKey: _sectionEventosKey,
      onScrollInicio: () => _scrollToSection(_sectionInicioKey),
      onScrollAvisos: () => _scrollToSection(_sectionAvisosKey),
      onScrollDestaques: () => _scrollToSection(_sectionDestaquesKey),
      onScrollEventos: () => _scrollToSection(_sectionEventosKey),
    );
  }
}

class _NotFound extends StatelessWidget {
  final String slug;
  final String prettyName;
  const _NotFound({required this.slug, required this.prettyName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Card(
            elevation: 10,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/LOGO_GESTAO_YAHWEH.png', height: 54),
                  const SizedBox(height: 14),
                  Text(
                    'Igreja não encontrada',
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w900),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Não existe uma igreja cadastrada com o slug:\n/$slug',
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/signup'),
                        icon: const Icon(Icons.app_registration),
                        label: const Text('Cadastrar igreja (teste grátis)'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/igreja/login'),
                        icon: const Icon(Icons.login),
                        label: const Text('Acessar Sistema'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pushNamed(context, '/admin'),
                        child: const Text('Sou administrador'),
                      ),
                    ],
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

/// Site público bloqueado (Master / licença / assinatura) — mesmo vocabulário visual do ecossistema.
class _ChurchPublicMaintenanceView extends StatelessWidget {
  final String churchName;
  const _ChurchPublicMaintenanceView({this.churchName = ''});

  @override
  Widget build(BuildContext context) {
    final name = churchName.trim();
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: ThemeCleanPremium.surfaceVariant,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(ThemeCleanPremium.spaceLg),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ThemeCleanPremium.cardBackground,
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                border: Border.all(color: const Color(0xFFE8EDF3)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: ThemeCleanPremium.spaceXl,
                    vertical: ThemeCleanPremium.spaceXl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.construction_rounded,
                        size: 56, color: ThemeCleanPremium.navSidebarAccent),
                    const SizedBox(height: ThemeCleanPremium.spaceMd),
                    Text(
                      'Site em manutenção',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: ThemeCleanPremium.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceSm),
                    Text(
                      name.isEmpty
                          ? 'Este portal está temporariamente indisponível. A igreja ou a assinatura podem estar em revisão pela equipe Gestão YAHWEH.'
                          : 'O site de $name está temporariamente indisponível. Tente novamente em breve ou fale com a liderança.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        height: 1.45,
                        color: ThemeCleanPremium.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: ThemeCleanPremium.spaceLg),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: ThemeCleanPremium.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(ThemeCleanPremium.radiusMd),
                        ),
                      ),
                      onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context, '/', (_) => false),
                      child: const Text('Voltar à página inicial'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String title;
  final String message;
  const _ErrorBox({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(ThemeCleanPremium.radiusLg)),
            shadowColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
                boxShadow: ThemeCleanPremium.softUiCardShadow,
                color: ThemeCleanPremium.cardBackground,
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 52, color: ThemeCleanPremium.error),
                  const SizedBox(height: 12),
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          color: ThemeCleanPremium.onSurfaceVariant,
                          height: 1.4)),
                  const SizedBox(height: 14),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd),
                      ),
                    ),
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                        context, '/', (_) => false),
                    child: const Text('Voltar para Home'),
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

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
