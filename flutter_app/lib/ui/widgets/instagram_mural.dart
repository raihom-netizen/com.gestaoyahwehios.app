import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode;
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/noticia_expired_media_cleanup_service.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/evento_calendar_integration.dart';
import 'package:gestao_yahweh/core/mural_video_warmup.dart';
import 'package:gestao_yahweh/core/noticia_social_service.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaDisplayVideoThumbnailUrl,
        eventNoticiaExternalVideoUrl,
        eventNoticiaHostedVideoPlayUrl,
        eventNoticiaPhotoStoragePathAt,
        eventNoticiaPhotoUrls,
        eventNoticiaVideosFromDoc,
        looksLikeHostedVideoFileUrl,
        noticiaImageRefsPreferDisplayOrder,
        postFeedCarouselAspectRatioForIndex,
        youtubeThumbnailUrlForVideoUrl;
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show buildNoticiaInviteShareMessage, resolveNoticiaHostedVideoShareUrl;
import 'package:gestao_yahweh/core/services/app_storage_image_service.dart';
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show StableStorageImage;
import 'package:gestao_yahweh/core/widgets/stable_storage_image.dart'
    show ChurchTenantLogoCircleAvatar;
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        SafeNetworkImage,
        dedupeImageRefsByStorageIdentity,
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlsListFromMap,
        imageUrlFromMap,
        churchTenantLogoUrl,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl,
        preloadNetworkImages,
        firebaseStorageMediaUrlLooksLike;
import 'package:gestao_yahweh/ui/widgets/church_chewie_video.dart';
import 'package:gestao_yahweh/ui/widgets/church_public_premium_ui.dart'
    show ChurchPublicConstrainedMedia;
import 'package:gestao_yahweh/ui/widgets/yahweh_premium_feed_widgets.dart'
    show
        YahwehInstagramHoverCard,
        YahwehPremiumFeedShimmer,
        resolveNoticiaSharePreviewImageUrl,
        scheduleFeedMediaWarmup;
import 'package:gestao_yahweh/ui/widgets/premium_storage_video/premium_html_feed_video.dart';
import 'package:gestao_yahweh/ui/widgets/mural_inline_native_video.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:shimmer/shimmer.dart';
import 'church_noticia_share_sheet.dart'
    show showChurchNoticiaShareSheet, shareRectFromContext;
import '../theme_clean_premium.dart';

/// Diagnóstico no Console (F12): prefixo pedido para filtrar falhas de Storage/CORS/decode.
/// O mural usa [SafeNetworkImage] (não [CachedNetworkImage] isolado em URLs Firebase na web).
void _muralImageLoadError(String url, Object? error) {
  debugPrint('Erro Storage: $error | url=$url');
}

({String? storagePath, String? imageUrl, String? gsUrl}) _muralStableParamsFromRef(
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

/// Garante que [imageStoragePaths] legado (ex.: `igrejas/.../noticias/`) não prevaleça
/// sobre uma URL https já exibível para outro prefixo (ex.: `public/gestao_yahweh/fotos/`).
String? _muralStoragePathAlignedWithPhotoRef({
  required String photoRefRaw,
  String? pathFromFirestore,
}) {
  final raw = sanitizeImageUrl(photoRefRaw);
  final pfs = (pathFromFirestore ?? '').trim();
  if (pfs.isEmpty) return null;
  if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
    return pfs;
  }
  final pathFromUrl = firebaseStorageObjectPathFromHttpUrl(raw);
  if (pathFromUrl == null || pathFromUrl.isEmpty) {
    return pfs;
  }
  final normUrl =
      normalizeFirebaseStorageObjectPath(pathFromUrl.replaceFirst(RegExp(r'^/+'), ''));
  final normFs =
      normalizeFirebaseStorageObjectPath(pfs.replaceFirst(RegExp(r'^/+'), ''));
  if (normFs == normUrl) return pfs;
  return null;
}

/// No feed, usa miniatura do primeiro slide quando existir em `media_info`.
String muralFeedPhotoRefAt(
    Map<String, dynamic> data, int idx, List<String> photos) {
  if (idx < 0 || idx >= photos.length) return '';
  if (idx != 0) return photos[idx];
  final mi = data['media_info'];
  if (mi is! Map) return photos[idx];
  final orig = sanitizeImageUrl(
      (mi['url_original'] ?? mi['urlOriginal'] ?? '').toString());
  if (orig.isNotEmpty && isValidImageUrl(orig)) return orig;
  final t = sanitizeImageUrl(
      (mi['url_thumb'] ?? mi['urlThumb'] ?? '').toString());
  if (t.isNotEmpty && isValidImageUrl(t)) return t;
  return photos[idx];
}

class InstagramMural extends StatefulWidget {
  final String tenantId;
  final String role;
  final String churchSlug;
  const InstagramMural({
    super.key,
    required this.tenantId,
    required this.role,
    required this.churchSlug,
  });

  @override
  State<InstagramMural> createState() => _InstagramMuralState();
}

class _InstagramMuralState extends State<InstagramMural> {
  Map<String, dynamic>? _tenantData;
  int _streamKey = 0;
  static const int _feedPageSize = 15;
  int _feedQueryLimit = _feedPageSize;
  bool _loadingMoreFeed = false;
  int _lastRawDocsCount = 0;

  User? get _user => FirebaseAuth.instance.currentUser;
  String get uid => _user?.uid ?? '';
  String get displayName {
    final dn = _user?.displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    return 'Administrador';
  }

  bool get _canEdit {
    final r = widget.role.toLowerCase();
    return r == 'adm' ||
        r == 'admin' ||
        r == 'gestor' ||
        r == 'master' ||
        r == 'lider';
  }

  bool get _canManageAll {
    final r = widget.role.toLowerCase();
    return r == 'adm' || r == 'admin' || r == 'gestor' || r == 'master';
  }

  bool _canEditDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (_canManageAll) return true;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final data = doc.data() ?? {};
    return uid.isNotEmpty && (data['createdByUid'] ?? '').toString() == uid;
  }

  CollectionReference<Map<String, dynamic>> get _noticias =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection(ChurchTenantPostsCollections.noticias);

  CollectionReference<Map<String, dynamic>> get _avisos =>
      FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .collection(ChurchTenantPostsCollections.avisos);

  String get _nomeIgreja =>
      (_tenantData?['name'] ?? _tenantData?['nome'] ?? '').toString();
  String get _logoUrl => churchTenantLogoUrl(_tenantData);

  @override
  void initState() {
    super.initState();
    _loadTenant();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_canManageAll) {
        NoticiaExpiredMediaCleanupService.runOnceForTenant(widget.tenantId);
      }
    });
  }

  Future<void> _loadTenant() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .get();
      if (mounted) setState(() => _tenantData = snap.data());
    } catch (_) {}
  }

  Future<void> _deletePost(DocumentSnapshot<Map<String, dynamic>> doc) async {
    final nome = (doc.data()?['title'] ?? doc.id).toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        title: const Text('Excluir'),
        content: Text('Deseja excluir "$nome"?'),
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
    if (ok == true) {
      await doc.reference.delete();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(ThemeCleanPremium.successSnackBar('Excluído.'));
      }
    }
  }

  Future<void> _openEditor(
      {DocumentSnapshot<Map<String, dynamic>>? doc,
      required String type}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => MuralAvisoEditorPage(
                tenantId: widget.tenantId,
                postsCollection: type == 'evento' ? _noticias : _avisos,
                doc: doc,
                type: type,
                churchSlug: widget.churchSlug,
              )),
    );
    if (result == true && mounted) setState(() {});
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}m';
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}min';
    return 'agora';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _streamForAll() {
    return _avisos
        .orderBy('createdAt', descending: true)
        .limit(_feedQueryLimit)
        .snapshots();
  }

  void _maybeLoadMoreFromScroll(ScrollMetrics metrics) {
    if (_loadingMoreFeed) return;
    if (_lastRawDocsCount < _feedQueryLimit) return;
    if ((metrics.maxScrollExtent - metrics.pixels) > 520) return;
    _loadingMoreFeed = true;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _feedQueryLimit += _feedPageSize;
        _streamKey++;
      });
      _loadingMoreFeed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical) {
          _maybeLoadMoreFromScroll(n.metrics);
        }
        return false;
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 12),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header super premium — padding responsivo para Android/iPhone
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow =
                    constraints.maxWidth < ThemeCleanPremium.breakpointMobile;
                final pad = isNarrow ? ThemeCleanPremium.spaceSm : 24.0;
                return Container(
                  padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary.withValues(alpha: 0.06),
                        ThemeCleanPremium.primary.withValues(alpha: 0.02),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border(
                        bottom: BorderSide(
                            color: Colors.grey.shade200.withValues(alpha: 0.8))),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ThemeCleanPremium.primary.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                      child: Icon(Icons.campaign_rounded,
                          color: ThemeCleanPremium.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Mural de Avisos',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1E293B),
                            letterSpacing: -0.3),
                      ),
                    ),
                    if (_canEdit)
                      FilledButton.icon(
                        onPressed: () => _openEditor(type: 'aviso'),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Novo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 12),
                          minimumSize: const Size(
                              ThemeCleanPremium.minTouchTarget,
                              ThemeCleanPremium.minTouchTarget),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  ThemeCleanPremium.radiusSm)),
                          elevation: 0,
                        ),
                      ),
                  ]),
                );
              },
            ),
            Padding(
              padding: ThemeCleanPremium.pagePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    key: ValueKey(_streamKey),
                    stream: _streamForAll(),
                    builder: (context, snap) {
                      _lastRawDocsCount = snap.data?.docs.length ?? 0;
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    size: 48, color: ThemeCleanPremium.error),
                                const SizedBox(height: 12),
                                Text('Erro ao carregar o mural.',
                                    style:
                                        TextStyle(color: Colors.grey.shade700)),
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  onPressed: () => setState(() => _streamKey++),
                                  icon: const Icon(Icons.refresh_rounded,
                                      size: 20),
                                  label: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (snap.connectionState == ConnectionState.waiting &&
                          !snap.hasData) {
                        return YahwehPremiumFeedShimmer.muralFeedSkeleton();
                      }
                      const type = 'aviso';
                      final docs = snap.data?.docs ?? [];
                      if (docs.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!context.mounted) return;
                          unawaited(scheduleFeedMediaWarmup(
                            context,
                            docs.map((d) => d.data()).toList(),
                          ));
                        });
                      }
                      if (docs.isEmpty) {
                        return SizedBox(
                          height: 300,
                          child: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Icon(Icons.campaign_outlined,
                                    size: 56, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                Text(
                                  'Nenhum aviso publicado',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade500),
                                ),
                                const SizedBox(height: 4),
                                Text('Toque em "Novo" para criar',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade400)),
                              ])),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        cacheExtent: 1600,
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          return YahwehInstagramHoverCard(
                            child: _PostCard(
                              doc: doc,
                              feedIndex: i,
                              feedDocs: docs,
                              nomeIgreja: _nomeIgreja,
                              logoUrl: _logoUrl,
                              tenantData: _tenantData,
                              churchSlug: widget.churchSlug,
                              canEdit: _canEditDoc(doc),
                              onEdit: () =>
                                  _openEditor(doc: doc, type: type),
                              onDelete: () => _deletePost(doc),
                              onShare: (Rect? shareOrigin) async {
                                final d = doc.data();
                                DateTime? sdt;
                                try {
                                  sdt = (d['startAt'] as Timestamp).toDate();
                                } catch (_) {}
                                final lat = d['locationLat'];
                                final lng = d['locationLng'];
                                final coverUrl =
                                    await resolveNoticiaSharePreviewImageUrl(
                                        d);
                                final videoShareUrl =
                                    await resolveNoticiaHostedVideoShareUrl(
                                        d);
                                final texto = (d['text'] ?? d['body'] ?? '')
                                    .toString();
                                final slug = widget.churchSlug.trim();
                                final inviteCardUrl = slug.isNotEmpty
                                    ? AppConstants.shareNoticiaIgrejaEventoUrl(
                                        widget.churchSlug, doc.id)
                                    : AppConstants.shareNoticiaCardUrl(
                                        widget.tenantId, doc.id);
                                final publicSite =
                                    AppConstants.publicSiteShortUrl(slug);
                                final churchName = _nomeIgreja
                                        .trim()
                                        .isNotEmpty
                                    ? _nomeIgreja.trim()
                                    : 'Nossa igreja';
                                final msg = buildNoticiaInviteShareMessage(
                                  churchName: churchName,
                                  noticiaKind: 'aviso',
                                  title: (d['title'] ?? '').toString(),
                                  bodyText: texto,
                                  startAt: sdt,
                                  location: (d['location'] ?? '').toString(),
                                  locationLat: lat is num
                                      ? lat.toDouble()
                                      : (lat != null
                                          ? double.tryParse(lat.toString())
                                          : null),
                                  locationLng: lng is num
                                      ? lng.toDouble()
                                      : (lng != null
                                          ? double.tryParse(lng.toString())
                                          : null),
                                  publicSiteUrl: publicSite,
                                  inviteCardUrl: inviteCardUrl,
                                );
                                if (!context.mounted) return;
                                await showChurchNoticiaShareSheet(
                                  context,
                                  shareLink: inviteCardUrl,
                                  shareMessage: msg,
                                  shareSubject: 'Convite — $churchName',
                                  previewImageUrl: coverUrl,
                                  videoPlayUrl: videoShareUrl,
                                  sharePositionOrigin: shareOrigin,
                                );
                              },
                              timeAgo: _timeAgo,
                              tenantId: widget.tenantId,
                            ),
                          );
                        },
                      );
                    },
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

// ═══════════════════════════════════════════════════════════════════════════════
// Links: convite (OG), site público e mapa — mural avisos/eventos
// ═══════════════════════════════════════════════════════════════════════════════
class _MuralPostLinksRow extends StatelessWidget {
  final String tenantId;
  final String churchSlug;
  final String shareInviteUrl;
  final String eventLocation;
  final double? eventLat;
  final double? eventLng;

  const _MuralPostLinksRow({
    required this.tenantId,
    required this.churchSlug,
    required this.shareInviteUrl,
    required this.eventLocation,
    this.eventLat,
    this.eventLng,
  });

  static double? _parseD(dynamic v) {
    if (v is num) return v.toDouble();
    if (v != null) return double.tryParse(v.toString());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final slug = churchSlug.trim();
    final publicSite = AppConstants.publicSiteShortUrl(slug);

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future:
          FirebaseFirestore.instance.collection('igrejas').doc(tenantId).get(),
      builder: (context, snap) {
        double? lat = eventLat;
        double? lng = eventLng;
        final church = snap.data?.data();
        if (church != null) {
          lat ??= _parseD(church['latitude']);
          lng ??= _parseD(church['longitude']);
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
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
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
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Post Card — Design Instagram Premium com suporte a múltiplas fotos
// ═══════════════════════════════════════════════════════════════════════════════
class _PostCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int feedIndex;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> feedDocs;
  final String nomeIgreja, logoUrl, tenantId, churchSlug;
  final Map<String, dynamic>? tenantData;
  final bool canEdit;
  final VoidCallback onEdit, onDelete;
  final Future<void> Function(Rect? sharePositionOrigin) onShare;
  final String Function(DateTime) timeAgo;
  const _PostCard({
    required this.doc,
    required this.feedIndex,
    required this.feedDocs,
    required this.nomeIgreja,
    required this.logoUrl,
    this.tenantData,
    this.churchSlug = '',
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
    required this.onShare,
    required this.timeAgo,
    required this.tenantId,
  });

  /// Fotos do post: [eventNoticiaPhotoUrls] (eventos/notícias) + [imageUrlsListFromMap] (avisos).
  /// Fallback: miniatura de vídeo quando o evento não tem foto (capa do vídeo ou preview YouTube).
  static List<String> imageUrlsFromData(Map<String, dynamic> data) {
    final seen = <String>{};
    final out = <String>[];
    bool usableRef(String s) {
      if (s.isEmpty || looksLikeHostedVideoFileUrl(s)) return false;
      final low = s.toLowerCase();
      if (low.contains('youtube.com') ||
          low.contains('youtu.be') ||
          low.contains('vimeo.com')) {
        return false;
      }
      if (isValidImageUrl(s)) return true;
      if (low.startsWith('gs://')) return true;
      return firebaseStorageMediaUrlLooksLike(s);
    }

    void addAll(List<String> list) {
      for (final raw in list) {
        final s = sanitizeImageUrl(raw);
        if (!usableRef(s)) continue;
        if (seen.add(s)) out.add(s);
      }
    }

    void addOne(String? raw) {
      if (raw == null) return;
      final s = sanitizeImageUrl(raw);
      if (!usableRef(s)) return;
      if (seen.add(s)) out.add(s);
    }

    addAll(eventNoticiaPhotoUrls(data));
    addAll(imageUrlsListFromMap(data));
    if (out.isEmpty) addOne(eventNoticiaDisplayVideoThumbnailUrl(data));
    if (out.isEmpty) addOne(imageUrlFromMap(data));
    return dedupeImageRefsByStorageIdentity(
        noticiaImageRefsPreferDisplayOrder(out));
  }

  /// Slides de **foto** no carrossel: não usa miniatura de vídeo como falsa foto; remove duplicata única = poster do vídeo.
  static List<String> photoUrlsOnlyForMural(Map<String, dynamic> data) {
    final seen = <String>{};
    final out = <String>[];
    bool usableRef(String s) {
      if (s.isEmpty || looksLikeHostedVideoFileUrl(s)) return false;
      final low = s.toLowerCase();
      if (low.contains('youtube.com') ||
          low.contains('youtu.be') ||
          low.contains('vimeo.com')) {
        return false;
      }
      if (isValidImageUrl(s)) return true;
      if (low.startsWith('gs://')) return true;
      return firebaseStorageMediaUrlLooksLike(s);
    }

    void addAll(List<String> list) {
      for (final raw in list) {
        final s = sanitizeImageUrl(raw);
        if (!usableRef(s)) continue;
        if (seen.add(s)) out.add(s);
      }
    }

    void addOne(String? raw) {
      if (raw == null) return;
      final s = sanitizeImageUrl(raw);
      if (!usableRef(s)) return;
      if (seen.add(s)) out.add(s);
    }

    addAll(eventNoticiaPhotoUrls(data));
    addAll(imageUrlsListFromMap(data));
    final vids = eventNoticiaVideosFromDoc(data);
    final hasVideo = vids.isNotEmpty;
    if (!hasVideo && out.isEmpty) addOne(imageUrlFromMap(data));

    final ordered = noticiaImageRefsPreferDisplayOrder(out);

    if (hasVideo && ordered.length == 1) {
      final u = sanitizeImageUrl(ordered.first);
      final thumbs = <String>{};
      for (final m in vids) {
        final t = sanitizeImageUrl(m['thumbUrl'] ?? '');
        if (t.isNotEmpty) thumbs.add(t);
      }
      final dt = eventNoticiaDisplayVideoThumbnailUrl(data);
      if (dt != null && dt.isNotEmpty) {
        thumbs.add(sanitizeImageUrl(dt));
      }
      if (thumbs.contains(u)) return [];
    }
    return dedupeImageRefsByStorageIdentity(ordered);
  }

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  int _carouselIndex = 0;
  bool _rsvpBusy = false;
  late final AnimationController _heartBurst;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _heartBurst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _preloadUpcomingImages());
  }

  @override
  void dispose() {
    _heartBurst.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doc.id != widget.doc.id) {
      _carouselIndex = 0;
    }
  }

  void _playHeartBurstAndLike({required bool liked}) {
    _heartBurst.forward(from: 0).whenComplete(() {
      if (mounted) _heartBurst.reset();
    });
    if (!liked) {
      _toggleLike(liked: liked);
    }
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _displayName {
    final dn = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    if (dn.isNotEmpty) return dn;
    return 'Membro';
  }

  static List<String> _imageUrlsFromData(Map<String, dynamic> data) {
    return _PostCard.imageUrlsFromData(data);
  }

  Future<({String name, String photo})> _memberDisplayForRsvp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (name: 'Membro', photo: '');
    var name = user.displayName?.trim() ?? '';
    var photo = user.photoURL?.trim() ?? '';
    if (name.isEmpty) {
      try {
        final uDoc = await FirebaseFirestore.instance
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

  void _onFeedVideoMostlyVisible() {
    scheduleMuralVideoWarmupFollowing(widget.feedDocs, widget.feedIndex);
    _preloadUpcomingImages();
  }

  void _preloadUpcomingImages() {
    if (!mounted) return;
    final upcoming = <String>[];
    for (var k = 0; k <= 2; k++) {
      final j = widget.feedIndex + k;
      if (j < 0 || j >= widget.feedDocs.length) continue;
      upcoming.addAll(_imageUrlsFromData(widget.feedDocs[j].data()));
    }
    if (upcoming.isEmpty) return;
    unawaited(preloadNetworkImages(context, upcoming, maxItems: 8));
  }

  Future<void> _togglePresencaEvento({
    required Map<String, dynamic> data,
    required bool currentlyConfirmed,
    required DateTime? eventDt,
  }) async {
    if (eventDt == null || !eventDt.isAfter(DateTime.now())) return;
    final uid = _uid;
    if (uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
            'Faça login no app para confirmar presença.'),
      );
      return;
    }
    setState(() => _rsvpBusy = true);
    try {
      final m = await _memberDisplayForRsvp();
      await NoticiaSocialService.toggleConfirmacaoPresenca(
        tenantId: widget.tenantId,
        postId: widget.doc.id,
        uid: uid,
        memberName: m.name,
        photoUrl: m.photo,
        currentlyConfirmed: currentlyConfirmed,
        parentCollection:
            ChurchTenantPostsCollections.segmentFromPostRef(widget.doc.reference),
      );
      if (!currentlyConfirmed && mounted) {
        final lat = data['locationLat'];
        final lng = data['locationLng'];
        await EventoCalendarIntegration.offerAddToCalendarDialog(
          context,
          eventTitle: (data['title'] ?? 'Evento').toString(),
          start: eventDt,
          location: (data['location'] ?? '').toString(),
          description: EventoCalendarIntegration.buildDescriptionWithPublicLink(
            body: (data['text'] ?? '').toString(),
            churchSlug: widget.churchSlug,
          ),
          locationLat: lat is num
              ? lat.toDouble()
              : (lat != null ? double.tryParse(lat.toString()) : null),
          locationLng: lng is num
              ? lng.toDouble()
              : (lng != null ? double.tryParse(lng.toString()) : null),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
              'Não foi possível atualizar a confirmação.'),
        );
      }
    } finally {
      if (mounted) setState(() => _rsvpBusy = false);
    }
  }

  Future<void> _toggleLike({
    required bool liked,
  }) async {
    final uid = _uid;
    if (uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Faça login no app para curtir.'),
      );
      return;
    }
    try {
      final dn = _displayName;
      final photo = FirebaseAuth.instance.currentUser?.photoURL?.trim() ?? '';
      await NoticiaSocialService.toggleCurtida(
        tenantId: widget.tenantId,
        postId: widget.doc.id,
        uid: uid,
        memberName: dn,
        photoUrl: photo,
        currentlyLiked: liked,
        parentCollection:
            ChurchTenantPostsCollections.segmentFromPostRef(widget.doc.reference),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Não foi possível curtir agora.'),
      );
    }
  }

  Future<void> _openCommentsSheet() async {
    final uid = _uid;
    if (uid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar('Faça login no app para comentar.'),
      );
      return;
    }
    final commentsRef = widget.doc.reference.collection('comentarios');
    final ctrl = TextEditingController();
    bool sending = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            Future<void> sendComment() async {
              final text = ctrl.text.trim();
              if (text.isEmpty || sending) return;
              setLocalState(() => sending = true);
              try {
                await commentsRef.add({
                  'authorUid': uid,
                  'authorName': _displayName,
                  'authorPhoto':
                      FirebaseAuth.instance.currentUser?.photoURL ?? '',
                  'text': text,
                  'texto': text,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                final current = (widget.doc.data()['commentsCount'] is num)
                    ? (widget.doc.data()['commentsCount'] as num).toInt()
                    : 0;
                await widget.doc.reference.set({
                  'commentsCount': (current + 1).clamp(0, 999999),
                }, SetOptions(merge: true));
                ctrl.clear();
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    ThemeCleanPremium.successSnackBar(
                        'Não foi possível comentar agora.'),
                  );
                }
              } finally {
                if (ctx.mounted) setLocalState(() => sending = false);
              }
            }

            final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 12 + bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(8))),
                      const SizedBox(height: 12),
                      Row(
                        children: const [
                          Icon(Icons.mode_comment_outlined, size: 20),
                          SizedBox(width: 8),
                          Text('Comentários',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 260,
                        child:
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: commentsRef
                              .orderBy('createdAt', descending: true)
                              .limit(60)
                              .snapshots(),
                          builder: (context, snap) {
                            final docs = snap.data?.docs ?? const [];
                            if (docs.isEmpty) {
                              return Center(
                                child: Text('Seja o primeiro a comentar.',
                                    style:
                                        TextStyle(color: Colors.grey.shade600)),
                              );
                            }
                            return ListView.separated(
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => Divider(
                                  height: 12, color: Colors.grey.shade200),
                              itemBuilder: (context, i) {
                                final c = docs[i].data();
                                final name =
                                    (c['authorName'] ?? c['name'] ?? 'Membro')
                                        .toString();
                                final text = (c['text'] ?? '').toString();
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                        radius: 14,
                                        backgroundColor: ThemeCleanPremium
                                            .primary
                                            .withValues(alpha: 0.12),
                                        child: Icon(Icons.person,
                                            size: 14,
                                            color: ThemeCleanPremium.primary)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12)),
                                          const SizedBox(height: 2),
                                          Text(text,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade800)),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: ctrl,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => sendComment(),
                              decoration: const InputDecoration(
                                hintText: 'Escreva um comentário...',
                                prefixIcon:
                                    Icon(Icons.chat_bubble_outline_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: sending ? null : sendComment,
                            icon: sending
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.send_rounded),
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  ThemeCleanPremium.primary.withValues(alpha: 0.1),
                              minimumSize: const Size(
                                  ThemeCleanPremium.minTouchTarget,
                                  ThemeCleanPremium.minTouchTarget),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final data = widget.doc.data();
    final type = (data['type'] ?? 'aviso').toString();
    final title = (data['title'] ?? '').toString();
    final text = (data['text'] ?? '').toString();
    final muralPhotos = _PostCard.photoUrlsOnlyForMural(data);
    final videoEntries = eventNoticiaVideosFromDoc(data);
    final photoCount = muralPhotos.length;
    final videoCount = videoEntries.length;
    final carouselLen = photoCount + videoCount;
    final mediaChipLabel = carouselLen > 0
        ? (photoCount == 0
            ? (videoCount > 1 ? '$videoCount vídeos' : 'Vídeo')
            : videoCount == 0
                ? '$photoCount foto${photoCount > 1 ? 's' : ''}'
                : '$photoCount foto${photoCount > 1 ? 's' : ''} · $videoCount vídeo${videoCount > 1 ? 's' : ''}')
        : '';
    final location = (data['location'] ?? '').toString();
    final locLat = data['locationLat'];
    final locLng = data['locationLng'];
    final locationLat = locLat is num
        ? locLat.toDouble()
        : (locLat != null ? double.tryParse(locLat.toString()) : null);
    final locationLng = locLng is num
        ? locLng.toDouble()
        : (locLng != null ? double.tryParse(locLng.toString()) : null);
    final hasMapLocation = locationLat != null && locationLng != null;

    DateTime? eventDt;
    try {
      eventDt = (data['startAt'] as Timestamp).toDate();
    } catch (_) {}
    DateTime? createdDt;
    try {
      createdDt = (data['createdAt'] as Timestamp).toDate();
    } catch (_) {}
    final createdAgo = createdDt != null ? widget.timeAgo(createdDt) : '';
    final eventDateStr = eventDt != null
        ? '${_wn(eventDt.weekday)}, ${eventDt.day.toString().padLeft(2, '0')}/${eventDt.month.toString().padLeft(2, '0')}/${eventDt.year} às ${eventDt.hour.toString().padLeft(2, '0')}:${eventDt.minute.toString().padLeft(2, '0')}'
        : '';
    final isEvento = type == 'evento';
    final mergedLikes = NoticiaSocialService.mergedLikeUids(data);
    final liked = _uid.isNotEmpty && mergedLikes.contains(_uid);
    final likesCount = NoticiaSocialService.likeDisplayCount(data, mergedLikes);
    final commentsCount = (data['commentsCount'] is num)
        ? (data['commentsCount'] as num).toInt()
        : 0;
    final shareInviteUrl = widget.churchSlug.trim().isNotEmpty
        ? AppConstants.shareNoticiaIgrejaEventoUrl(
            widget.churchSlug, widget.doc.id)
        : AppConstants.shareNoticiaCardUrl(widget.tenantId, widget.doc.id);
    final rsvpUids = List<String>.from(
        ((data['rsvp'] as List?) ?? []).map((e) => e.toString()));
    final rsvpConfirmed = _uid.isNotEmpty && rsvpUids.contains(_uid);
    final rsvpCount = NoticiaSocialService.rsvpDisplayCount(data, rsvpUids);
    final canRsvpEvento =
        isEvento && eventDt != null && eventDt.isAfter(DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isEvento
                        ? [const Color(0xFFD97706), const Color(0xFFF59E0B)]
                        : [const Color(0xFF7C3AED), const Color(0xFFA78BFA)],
                  ),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: ChurchTenantLogoCircleAvatar(
                    tenantId: widget.tenantId,
                    tenantData: widget.tenantData,
                    preferImageUrl:
                        widget.logoUrl.isNotEmpty ? widget.logoUrl : null,
                    radius: 16,
                    fallbackIcon: Icons.church_rounded,
                    fallbackColor: ThemeCleanPremium.primary,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.nomeIgreja.isNotEmpty ? widget.nomeIgreja : 'Igreja',
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isEvento
                            ? const Color(0xFFFEF3C7)
                            : const Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isEvento ? 'Evento' : 'Aviso',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isEvento
                              ? const Color(0xFFD97706)
                              : const Color(0xFF7C3AED),
                        ),
                      ),
                    ),
                  ]),
                ],
              )),
              if (widget.canEdit)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded,
                      color: Colors.grey.shade600),
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
                          const SizedBox(width: 8),
                          Text('Excluir', style: TextStyle(color: Colors.red))
                        ])),
                  ],
                ),
            ]),
          ),

          // Faixa estreita (evento: título+data; aviso sem foto: só título)
          if (isEvento && (title.isNotEmpty || eventDateStr.isNotEmpty))
            _buildCompactTitleStrip(title, eventDateStr, isEvento),
          if (!isEvento && carouselLen == 0 && title.isNotEmpty)
            _buildCompactTitleStrip(title, '', isEvento),

          // Mídia — carrossel 1:1 (Instagram): N fotos + M vídeos (deslizar)
          if (carouselLen > 0)
            GestureDetector(
              key: ValueKey<String>('mural_carousel_${widget.doc.id}'),
              onDoubleTap: () => _playHeartBurstAndLike(liked: liked),
              behavior: HitTestBehavior.translucent,
              child: GestureDetector(
                onTap: () {
                  if (_carouselIndex < photoCount) {
                    _openFullScreen(context, muralPhotos);
                  } else {
                    unawaited(_openMuralPostVideoAt(
                        context, _carouselIndex - photoCount));
                  }
                },
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.hardEdge,
                  children: [
                    AspectRatio(
                      aspectRatio: postFeedCarouselAspectRatioForIndex(
                        data,
                        _carouselIndex,
                        photoCount,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: PageView.builder(
                              itemCount: carouselLen,
                              onPageChanged: (p) =>
                                  setState(() => _carouselIndex = p),
                              itemBuilder: (_, idx) {
                                if (idx < photoCount) {
                                  final refStr = muralFeedPhotoRefAt(
                                      data, idx, muralPhotos);
                                  final pathFs = eventNoticiaPhotoStoragePathAt(
                                      data, idx);
                                  final ps =
                                      _muralStableParamsFromRef(refStr);
                                  final pathCombined =
                                      pathFs ?? ps.storagePath;
                                  final pathForSlide =
                                      _muralStoragePathAlignedWithPhotoRef(
                                    photoRefRaw: refStr,
                                    pathFromFirestore: pathCombined,
                                  );
                                  return LayoutBuilder(
                                    builder: (ctx, c) {
                                      final w = c.maxWidth;
                                      final h = c.maxHeight;
                                      final dpr =
                                          MediaQuery.devicePixelRatioOf(ctx);
                                      return StableStorageImage(
                                        storagePath: pathForSlide,
                                        imageUrl: ps.imageUrl,
                                        gsUrl: ps.gsUrl,
                                        width: w,
                                        height: h,
                                        fit: BoxFit.cover,
                                        memCacheWidth:
                                            (w * dpr).round().clamp(64, 1400),
                                        memCacheHeight:
                                            (h * dpr).round().clamp(64, 1400),
                                        placeholder: YahwehPremiumFeedShimmer
                                            .mediaCover(),
                                        errorWidget:
                                            _brokenMuralMediaFallback(
                                                title,
                                                isEvento ? eventDateStr : '',
                                                isEvento),
                                        onLoadError: _muralImageLoadError,
                                      );
                                    },
                                  );
                                }
                                final vIdx = idx - photoCount;
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                      ThemeCleanPremium.radiusMd),
                                  child: _buildVideoBlockFromEntry(
                                    context,
                                    data,
                                    videoEntries[vIdx],
                                    title,
                                    isEvento,
                                    vIdx,
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _heartBurst,
                          builder: (_, __) {
                            final v = _heartBurst.value;
                            if (v < 0.02) return const SizedBox.shrink();
                            return Center(
                              child: Transform.scale(
                                scale: 0.45 +
                                    0.7 *
                                        Curves.elasticOut
                                            .transform(v.clamp(0.0, 1.0)),
                                child: Icon(
                                  Icons.favorite_rounded,
                                  size: 88,
                                  color: const Color(0xFFE11D48).withValues(
                                      alpha: 0.94 * (1.0 - v * 0.4)),
                                  shadows: const [
                                    Shadow(
                                        blurRadius: 18, color: Colors.black54),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    if (carouselLen > 1)
                      Positioned(
                        bottom: 10,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            carouselLen,
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
                    if (carouselLen > 1)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_carouselIndex + 1}/$carouselLen',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (carouselLen > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Deslize para o lado para ver todas as mídias.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          // Legenda: aviso com foto repete o título; evento usa só o texto longo (título na faixa)
          if (!isEvento && muralPhotos.isNotEmpty && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          if (text.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16,
                  (!isEvento && muralPhotos.isNotEmpty && title.isNotEmpty)
                      ? 0
                      : 12,
                  16,
                  4),
              child: SelectableText(
                text,
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade800,
                    height: 1.45,
                    fontWeight: FontWeight.w500),
              ),
            ),

          _MuralPostLinksRow(
            tenantId: widget.tenantId,
            churchSlug: widget.churchSlug,
            shareInviteUrl: shareInviteUrl,
            eventLocation: location,
            eventLat: locationLat,
            eventLng: locationLng,
          ),

          if (canRsvpEvento)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _rsvpBusy
                        ? null
                        : () => _togglePresencaEvento(
                              data: data,
                              currentlyConfirmed: rsvpConfirmed,
                              eventDt: eventDt,
                            ),
                    icon: Icon(
                      rsvpConfirmed
                          ? Icons.event_available_rounded
                          : Icons.event_outlined,
                      size: 20,
                    ),
                    label: Text(
                      rsvpConfirmed
                          ? 'Presença confirmada'
                          : 'Confirmar presença',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: rsvpConfirmed
                          ? ThemeCleanPremium.success.withValues(alpha: 0.12)
                          : const Color(0xFFEFF6FF),
                      foregroundColor: rsvpConfirmed
                          ? ThemeCleanPremium.success
                          : ThemeCleanPremium.primary,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusSm),
                      ),
                    ),
                  ),
                  if (rsvpCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '$rsvpCount ${rsvpCount == 1 ? 'pessoa confirmou' : 'pessoas confirmaram'} presença',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),

          // Local com link para mapa (quando há coordenadas)
          if (location.isNotEmpty || hasMapLocation)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  if (location.isNotEmpty) ...[
                    Icon(Icons.location_on_rounded,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(location,
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                  ],
                  if (hasMapLocation)
                    TextButton.icon(
                      onPressed: () {
                        final uri = Uri.parse(
                            'https://www.google.com/maps?q=$locationLat,$locationLng');
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text('Ver no mapa'),
                      style: TextButton.styleFrom(
                        foregroundColor: ThemeCleanPremium.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                ],
              ),
            ),

          // Actions (Instagram-like): curtir, comentar e compartilhar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(children: [
              IconButton(
                tooltip: liked ? 'Descurtir' : 'Curtir',
                onPressed: () => _toggleLike(liked: liked),
                icon: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked ? const Color(0xFFE11D48) : Colors.grey.shade700,
                  size: 22,
                ),
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
              Text('$likesCount',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Comentar',
                onPressed: _openCommentsSheet,
                icon: Icon(Icons.mode_comment_outlined,
                    color: Colors.grey.shade700, size: 22),
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
              Text('$commentsCount',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600)),
              IconButton(
                tooltip: 'Compartilhar',
                onPressed: () {
                  final origin = shareRectFromContext(context);
                  widget.onShare(origin);
                },
                icon: Icon(Icons.near_me_rounded,
                    color: Colors.grey.shade700, size: 22),
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
              IconButton(
                tooltip: 'Copiar texto',
                onPressed: () {
                  final d = widget.doc.data();
                  Clipboard.setData(ClipboardData(
                      text:
                          '${(d['title'] ?? '').toString()}\n${(d['text'] ?? '').toString()}'));
                  ScaffoldMessenger.of(context).showSnackBar(
                      ThemeCleanPremium.successSnackBar('Texto copiado!'));
                },
                icon: Icon(Icons.copy_rounded,
                    color: Colors.grey.shade700, size: 22),
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              ),
              if (carouselLen > 0)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: carouselLen > 1
                        ? () {
                            final mp = List<String>.from(muralPhotos);
                            final ve = videoEntries
                                .map((e) => Map<String, String>.from(e))
                                .toList();
                            Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (ctx) => _MuralFullscreenMediaPager(
                                  muralPhotos: mp,
                                  videoEntries: ve,
                                  initialIndex: _carouselIndex,
                                  photoSlideBuilder: (c, i) {
                                    final pathFs =
                                        eventNoticiaPhotoStoragePathAt(
                                            data, i);
                                    final ps =
                                        _muralStableParamsFromRef(mp[i]);
                                    final pathCombined =
                                        pathFs ?? ps.storagePath;
                                    final pathForSlide =
                                        _muralStoragePathAlignedWithPhotoRef(
                                      photoRefRaw: mp[i],
                                      pathFromFirestore: pathCombined,
                                    );
                                    return LayoutBuilder(
                                      builder: (ctx, box) {
                                        final w = box.maxWidth;
                                        final h = box.maxHeight;
                                        final dpr = MediaQuery.devicePixelRatioOf(
                                            ctx);
                                        return StableStorageImage(
                                          storagePath: pathForSlide,
                                          imageUrl: ps.imageUrl,
                                          gsUrl: ps.gsUrl,
                                          width: w,
                                          height: h,
                                          fit: BoxFit.contain,
                                          memCacheWidth: (w * dpr)
                                              .round()
                                              .clamp(64, 1440),
                                          memCacheHeight: (h * dpr)
                                              .round()
                                              .clamp(64, 1440),
                                          placeholder: YahwehPremiumFeedShimmer
                                              .mediaCover(),
                                          errorWidget:
                                              _brokenMuralMediaFallback(
                                            title,
                                            isEvento ? eventDateStr : '',
                                            isEvento,
                                          ),
                                          onLoadError: _muralImageLoadError,
                                        );
                                      },
                                    );
                                  },
                                  videoSlideBuilder: (c, vi) =>
                                      _buildVideoBlockFromEntry(
                                    c,
                                    data,
                                    ve[vi],
                                    title,
                                    isEvento,
                                    vi,
                                  ),
                                ),
                              ),
                            );
                          }
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          photoCount == 0
                              ? Icons.videocam_rounded
                              : (videoCount > 0
                                  ? Icons.collections_rounded
                                  : Icons.photo_library_rounded),
                          size: 14,
                          color: const Color(0xFF059669),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          mediaChipLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF059669),
                          ),
                        ),
                        if (carouselLen > 1) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.open_in_full_rounded,
                              size: 12, color: Colors.grey.shade600),
                        ],
                      ]),
                    ),
                  ),
                ),
              const Spacer(),
              if (createdAgo.isNotEmpty)
                Text('há $createdAgo',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Future<void> _openMuralPostVideoAt(BuildContext context, int slot) async {
    final data = widget.doc.data();
    final vids = eventNoticiaVideosFromDoc(data);
    if (vids.isEmpty) {
      await _openMuralPostVideoLegacy(context);
      return;
    }
    if (slot < 0 || slot >= vids.length) return;
    await _openMuralVideoFromEntry(context, vids[slot]);
  }

  Future<void> _openMuralVideoFromEntry(
      BuildContext context, Map<String, String> entry) async {
    var openUrl = sanitizeImageUrl(entry['videoUrl'] ?? '');
    if (openUrl.isEmpty) return;
    if (!openUrl.startsWith('http://') &&
        !openUrl.startsWith('https://') &&
        firebaseStorageMediaUrlLooksLike(openUrl)) {
      openUrl = (await AppStorageImageService.instance
              .resolveImageUrl(imageUrl: openUrl)) ??
          openUrl;
    }
    var thumbRaw = (entry['thumbUrl'] ?? '').toString().trim();
    if (thumbRaw.isEmpty) {
      thumbRaw = youtubeThumbnailUrlForVideoUrl(openUrl) ?? '';
    }
    final thumb = sanitizeImageUrl(thumbRaw);
    final hasThumb = isValidImageUrl(thumb);
    bool isYoutubeOrVimeo(String u) {
      final low = u.toLowerCase();
      return low.contains('youtube.com') ||
          low.contains('youtu.be') ||
          low.contains('vimeo.com');
    }

    if (isYoutubeOrVimeo(openUrl)) {
      final withScheme =
          openUrl.startsWith('http://') || openUrl.startsWith('https://')
              ? openUrl
              : 'https://$openUrl';
      final uri = Uri.tryParse(withScheme);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }
    final isHosted = looksLikeHostedVideoFileUrl(openUrl) ||
        openUrl.contains('firebasestorage.googleapis.com') ||
        openUrl.contains('.firebasestorage.app');
    if (isHosted) {
      if (!context.mounted) return;
      await showChurchHostedVideoDialog(
        context,
        videoUrl: openUrl,
        thumbnailUrl: hasThumb ? thumb : null,
        autoPlay: true,
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

  Future<void> _openMuralPostVideoLegacy(BuildContext context) async {
    final data = widget.doc.data();
    final hosted = eventNoticiaHostedVideoPlayUrl(data) ?? '';
    final ext = eventNoticiaExternalVideoUrl(data);
    final legacy = (data['videoUrl'] ?? '').toString().trim();
    final openUrl = hosted.isNotEmpty
        ? hosted
        : (ext != null && ext.isNotEmpty)
            ? ext
            : legacy;
    if (openUrl.isEmpty) return;
    await _openMuralVideoFromEntry(context, {
      'videoUrl': openUrl,
      'thumbUrl': eventNoticiaDisplayVideoThumbnailUrl(data) ?? '',
    });
  }

  Widget _buildVideoBlockFromEntry(
    BuildContext context,
    Map<String, dynamic> data,
    Map<String, String> entry,
    String title,
    bool isEvento,
    int slot,
  ) {
    var openUrl = sanitizeImageUrl(entry['videoUrl'] ?? '');
    if (openUrl.isEmpty) return _videoGradientFallback(isEvento, title);
    var thumbRaw = (entry['thumbUrl'] ?? '').toString().trim();
    if (thumbRaw.isEmpty) {
      thumbRaw = youtubeThumbnailUrlForVideoUrl(openUrl) ?? '';
    }
    if (thumbRaw.isEmpty) {
      thumbRaw = eventNoticiaDisplayVideoThumbnailUrl(data) ?? '';
    }
    final thumb = sanitizeImageUrl(thumbRaw);
    final hasThumb = isValidImageUrl(thumb);
    /// Web: MP4/Storage no feed — pré-carrega como no site público (URL ou caminho Storage).
    final webHostedPreview = kIsWeb &&
        openUrl.isNotEmpty &&
        (looksLikeHostedVideoFileUrl(openUrl) ||
            (!openUrl.startsWith('http://') &&
                !openUrl.startsWith('https://') &&
                firebaseStorageMediaUrlLooksLike(openUrl)));

    bool isYoutubeOrVimeo(String u) {
      final low = u.toLowerCase();
      return low.contains('youtube.com') ||
          low.contains('youtu.be') ||
          low.contains('vimeo.com');
    }

    Future<void> openVideo() async {
      if (openUrl.isEmpty) return;
      if (isYoutubeOrVimeo(openUrl)) {
        final withScheme =
            openUrl.startsWith('http://') || openUrl.startsWith('https://')
                ? openUrl
                : 'https://$openUrl';
        final uri = Uri.tryParse(withScheme);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        return;
      }
      final isHosted = looksLikeHostedVideoFileUrl(openUrl) ||
          openUrl.contains('firebasestorage.googleapis.com') ||
          openUrl.contains('.firebasestorage.app');
      if (isHosted) {
        if (!context.mounted) return;
        await showChurchHostedVideoDialog(
          context,
          videoUrl: openUrl,
          thumbnailUrl: hasThumb ? thumb : null,
          autoPlay: true,
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

    final normalized = openUrl.isEmpty
        ? ''
        : (openUrl.startsWith('http://') || openUrl.startsWith('https://')
            ? openUrl
            : (looksLikeHostedVideoFileUrl(openUrl)
                ? openUrl
                : 'https://$openUrl'));
    final isHostedFile = normalized.isNotEmpty &&
        !isYoutubeOrVimeo(normalized) &&
        (looksLikeHostedVideoFileUrl(openUrl) ||
            normalized.contains('firebasestorage.googleapis.com') ||
            normalized.contains('.firebasestorage.app'));

    if (webHostedPreview) {
      return ChurchPublicConstrainedMedia(
        child: Stack(
          fit: StackFit.expand,
          children: [
            PremiumHtmlFeedVideo(
              videoUrl: openUrl,
              visibilityKey: '${widget.doc.id}_v$slot',
              showControls: true,
              posterUrl: hasThumb ? thumb : null,
              startLoadingImmediately: true,
              onMostlyVisible: _onFeedVideoMostlyVisible,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: openVideo,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Toque para tela cheia no app/navegador',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w600,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black54)
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!kIsWeb && isHostedFile) {
      return ChurchPublicConstrainedMedia(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
          child: MuralInlineNativeVideo(
            videoUrl: normalized,
            visibilityKey: '${widget.doc.id}_v$slot',
            thumbnailUrl: hasThumb ? thumb : null,
            borderRadius: ThemeCleanPremium.radiusLg,
            onTapOpenFullscreen: () => openVideo(),
            onMostlyVisible: _onFeedVideoMostlyVisible,
          ),
        ),
      );
    }

    return ChurchPublicConstrainedMedia(
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg)),
        child: InkWell(
          onTap: openVideo,
          child: hasThumb
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 640,
                      memCacheHeight: 360,
                      placeholder: YahwehPremiumFeedShimmer.videoThumbDark(
                          isEvento: isEvento),
                      errorWidget: _videoGradientFallback(isEvento, title),
                      skipFreshDisplayUrl: false,
                      onLoadError: _muralImageLoadError,
                    ),
                    Container(color: Colors.black26),
                    const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            size: 48, color: Colors.white)),
                  ],
                )
              : _videoGradientFallback(isEvento, title),
        ),
      ),
    );
  }

  Color _muralChurchAccent() {
    final m = widget.tenantData;
    if (m == null || m.isEmpty) return ThemeCleanPremium.primary;
    for (final k in [
      'sitePrimaryHex',
      'sitePrimaryColor',
      'corSite',
      'primaryHex'
    ]) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isEmpty) continue;
      var s = v.replaceFirst('#', '').replaceAll(RegExp(r'\s'), '');
      if (s.length == 6) s = 'FF$s';
      if (s.length == 8) {
        final n = int.tryParse(s, radix: 16);
        if (n != null) return Color(n);
      }
    }
    return ThemeCleanPremium.primary;
  }

  /// Capa quando a URL falha (403/rede) ou está inválida — alinhado às cores do tenant.
  Widget _brokenMuralMediaFallback(
      String title, String dateStr, bool isEvento) {
    final accent = _muralChurchAccent();
    final blend = Color.lerp(accent, Colors.white, 0.32)!;
    return Container(
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.94),
            blend.withValues(alpha: 0.88),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isEvento ? Icons.event_rounded : Icons.article_rounded,
              color: Colors.white.withValues(alpha: 0.95),
              size: 52,
            ),
            const SizedBox(height: 10),
            Text(
              isEvento ? 'Evento' : 'Aviso',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            if (title.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (isEvento && dateStr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                dateStr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _videoGradientFallback(bool isEvento, String title) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEvento
              ? [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)]
              : [const Color(0xFF7C3AED), const Color(0xFFA78BFA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.play_circle_filled_rounded,
              color: Colors.white, size: 48),
          const SizedBox(height: 8),
          Text('Assistir vídeo',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                title,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95), fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactTitleStrip(String title, String dateStr, bool isEvento) {
    if (title.isEmpty && dateStr.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isEvento
              ? [
                  const Color(0xFF1E3A8A).withValues(alpha: 0.95),
                  const Color(0xFF2563EB).withValues(alpha: 0.9)
                ]
              : [
                  const Color(0xFF6D28D9).withValues(alpha: 0.95),
                  const Color(0xFF7C3AED).withValues(alpha: 0.88)
                ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isEvento ? Icons.event_rounded : Icons.campaign_rounded,
              color: Colors.white70, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        height: 1.2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (dateStr.isNotEmpty) ...[
                  if (title.isNotEmpty) const SizedBox(height: 4),
                  Text(dateStr,
                      style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context, List<String> images) {
    if (images.isEmpty) return;
    final i = _carouselIndex.clamp(0, images.length - 1);
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => _FullScreenGallery(images: images, initial: i)));
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

/// Galeria em tela cheia: mesmas páginas do carrossel (fotos + vídeos).
class _MuralFullscreenMediaPager extends StatefulWidget {
  final List<String> muralPhotos;
  final List<Map<String, String>> videoEntries;
  final int initialIndex;
  final Widget Function(BuildContext context, int photoIndex) photoSlideBuilder;
  final Widget Function(BuildContext context, int videoIndex) videoSlideBuilder;

  const _MuralFullscreenMediaPager({
    required this.muralPhotos,
    required this.videoEntries,
    required this.initialIndex,
    required this.photoSlideBuilder,
    required this.videoSlideBuilder,
  });

  @override
  State<_MuralFullscreenMediaPager> createState() =>
      _MuralFullscreenMediaPagerState();
}

class _MuralFullscreenMediaPagerState extends State<_MuralFullscreenMediaPager> {
  late final PageController _ctrl;
  late int _page;

  int get _total =>
      widget.muralPhotos.length + widget.videoEntries.length;

  @override
  void initState() {
    super.initState();
    final maxI = _total > 0 ? _total - 1 : 0;
    _page = widget.initialIndex.clamp(0, maxI);
    _ctrl = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        elevation: 0,
        title: _total > 1
            ? Text(
                '${_page + 1} / $_total',
                style: const TextStyle(fontSize: 15),
              )
            : const Text('Mídias'),
      ),
      body: PageView.builder(
        controller: _ctrl,
        onPageChanged: (p) => setState(() => _page = p),
        itemCount: _total,
        itemBuilder: (ctx, i) {
          if (i < widget.muralPhotos.length) {
            return ColoredBox(
              color: Colors.black,
              child: widget.photoSlideBuilder(ctx, i),
            );
          }
          final vi = i - widget.muralPhotos.length;
          return ColoredBox(
            color: Colors.black,
            child: widget.videoSlideBuilder(ctx, vi),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Full Screen Gallery (zoom/pan)
// ═══════════════════════════════════════════════════════════════════════════════
/// Imagem de galeria usando SafeNetworkImage (compatível com Firebase Storage).
class _ResilientGalleryImage extends StatelessWidget {
  final String imageUrl;
  const _ResilientGalleryImage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(
      child: Shimmer.fromColors(
        baseColor: Colors.white24,
        highlightColor: Colors.white38,
        period: const Duration(milliseconds: 1200),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
    final errorWidget = Center(
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
    );
    return SafeNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      placeholder: placeholder,
      errorWidget: errorWidget,
      onLoadError: _muralImageLoadError,
    );
  }
}

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: widget.images.length > 1
            ? Text('${_current + 1} / ${widget.images.length}',
                style: const TextStyle(fontSize: 14))
            : null,
      ),
      body: PhotoViewGallery.builder(
        scrollPhysics: const BouncingScrollPhysics(),
        pageController: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        builder: (context, i) {
          final url = widget.images[i];
          final valid = url.startsWith('http://') || url.startsWith('https://');
          if (!valid) {
            return PhotoViewGalleryPageOptions.customChild(
              child: Center(
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
              ),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.contained,
              initialScale: PhotoViewComputedScale.contained,
            );
          }
          return PhotoViewGalleryPageOptions.customChild(
            child: _ResilientGalleryImage(imageUrl: url.trim()),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3.2,
            initialScale: PhotoViewComputedScale.contained,
          );
        },
        backgroundDecoration: const BoxDecoration(color: Colors.black),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Formulário de Aviso/Evento — com suporte a MÚLTIPLAS FOTOS
// ═══════════════════════════════════════════════════════════════════════════════
/// Formulário de aviso/evento do mural — público para abertura a partir da busca global (shell).
class MuralAvisoEditorPage extends StatefulWidget {
  final String tenantId;
  final CollectionReference<Map<String, dynamic>> postsCollection;
  final DocumentSnapshot<Map<String, dynamic>>? doc;
  final String type;
  final String churchSlug;
  const MuralAvisoEditorPage({
    super.key,
    required this.tenantId,
    required this.postsCollection,
    this.doc,
    required this.type,
    required this.churchSlug,
  });

  @override
  State<MuralAvisoEditorPage> createState() => _MuralAvisoEditorPageState();
}

class _MuralAvisoEditorPageState extends State<MuralAvisoEditorPage> {
  late TextEditingController _title, _text, _videoUrl;
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
  final List<String> _newNames = [];
  DateTime? _date;
  TimeOfDay? _time;
  DateTime? _validUntil;
  bool _saving = false;
  bool _mediaPicking = false;

  /// Quando false, o post não aparece no site público (painel/app continuam).
  bool _publicSite = true;
  bool _buscandoCep = false;
  bool _useChurchLocation = false;
  String? _churchAddressText;
  double? _locationLat;
  double? _locationLng;

  static String _onlyDigits(String s) => s.replaceAll(RegExp(r'\D'), '');
  static String _formatCepDisplay(String digits) {
    final d = _onlyDigits(digits);
    if (d.length <= 5) return d;
    return '${d.substring(0, 5)}-${d.substring(5, d.length.clamp(5, 8))}';
  }

  @override
  void initState() {
    super.initState();
    final data = widget.doc?.data() ?? {};
    _title = TextEditingController(text: (data['title'] ?? '').toString());
    _text = TextEditingController(text: (data['text'] ?? '').toString());
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
        if (legacy.isNotEmpty) {
          _logradouro.text = legacy;
        }
      }
    }
    final lat = data['locationLat'];
    final lng = data['locationLng'];
    _locationLat = lat is num
        ? lat.toDouble()
        : (lat != null ? double.tryParse(lat.toString()) : null);
    _locationLng = lng is num
        ? lng.toDouble()
        : (lng != null ? double.tryParse(lng.toString()) : null);
    final urls = _PostCard.imageUrlsFromData(data);
    _existingUrls.addAll(urls);
    try {
      final dt = (data['startAt'] as Timestamp).toDate();
      _date = DateTime(dt.year, dt.month, dt.day);
      _time = TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {}
    try {
      final v = data['validUntil'];
      if (v is Timestamp) {
        _validUntil = v.toDate();
      }
    } catch (_) {}
    _publicSite = data['publicSite'] != false;
  }

  /// Monta o endereço completo a partir do doc da igreja (tenant).
  static String _buildEnderecoFromTenant(Map<String, dynamic> data) {
    final endereco = (data['endereco'] ?? '').toString().trim();
    if (endereco.isNotEmpty) {
      return endereco;
    }
    final rua = (data['rua'] ?? data['address'] ?? '').toString().trim();
    final bairro = (data['bairro'] ?? '').toString().trim();
    final cidade =
        (data['cidade'] ?? data['localidade'] ?? '').toString().trim();
    final estado = (data['estado'] ?? data['uf'] ?? '').toString().trim();
    final cep = (data['cep'] ?? '').toString().trim();
    final parts = <String>[];
    if (rua.isNotEmpty) {
      parts.add(rua);
    }
    if (bairro.isNotEmpty) {
      parts.add(bairro);
    }
    if (cidade.isNotEmpty && estado.isNotEmpty) {
      parts.add('$cidade - $estado');
    } else if (cidade.isNotEmpty) {
      parts.add(cidade);
    } else if (estado.isNotEmpty) {
      parts.add(estado);
    }
    if (cep.isNotEmpty) {
      parts.add('CEP $cep');
    }
    return parts.join(', ');
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
    try {
      final snap = await FirebaseFirestore.instance
          .collection('igrejas')
          .doc(widget.tenantId)
          .get();
      final data = snap.data() ?? {};
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
          _useChurchLocation = true;
          _churchAddressText = endereco;
          _locationLat = lat is num
              ? lat.toDouble()
              : (lat != null ? double.tryParse(lat.toString()) : null);
          _locationLng = lng is num
              ? lng.toDouble()
              : (lng != null ? double.tryParse(lng.toString()) : null);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar(
            'Endereço da igreja selecionado. Use “Definir por CEP / manual” para outro local.',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao carregar igreja: $e',
                  style: const TextStyle(color: Colors.white)),
              backgroundColor: ThemeCleanPremium.error),
        );
      }
    }
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    setState(() => _buscandoCep = true);
    try {
      final res = await http
          .get(Uri.parse('https://viacep.com.br/ws/$cep/json/'))
          .timeout(const Duration(seconds: 12));
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
              'CEP encontrado. Complete número, quadra/lote e referência se quiser.'),
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

  /// [allowDeleteSentinels] só com `set(..., SetOptions(merge: true))` ou `update`.
  /// `add()` rejeita [FieldValue.delete] — [cloud_firestore/invalid-argument] em `locationCep`.
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

  @override
  void dispose() {
    _title.dispose();
    _text.dispose();
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

  Future<void> _pickImages() async {
    setState(() => _mediaPicking = true);
    try {
      final files =
          await MediaHandlerService.instance.pickAndProcessMultipleImages();
      for (final f in files) {
        final bytes = await f.readAsBytes();
        if (!mounted) return;
        setState(() {
          _newImages.add(bytes);
          _newNames.add(f.name);
        });
      }
    } finally {
      if (mounted) setState(() => _mediaPicking = false);
    }
  }

  Future<void> _pickCamera() async {
    setState(() => _mediaPicking = true);
    try {
      final file = await MediaHandlerService.instance.pickAndProcessImage(
        source: ImageSource.camera,
      );
      if (file != null) {
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() {
          _newImages.add(bytes);
          _newNames.add(file.name);
        });
      }
    } finally {
      if (mounted) setState(() => _mediaPicking = false);
    }
  }

  List<String>? _muralPathsFromImageUrls(List<String> urls) {
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

  Future<String> _upload(Uint8List bytes, String postId, int slotIndex) async {
    final storagePath = widget.type == 'evento'
        ? ChurchStorageLayout.eventPostPhotoPath(
            widget.tenantId, postId, slotIndex)
        : ChurchStorageLayout.avisoPostPhotoPath(
            widget.tenantId, postId, slotIndex);
    return MediaUploadService.uploadBytesWithRetry(
      storagePath: storagePath,
      bytes: bytes,
      contentType: 'image/jpeg',
    );
  }

  double _aspectRatioFromImageBytes(Uint8List bytes) {
    try {
      final im = img.decodeImage(bytes);
      if (im == null || im.height <= 0) return 1.0;
      return (im.width / im.height).clamp(0.4, 2.3);
    } catch (_) {
      return 1.0;
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(ThemeCleanPremium.successSnackBar('Informe o título.'));
      return;
    }
    final docRef = widget.doc?.reference ?? widget.postsCollection.doc();
    final postId = docRef.id;
    setState(() => _saving = true);
    try {
      var allUrls = dedupeImageRefsByStorageIdentity(_existingUrls);
      if (_newImages.isNotEmpty) {
        final startSlot = allUrls.length;
        final uploaded = await Future.wait(
          List.generate(
            _newImages.length,
            (i) => _upload(_newImages[i], postId, startSlot + i),
          ),
        );
        allUrls = dedupeImageRefsByStorageIdentity([...allUrls, ...uploaded]);
      }
      var aspectRatio = 1.0;
      if (_newImages.isNotEmpty) {
        aspectRatio = _aspectRatioFromImageBytes(_newImages.first);
      }
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final displayName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'Administrador';
      final now = FieldValue.serverTimestamp();

      final firstUrl = allUrls.isNotEmpty ? allUrls[0] : '';
      if (_newImages.isEmpty && allUrls.isNotEmpty) {
        final prev = widget.doc?.data()?['media_info'];
        if (prev is Map) {
          final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
          if (oar is num) {
            aspectRatio = oar.toDouble().clamp(0.4, 2.3);
          }
        }
      }
      final hasVideo = _videoUrl.text.trim().isNotEmpty;

      final payload = <String, dynamic>{
        'type': widget.type,
        'title': _title.text.trim(),
        'text': _text.text.trim(),
        'imageUrl': firstUrl,
        'imageUrls': allUrls,
        'defaultImageUrl': firstUrl,
        'videoUrl': _videoUrl.text.trim(),
        'updatedAt': now,
        ..._locationFieldsForSave(allowDeleteSentinels: widget.doc != null),
      };
      if (firstUrl.isNotEmpty) {
        payload['imagemUrl'] = firstUrl;
        payload['imagem_url'] = firstUrl;
      } else if (widget.doc != null) {
        payload['imagemUrl'] = FieldValue.delete();
        payload['imagem_url'] = FieldValue.delete();
      }

      /// Só [url_original]: miniatura no Storage não é mais referenciada (evita confusão com `thumb_*` da extensão).
      if (allUrls.isNotEmpty) {
        payload['media_info'] = <String, dynamic>{
          'url_original': firstUrl,
          'aspect_ratio': aspectRatio,
          'tipo': hasVideo ? 'video' : 'image',
        };
      } else if (widget.doc != null) {
        payload['media_info'] = FieldValue.delete();
      }

      if (allUrls.isEmpty) {
        if (widget.doc != null) {
          payload['imageStoragePath'] = FieldValue.delete();
          payload['imageStoragePaths'] = FieldValue.delete();
        }
      } else {
        final paths = _muralPathsFromImageUrls(allUrls);
        if (paths != null && paths.isNotEmpty) {
          payload['imageStoragePath'] = paths.first;
          payload['imageStoragePaths'] = paths;
        }
      }

      if (widget.type == 'evento' && _date != null && _time != null) {
        final dt = DateTime(
            _date!.year, _date!.month, _date!.day, _time!.hour, _time!.minute);
        payload['startAt'] = Timestamp.fromDate(dt);
        payload['generated'] = false;
      }
      if (_validUntil != null) {
        payload['validUntil'] = Timestamp.fromDate(_validUntil!);
      }
      // Avisos são temporários: no site público só aparecem até 1 dia após a data predeterminada (ou criação).
      if (widget.type == 'aviso') {
        final refDate = _validUntil ?? DateTime.now();
        final expiresAt = refDate.add(const Duration(days: 1));
        payload['avisoExpiresAt'] = Timestamp.fromDate(expiresAt);
      }
      payload['publicSite'] = _publicSite;

      if (widget.type == 'evento' && widget.doc != null) {
        payload['imageVariants'] = FieldValue.delete();
      }
      if (widget.doc == null) {
        payload['createdAt'] = now;
        payload['createdByUid'] = uid;
        payload['createdByName'] = displayName;
        payload['likes'] = <String>[];
        payload['likedBy'] = <String>[];
        payload['rsvp'] = <String>[];
        payload['likesCount'] = 0;
        payload['rsvpCount'] = 0;
        payload['commentsCount'] = 0;
        await docRef.set(payload);
      } else {
        if (widget.type == 'evento') {
          payload['templateId'] = FieldValue.delete();
        }
        await widget.doc!.reference.set(payload, SetOptions(merge: true));
      }

      if (_newImages.isNotEmpty) {
        if (widget.type == 'aviso') {
          FirebaseStorageCleanupService.scheduleCleanupAfterAvisoPostImageUpload(
            tenantId: widget.tenantId,
            postDocId: postId,
          );
        } else if (widget.type == 'evento') {
          FirebaseStorageCleanupService.scheduleCleanupAfterEventPostImageUpload(
            tenantId: widget.tenantId,
            postDocId: postId,
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            ThemeCleanPremium.successSnackBar(
                widget.doc == null ? 'Publicado!' : 'Atualizado!'));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('Erro: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: ThemeCleanPremium.error));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEvento = widget.type == 'evento';
    final isMobile = ThemeCleanPremium.isMobile(context);
    final thumbSize = isMobile ? 80.0 : 100.0;
    final allPreviews = <Widget>[];
    for (var i = 0; i < _existingUrls.length; i++) {
      final idx = i;
      allPreviews.add(Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SafeNetworkImage(
            imageUrl: _existingUrls[idx],
            width: thumbSize,
            height: thumbSize,
            fit: BoxFit.cover,
            placeholder: Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(
                width: thumbSize,
                height: thumbSize,
                color: Colors.grey.shade200,
              ),
            ),
            errorWidget: Container(
                width: thumbSize,
                height: thumbSize,
                color: Colors.grey.shade300,
                child:
                    const Icon(Icons.broken_image_rounded, color: Colors.grey)),
            onLoadError: _muralImageLoadError,
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
                  child:
                      const Icon(Icons.close, size: 14, color: Colors.white)),
            )),
      ]));
    }
    for (var i = 0; i < _newImages.length; i++) {
      final idx = i;
      allPreviews.add(Stack(children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_newImages[idx],
                width: thumbSize, height: thumbSize, fit: BoxFit.cover)),
        Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => setState(() {
                _newImages.removeAt(idx);
                _newNames.removeAt(idx);
              }),
              child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.close, size: 14, color: Colors.white)),
            )),
      ]));
    }

    final padding = ThemeCleanPremium.pagePadding(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    final publishLabel =
        widget.doc != null ? 'Atualizar' : 'Publicar';
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
          tooltip: 'Voltar',
          style: IconButton.styleFrom(
            minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                ThemeCleanPremium.minTouchTarget),
          ),
        ),
        title: Text(widget.doc != null
            ? 'Editar ${isEvento ? 'Evento' : 'Aviso'}'
            : 'Novo ${isEvento ? 'Evento' : 'Aviso'}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(_saving ? 'Salvando...' : 'Publicar',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                minimumSize: const Size(ThemeCleanPremium.minTouchTarget,
                    ThemeCleanPremium.minTouchTarget),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Material(
        elevation: 12,
        shadowColor: const Color(0x40000000),
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              10,
              padding.right,
              10 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SizedBox(
              height: math.max(52, ThemeCleanPremium.minTouchTarget),
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.publish_rounded),
                label: Text(
                  _saving ? 'Publicando...' : publishLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: ThemeCleanPremium.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              padding.top,
              padding.right,
              padding.bottom + keyboardInset,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_mediaPicking || _saving)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              // FOTOS
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.photo_library_rounded,
                            color: ThemeCleanPremium.primary, size: 20),
                        const SizedBox(width: 8),
                        const Text('Fotos',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        const Spacer(),
                        Text(
                          '${_existingUrls.length + _newImages.length} foto(s)',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ...allPreviews,
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap:
                                (_mediaPicking || _saving) ? null : _pickImages,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: thumbSize,
                              height: thumbSize,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.green.shade400),
                              ),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate_rounded,
                                        color: Colors.green.shade700, size: 28),
                                    const SizedBox(height: 4),
                                    Text('Galeria',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green.shade700)),
                                  ]),
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap:
                                (_mediaPicking || _saving) ? null : _pickCamera,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: thumbSize,
                              height: thumbSize,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.green.shade400),
                              ),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.camera_alt_rounded,
                                        color: Colors.green.shade700, size: 28),
                                    const SizedBox(height: 4),
                                    Text('Câmera',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green.shade700)),
                                  ]),
                            ),
                          ),
                        ),
                      ]),
                    ]),
              ),
              const SizedBox(height: 16),

              // CAMPOS
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(ThemeCleanPremium.radiusMd),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                          controller: _title,
                          decoration: const InputDecoration(
                              labelText: 'Título *',
                              prefixIcon: Icon(Icons.title_rounded))),
                      const SizedBox(height: 14),
                      TextField(
                          controller: _text,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: 'Texto / Descrição',
                              prefixIcon: Icon(Icons.notes_rounded),
                              alignLabelWithHint: true)),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Icon(Icons.place_rounded,
                              size: 22,
                              color:
                                  ThemeCleanPremium.primary.withValues(alpha: 0.85)),
                          const SizedBox(width: 8),
                          Text('Local (opcional)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: Colors.grey.shade800)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'CEP preenche rua, bairro e cidade; complete número, quadra/lote e referência. Ou use o endereço da igreja.',
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
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text('Mapa no compartilhamento.',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.green.shade700)),
                                      ),
                                      TextButton.icon(
                                        onPressed: () {
                                          launchUrl(
                                              Uri.parse(
                                                  'https://www.google.com/maps?q=$_locationLat,$_locationLng'),
                                              mode: LaunchMode
                                                  .externalApplication);
                                        },
                                        icon: const Icon(Icons.map_rounded,
                                            size: 16),
                                        label: const Text('Abrir'),
                                      ),
                                    ],
                                  ),
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
                                      minimumSize: const Size(
                                          ThemeCleanPremium.minTouchTarget,
                                          ThemeCleanPremium.minTouchTarget),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _usarEnderecoIgreja,
                                    icon: const Icon(Icons.refresh_rounded,
                                        size: 18, color: Colors.white),
                                    label: const Text('Atualizar da igreja',
                                        style: TextStyle(color: Colors.white)),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green.shade700,
                                      minimumSize: const Size(
                                          ThemeCleanPremium.minTouchTarget,
                                          ThemeCleanPremium.minTouchTarget),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _cep,
                                keyboardType: TextInputType.number,
                                maxLength: 9,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'CEP',
                                  hintText: '00000-000',
                                  counterText: '',
                                  prefixIcon:
                                      const Icon(Icons.pin_drop_outlined),
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
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.search_rounded,
                                        size: 20, color: Colors.white),
                                label: Text(_buscandoCep ? '...' : 'Buscar CEP',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600)),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.primary,
                                  minimumSize: const Size(
                                      ThemeCleanPremium.minTouchTarget,
                                      ThemeCleanPremium.minTouchTarget),
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
                          onChanged: (_) => setState(() {}),
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
                          onChanged: (_) => setState(() {}),
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
                          onChanged: (_) => setState(() {}),
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
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  labelText: 'Cidade',
                                  prefixIcon:
                                      const Icon(Icons.location_city_rounded),
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
                                onChanged: (_) => setState(() {}),
                                textCapitalization:
                                    TextCapitalization.characters,
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
                          onChanged: (_) => setState(() {}),
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
                          onChanged: (_) => setState(() {}),
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Ponto de referência (opcional)',
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
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Resumo do local',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: Colors.grey.shade700)),
                              const SizedBox(height: 6),
                              Text(
                                _montarEnderecoManual().isEmpty
                                    ? '(preencha os campos acima)'
                                    : _montarEnderecoManual(),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  height: 1.4,
                                  color: _montarEnderecoManual().isEmpty
                                      ? Colors.grey.shade500
                                      : Colors.grey.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _usarEnderecoIgreja,
                          icon: const Icon(Icons.church_rounded,
                              size: 20, color: Colors.white),
                          label: const Text(
                              'Usar endereço da igreja (cadastro)',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            minimumSize: const Size(double.infinity,
                                ThemeCleanPremium.minTouchTarget),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                          controller: _videoUrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                              labelText: 'Link do vídeo (YouTube/Vimeo)',
                              prefixIcon: Icon(Icons.video_library_rounded),
                              hintText: 'https://...')),
                      const SizedBox(height: 14),
                      if (isEvento) ...[
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                              child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime(DateTime.now().year - 1),
                                  lastDate: DateTime(DateTime.now().year + 3),
                                  initialDate: _date ?? DateTime.now());
                              if (picked != null) {
                                setState(() => _date = picked);
                              }
                            },
                            icon: const Icon(Icons.event_rounded),
                            label: Text(_date == null
                                ? 'Data'
                                : '${_date!.day.toString().padLeft(2, '0')}/${_date!.month.toString().padLeft(2, '0')}/${_date!.year}'),
                          )),
                          const SizedBox(width: 10),
                          Expanded(
                              child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _time ?? TimeOfDay.now());
                              if (picked != null) {
                                setState(() => _time = picked);
                              }
                            },
                            icon: const Icon(Icons.schedule_rounded),
                            label: Text(_time == null
                                ? 'Hora'
                                : _time!.format(context)),
                          )),
                        ]),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
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
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                        minWidth: 120,
                                        minHeight:
                                            ThemeCleanPremium.minTouchTarget),
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          firstDate: DateTime.now(),
                                          lastDate:
                                              DateTime(DateTime.now().year + 5),
                                          initialDate: _validUntil ??
                                              DateTime.now().add(
                                                  const Duration(days: 30)),
                                        );
                                        if (picked != null) {
                                          setState(() => _validUntil = picked);
                                        }
                                      },
                                      icon: const Icon(
                                          Icons.calendar_today_rounded,
                                          size: 18),
                                      label: Text(
                                          _validUntil == null
                                              ? 'Permanente'
                                              : DateFormat('dd/MM/yyyy')
                                                  .format(_validUntil!),
                                          overflow: TextOverflow.ellipsis),
                                      style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(120,
                                              ThemeCleanPremium.minTouchTarget),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12)),
                                    ),
                                  ),
                                ),
                                if (_validUntil != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Remover data de validade',
                                    onPressed: () =>
                                        setState(() => _validUntil = null),
                                    icon: const Icon(Icons.close_rounded),
                                    style: IconButton.styleFrom(
                                        minimumSize: const Size(
                                            ThemeCleanPremium.minTouchTarget,
                                            ThemeCleanPremium.minTouchTarget)),
                                  ),
                                ],
                              ]),
                            ]),
                      ),
                      if (!isEvento)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Avisos são temporários: no site público ficam visíveis até 1 dia após a data de validade (ou da publicação). No painel continuam visíveis.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                height: 1.3),
                          ),
                        ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _publicSite,
                        onChanged: (v) => setState(() => _publicSite = v),
                        title: const Text('Publicar no site público'),
                        subtitle: Text(
                          _publicSite
                              ? 'Visível em gestaoyahweh.com.br/{slug} com curtidas e comentários.'
                              : 'Oculto no site; permanece no painel e no app.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                        secondary: Icon(Icons.public_rounded,
                            color: ThemeCleanPremium.primary),
                      ),
                    ]),
              ),
              SizedBox(height: 88 + MediaQuery.paddingOf(context).bottom),
            ]),
      ),
    );
  }
}
