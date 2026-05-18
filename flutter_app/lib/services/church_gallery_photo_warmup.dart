import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_member_profile_photo.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show isValidImageUrl, preloadNetworkImages, sanitizeImageUrl;

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

/// Pré-resolve URLs de miniatura no Storage e pré-carrega decode — lista mais rápida.
abstract final class ChurchGalleryPhotoWarmup {
  ChurchGalleryPhotoWarmup._();

  static DateTime? _lastRun;
  static String _lastKey = '';

  static Future<void> schedule({
    required BuildContext context,
    required String tenantId,
    required Iterable<ChurchGalleryMemberPhotoRef> members,
    int maxMembers = 28,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty || !context.mounted) return;

    final list = members.take(maxMembers).toList();
    if (list.isEmpty) return;

    final key = '$tid:${list.map((e) => e.memberDocId).join(',')}';
    final now = DateTime.now();
    if (_lastKey == key &&
        _lastRun != null &&
        now.difference(_lastRun!) < const Duration(seconds: 40)) {
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
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!context.mounted) return;

    final urls = <String>[];
    const batch = 6;
    for (var i = 0; i < list.length; i += batch) {
      if (!context.mounted) return;
      final slice = list.sublist(
        i,
        i + batch > list.length ? list.length : i + batch,
      );
      final batchUrls = await Future.wait(
        slice.map((ref) async {
          final md = ref.memberData;
          final nome = md != null
              ? (md['NOME_COMPLETO'] ?? md['nome'] ?? md['name'] ?? '')
                  .toString()
                  .trim()
              : null;
          final u = await FirebaseStorageService.getMemberProfilePhotoDownloadUrl(
            tenantId: tenantId,
            memberId: ref.memberDocId,
            cpfDigits: ref.cpfDigits,
            authUid: ref.authUid,
            nomeCompleto:
                (nome == null || nome.isEmpty) ? null : nome,
            memberFirestoreHint: md,
            preferListThumbnail: true,
          );
          return u != null ? sanitizeImageUrl(u) : '';
        }),
      );
      for (final u in batchUrls) {
        if (u.isNotEmpty && isValidImageUrl(u)) urls.add(u);
      }
    }

    if (!context.mounted || urls.isEmpty) return;
    await preloadNetworkImages(context, urls, maxItems: urls.length);
  }
}
