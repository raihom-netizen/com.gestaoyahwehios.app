import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Cache `_panel_cache/media_prefetch` — URLs de logo e fotos já resolvidas no servidor.
abstract final class PanelMediaPrefetchService {
  PanelMediaPrefetchService._();

  static DocumentReference<Map<String, dynamic>> _ref(String tenantId) =>
                ChurchOperationalPaths.churchDoc(tenantId.trim())
          .collection('_panel_cache')
          .doc('media_prefetch');

  static Future<Map<String, dynamic>?> readOnce(String tenantId) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return null;
    try {
      final snap = await _ref(tid).get();
      if (!snap.exists) return null;
      return snap.data();
    } catch (_) {
      return null;
    }
  }

  static Stream<Map<String, dynamic>?> watch(String tenantId) {
    final tid = tenantId.trim();
    if (tid.isEmpty) {
      return const Stream<Map<String, dynamic>?>.empty();
    }
    return _ref(tid).watchSafe()
        .map((s) => s.exists ? s.data() : null);
  }

  /// Preenche caches RAM do cliente — evita rajada de `getDownloadURL` na lista.
  static Future<void> applyToUrlCaches(
    String tenantId, {
    Map<String, dynamic>? raw,
    Map<String, dynamic>? tenantData,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;

    final data = raw ?? await readOnce(tid);
    if (data == null || data.isEmpty) return;

    final logo = (data['churchLogoUrl'] ?? '').toString().trim();
    if (logo.startsWith('http')) {
      FirebaseStorageService.seedChurchLogoDownloadUrl(
        tid,
        logo,
        tenantData: tenantData,
      );
    }

    final members = data['memberPhotoUrls'];
    if (members is! Map) return;

    for (final e in members.entries) {
      final id = e.key.toString().trim();
      final url = (e.value ?? '').toString().trim();
      if (id.isEmpty || !url.startsWith('http')) continue;
      FirebaseStorageService.seedMemberProfilePhotoDownloadUrl(
        tenantId: tid,
        memberId: id,
        downloadUrl: url,
        preferListThumbnail: true,
      );
      FirebaseStorageService.seedMemberProfilePhotoDownloadUrl(
        tenantId: tid,
        memberId: id,
        downloadUrl: url,
        preferListThumbnail: false,
      );
    }
  }
}
