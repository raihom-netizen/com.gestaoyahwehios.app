import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show eventNoticiaPhotoUrls;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_chat_member_photo_map.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_media_prefetch_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        MemberProfilePhotoBytesCache,
        dedupeImageRefsByStorageIdentity,
        firebaseStorageBytesFromDownloadUrl,
        imageUrlFromMap,
        isValidImageUrl,
        preloadNetworkImages,
        sanitizeImageUrl;

/// Referência mínima para aquecer fotos da galeria (líderes / corpo administrativo).
class ChurchGalleryMemberPhotoRef {
  final String memberDocId;
  final Map<String, dynamic>? memberData;
  final String? cpfDigits;
  final String? authUid;

  const ChurchGalleryMemberPhotoRef({
    required this.memberDocId,
    this.memberData,
    this.cpfDigits,
    this.authUid,
  });
}

/// Pré-resolve URLs e bytes (RAM + disco) — painel, avisos, eventos, chat e galerias.
abstract final class ChurchGalleryPhotoWarmup {
  ChurchGalleryPhotoWarmup._();

  static DateTime? _lastRun;
  static String _lastKey = '';
  static const int _listMaxBytes = 112 * 1024;
  static const int _feedMaxBytes = 512 * 1024;
  static const int _parallelMembers = 22;

  static List<ChurchGalleryMemberPhotoRef> _refsFromPanel(
    PanelDashboardSnapshot panel,
  ) {
    final refs = <ChurchGalleryMemberPhotoRef>[];
    final seen = <String>{};
    void addLite(PanelHomeMemberLite lite) {
      if (lite.memberDocId.isEmpty || seen.contains(lite.memberDocId)) return;
      seen.add(lite.memberDocId);
      refs.add(
        ChurchGalleryMemberPhotoRef(
          memberDocId: lite.memberDocId,
          memberData: lite.toMemberDataMap(),
          cpfDigits: lite.cpfDigits,
          authUid: lite.authUid,
        ),
      );
    }

    for (final lite in panel.homeLeaders) {
      addLite(lite);
    }
    for (final lite in panel.homeCorpoAdmin) {
      addLite(lite);
    }
    for (final lite in panel.birthdaysToday) {
      addLite(lite);
    }
    for (final lite in panel.birthdaysWeek.take(24)) {
      addLite(lite);
    }
    for (final lite in panel.birthdaysMonth.take(16)) {
      addLite(lite);
    }
    return refs;
  }

  /// Sem [BuildContext] — chamado no login / shell antes do 1.º frame do painel.
  static Future<void> warmBytesForPanel({
    required String tenantId,
    required PanelDashboardSnapshot panel,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    try {
      await ensureFirebaseInitialized();
    } catch (_) {}

    final refs = _refsFromPanel(panel);
    if (refs.isNotEmpty) {
      await _warmMembersParallel(tid, refs.take(96).toList());
    }

    final feedUrls = <String>[];
    for (final a in panel.homeAvisos.take(8)) {
      final u = sanitizeImageUrl(a.coverPhotoUrl ?? '');
      if (isValidImageUrl(u)) feedUrls.add(u);
    }
    for (final raw in panel.recentEventos.take(6)) {
      for (final u in eventNoticiaPhotoUrls(raw)) {
        final s = sanitizeImageUrl(u);
        if (isValidImageUrl(s)) feedUrls.add(s);
      }
    }
    for (final raw in panel.upcomingEventos.take(6)) {
      for (final u in eventNoticiaPhotoUrls(raw)) {
        final s = sanitizeImageUrl(u);
        if (isValidImageUrl(s)) feedUrls.add(s);
      }
    }
    await warmBytesForUrls(feedUrls, maxItems: 24, maxBytes: _feedMaxBytes);
  }

  /// URLs já resolvidas no servidor (`_panel_cache/media_prefetch`).
  static Future<void> warmBytesFromMediaPrefetch(
    String tenantId,
    Map<String, dynamic>? raw,
  ) async {
    final tid = tenantId.trim();
    if (tid.isEmpty || raw == null || raw.isEmpty) return;
    await PanelMediaPrefetchService.applyToUrlCaches(tid, raw: raw);

    final urls = <String>[];
    final logo = (raw['churchLogoUrl'] ?? '').toString().trim();
    if (logo.startsWith('http')) urls.add(logo);

    final members = raw['memberPhotoUrls'];
    if (members is Map) {
      for (final e in members.entries) {
        final url = (e.value ?? '').toString().trim();
        if (url.startsWith('http')) urls.add(url);
      }
    }
    await warmBytesForUrls(urls, maxItems: 120, maxBytes: _listMaxBytes);
  }

  /// Chat igreja — avatares visíveis na lista de conversas.
  static void warmBytesForChatRefs(
    String tenantId,
    Iterable<ChurchChatMemberRef> refs, {
    int maxItems = 48,
  }) {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final list = <ChurchGalleryMemberPhotoRef>[];
    for (final r in refs.take(maxItems)) {
      if (r.memberId.isEmpty) continue;
      list.add(
        ChurchGalleryMemberPhotoRef(
          memberDocId: r.memberId,
          memberData: r.data,
          authUid: r.authUid,
        ),
      );
    }
    if (list.isEmpty) return;
    unawaited(_warmMembersParallel(tid, list));
  }

  /// Capas de avisos/eventos e URLs soltas (sem resolver membro).
  static Future<void> warmBytesForUrls(
    Iterable<String> urls, {
    int maxItems = 48,
    int maxBytes = _feedMaxBytes,
  }) async {
    try {
      await ensureFirebaseInitialized();
    } catch (_) {}

    final cleaned = dedupeImageRefsByStorageIdentity(urls)
        .map(sanitizeImageUrl)
        .where((u) => isValidImageUrl(u))
        .take(maxItems)
        .toList();
    if (cleaned.isEmpty) return;

    await _warmUrlsParallel(cleaned, maxBytes: maxBytes);
  }

  /// Líderes + corpo administrativo do `_panel_cache` — prioridade ao abrir o painel.
  static void schedulePanelHome({
    required BuildContext context,
    required String tenantId,
    required PanelDashboardSnapshot panel,
    bool force = true,
  }) {
    final refs = _refsFromPanel(panel);
    if (refs.isEmpty) return;
    schedule(
      context: context,
      tenantId: tenantId,
      members: refs,
      maxMembers: 96,
      highPriority: true,
      force: force,
    );
    unawaited(warmBytesForPanel(tenantId: tenantId, panel: panel));
  }

  /// Lista de membros (`_panel_cache/members_directory`) — fotos antes do scroll.
  static void scheduleMembersDirectory({
    required BuildContext context,
    required String tenantId,
    required MembersDirectorySnapshot directory,
    int maxMembers = 80,
  }) {
    if (!directory.hasEntries) return;
    final refs = directory.entries
        .take(maxMembers)
        .map(
          (e) => ChurchGalleryMemberPhotoRef(
            memberDocId: e.memberDocId,
            memberData: e.toMemberDataMap(),
            cpfDigits: e.cpfDigits,
            authUid: e.authUid,
          ),
        )
        .toList();
    schedule(
      context: context,
      tenantId: tenantId,
      members: refs,
      maxMembers: maxMembers,
      highPriority: true,
      force: true,
    );
    unawaited(
      _warmMembersParallel(tenantId.trim(), refs),
    );
  }

  static Future<void> schedule({
    required BuildContext context,
    required String tenantId,
    required Iterable<ChurchGalleryMemberPhotoRef> members,
    int maxMembers = 28,
    bool highPriority = false,
    bool force = false,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty || !context.mounted) return;

    final list = members.take(maxMembers).toList();
    if (list.isEmpty) return;

    final key = '$tid:${list.map((e) => e.memberDocId).join(',')}';
    final now = DateTime.now();
    final debounce = highPriority
        ? const Duration(seconds: 2)
        : const Duration(seconds: 25);
    if (!force &&
        _lastKey == key &&
        _lastRun != null &&
        now.difference(_lastRun!) < debounce) {
      return;
    }
    _lastKey = key;
    _lastRun = now;

    unawaited(_run(context, tid, list));
  }

  static Future<void> _warmMembersParallel(
    String tenantId,
    List<ChurchGalleryMemberPhotoRef> list,
  ) async {
    if (list.isEmpty) return;
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= list.length) return;
        await _warmOne(tenantId, list[i]);
      }
    }
    final workers = list.length < _parallelMembers
        ? list.length
        : _parallelMembers;
    if (workers < 1) return;
    await Future.wait(List.generate(workers, (_) => worker()));
  }

  static Future<void> _warmUrlsParallel(
    List<String> urls, {
    required int maxBytes,
  }) async {
    var index = 0;
    Future<void> worker() async {
      while (true) {
        final i = index++;
        if (i >= urls.length) return;
        await _warmUrlBytes(urls[i], maxBytes: maxBytes);
      }
    }
    final workers = urls.length < 16 ? urls.length : 16;
    if (workers < 1) return;
    await Future.wait(List.generate(workers, (_) => worker()));
  }

  static Future<void> _warmUrlBytes(String url, {required int maxBytes}) async {
    final clean = sanitizeImageUrl(url);
    if (!isValidImageUrl(clean)) return;
    if (MemberProfilePhotoBytesCache.get(clean) != null) return;
    try {
      final bytes = await firebaseStorageBytesFromDownloadUrl(
        clean,
        maxBytes: maxBytes,
        skipFreshDisplayUrl: true,
      );
      if (bytes != null && bytes.length > 24) {
        MemberProfilePhotoBytesCache.put(clean, bytes);
      }
    } catch (_) {}
  }

  static Future<void> _run(
    BuildContext context,
    String tenantId,
    List<ChurchGalleryMemberPhotoRef> list,
  ) async {
    try {
      await ensureFirebaseInitialized();
    } catch (_) {}

    await _warmMembersParallel(tenantId, list);

    if (!context.mounted) return;
    final urls = <String>[];
    for (final ref in list) {
      final md = ref.memberData;
      if (md == null) continue;
      final u = sanitizeImageUrl(imageUrlFromMap(md));
      if (u.isNotEmpty && isValidImageUrl(u)) urls.add(u);
    }
    if (urls.isNotEmpty) {
      await preloadNetworkImages(
        context,
        urls,
        maxItems: urls.length.clamp(1, 96),
      );
    }
  }

  static Future<void> _warmOne(
    String tenantId,
    ChurchGalleryMemberPhotoRef ref,
  ) async {
    final md = ref.memberData;
    final nome = md != null
        ? (md['NOME_COMPLETO'] ?? md['nome'] ?? md['name'] ?? '')
            .toString()
            .trim()
        : null;

    String? url;
    if (md != null) {
      final fromDoc = sanitizeImageUrl(imageUrlFromMap(md));
      if (isValidImageUrl(fromDoc)) {
        url = fromDoc;
      }
    }

    url ??= FirebaseStorageService.peekMemberProfilePhotoDownloadUrl(
      tenantId: tenantId,
      memberId: ref.memberDocId,
      cpfDigits: ref.cpfDigits,
      authUid: ref.authUid,
      nomeCompleto: (nome == null || nome.isEmpty) ? null : nome,
      memberFirestoreHint: md,
      preferListThumbnail: true,
    );

    url ??= await FirebaseStorageService.getMemberProfilePhotoDownloadUrl(
      tenantId: tenantId,
      memberId: ref.memberDocId,
      cpfDigits: ref.cpfDigits,
      authUid: ref.authUid,
      nomeCompleto: (nome == null || nome.isEmpty) ? null : nome,
      memberFirestoreHint: md,
      preferListThumbnail: true,
    );

    final clean = url != null ? sanitizeImageUrl(url) : '';
    if (clean.isEmpty || !isValidImageUrl(clean)) return;

    if (MemberProfilePhotoBytesCache.get(clean) != null) return;

    Uint8List? bytes;
    try {
      bytes = await firebaseStorageBytesFromDownloadUrl(
        clean,
        maxBytes: _listMaxBytes,
        skipFreshDisplayUrl: true,
      );
    } catch (_) {
      bytes = null;
    }
    if (bytes != null && bytes.length > 24) {
      MemberProfilePhotoBytesCache.put(clean, bytes);
    }
  }
}
