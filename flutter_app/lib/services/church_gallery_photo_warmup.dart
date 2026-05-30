import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/members_directory_snapshot_service.dart';
import 'package:gestao_yahweh/services/panel_dashboard_snapshot_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        MemberProfilePhotoBytesCache,
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

/// Pré-resolve URLs e bytes (RAM) — listas de líderes / corpo admin abrem com foto visível.
abstract final class ChurchGalleryPhotoWarmup {
  ChurchGalleryPhotoWarmup._();

  static DateTime? _lastRun;
  static String _lastKey = '';
  static const int _listMaxBytes = 112 * 1024;

  /// Líderes + corpo administrativo do `_panel_cache` — prioridade ao abrir o painel.
  static void schedulePanelHome({
    required BuildContext context,
    required String tenantId,
    required PanelDashboardSnapshot panel,
  }) {
    final refs = <ChurchGalleryMemberPhotoRef>[];
    final seen = <String>{};
    void addLite(PanelHomeMemberLite lite) {
      if (lite.memberDocId.isEmpty || seen.contains(lite.memberDocId)) return;
      seen.add(lite.memberDocId);
      final data = lite.toMemberDataMap();
      refs.add(
        ChurchGalleryMemberPhotoRef(
          memberDocId: lite.memberDocId,
          memberData: data,
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
    for (final lite in panel.birthdaysWeek.take(12)) {
      addLite(lite);
    }
    for (final lite in panel.birthdaysMonth.take(8)) {
      addLite(lite);
    }
    if (refs.isEmpty) return;
    schedule(
      context: context,
      tenantId: tenantId,
      members: refs,
      maxMembers: 64,
      highPriority: true,
    );
  }

  /// Lista de membros (`_panel_cache/members_directory`) — fotos antes do scroll.
  static void scheduleMembersDirectory({
    required BuildContext context,
    required String tenantId,
    required MembersDirectorySnapshot directory,
    int maxMembers = 64,
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
    );
  }

  static Future<void> schedule({
    required BuildContext context,
    required String tenantId,
    required Iterable<ChurchGalleryMemberPhotoRef> members,
    int maxMembers = 28,
    bool highPriority = false,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty || !context.mounted) return;

    final list = members.take(maxMembers).toList();
    if (list.isEmpty) return;

    final key = '$tid:${list.map((e) => e.memberDocId).join(',')}';
    final now = DateTime.now();
    final debounce = highPriority
        ? const Duration(seconds: 8)
        : const Duration(seconds: 40);
    if (!highPriority &&
        _lastKey == key &&
        _lastRun != null &&
        now.difference(_lastRun!) < debounce) {
      return;
    }
    _lastKey = key;
    _lastRun = now;

    unawaited(_run(context, tid, list));
  }

  static Future<void> _run(
    BuildContext context,
    String tenantId,
    List<ChurchGalleryMemberPhotoRef> list,
  ) async {
    try {
      await ensureFirebaseInitialized();
    } catch (_) {}

    const batchRefs = 12;
    for (var i = 0; i < list.length; i += batchRefs) {
      if (!context.mounted) return;
      final slice = list.sublist(
        i,
        i + batchRefs > list.length ? list.length : i + batchRefs,
      );
      await Future.wait(slice.map((ref) => _warmOne(tenantId, ref)));
    }

    if (!context.mounted) return;
    final urls = <String>[];
    for (final ref in list) {
      final md = ref.memberData;
      if (md == null) continue;
      final u = sanitizeImageUrl(imageUrlFromMap(md));
      if (u.isNotEmpty && isValidImageUrl(u)) urls.add(u);
    }
    if (urls.isNotEmpty) {
      await preloadNetworkImages(context, urls, maxItems: urls.length);
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

    final cached = MemberProfilePhotoBytesCache.get(clean);
    if (cached != null && cached.length > 24) return;

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
