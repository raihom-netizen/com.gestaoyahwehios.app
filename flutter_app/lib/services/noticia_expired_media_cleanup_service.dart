import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        imageUrlsFromVariantMap,
        isFirebaseStorageHttpUrl,
        isValidImageUrl,
        sanitizeImageUrl;

/// Remove do Storage (e o documento no Firestore) publicações com **vencimento passado**
/// (`avisoExpiresAt` ou `validUntil`). Publicações **sem** esses campos não são tocadas.
///
/// Executado quando gestor/adm/master abre o mural (várias levas se houver muitos vencidos).
class NoticiaExpiredMediaCleanupService {
  NoticiaExpiredMediaCleanupService._();

  static Future<void> runOnceForTenant(String tenantId) async {
    final t = tenantId.trim();
    if (t.isEmpty) return;
    try {
      await _run(t);
    } catch (e, st) {
      debugPrint('NoticiaExpiredMediaCleanupService: $e\n$st');
    }
  }

  static bool _isExpired(Map<String, dynamic> data, DateTime now) {
    final vu = data['validUntil'];
    if (vu is Timestamp && !vu.toDate().isAfter(now)) return true;
    final ae = data['avisoExpiresAt'];
    if (ae is Timestamp && !ae.toDate().isAfter(now)) return true;
    return false;
  }

  static void _addUrl(Set<String> sink, String? raw) {
    final s = sanitizeImageUrl(raw ?? '');
    if (s.isEmpty || !isValidImageUrl(s)) return;
    if (!isFirebaseStorageHttpUrl(s)) return;
    sink.add(s);
  }

  static void _collectStorageTargets(Map<String, dynamic> data, Set<String> sink) {
    for (final u in eventNoticiaPhotoUrls(data)) {
      _addUrl(sink, u);
    }
    for (final m in eventNoticiaVideosFromDoc(data)) {
      _addUrl(sink, m['videoUrl']?.toString());
      _addUrl(sink, m['thumbUrl']?.toString());
    }
    for (final u in imageUrlsFromVariantMap(data['imageVariants'])) {
      _addUrl(sink, u);
    }
    for (final u in imageUrlsFromVariantMap(data['fotoVariants'])) {
      _addUrl(sink, u);
    }
    final isp = eventNoticiaImageStoragePath(data);
    if (isp != null && isp.isNotEmpty) sink.add(isp);
    final tsp = eventNoticiaThumbStoragePath(data);
    if (tsp != null && tsp.isNotEmpty) sink.add(tsp);
    final paths = data['imageStoragePaths'];
    if (paths is List) {
      for (final e in paths) {
        final p = e?.toString().trim() ?? '';
        if (p.isNotEmpty) sink.add(p);
      }
    }
    for (final k in [
      'imageStoragePath',
      'coverStoragePath',
      'thumbStoragePath',
      'videoStoragePath',
    ]) {
      final p = (data[k] ?? '').toString().trim();
      if (p.isNotEmpty && !p.startsWith('http')) sink.add(p);
    }
  }

  static Future<void> _deleteSubcollections(
      DocumentReference<Map<String, dynamic>> docRef) async {
    for (final sub in ['comentarios', 'curtidas', 'confirmacoes']) {
      while (true) {
        final q = await docRef.collection(sub).limit(120).get();
        if (q.docs.isEmpty) break;
        for (final d in q.docs) {
          try {
            await d.reference.delete();
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> _purgeDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) async {
    final data = doc.data();
    if (data == null) return;
    final now = DateTime.now();
    if (!_isExpired(data, now)) return;

    final sink = <String>{};
    _collectStorageTargets(data, sink);
    await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(sink);

    await _deleteSubcollections(doc.reference);
    try {
      await doc.reference.delete();
    } catch (e) {
      debugPrint('NoticiaExpiredMediaCleanupService.delete doc ${doc.id}: $e');
    }
  }

  static Future<void> _purgeCollection(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    final now = Timestamp.now();

    Future<void> handle(
        QuerySnapshot<Map<String, dynamic>> snap, Set<String> seen) async {
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue;
        await _purgeDoc(doc);
      }
    }

    for (var round = 0; round < 8; round++) {
      final seen = <String>{};
      final q1 =
          await col.where('avisoExpiresAt', isLessThan: now).limit(30).get();
      final q2 =
          await col.where('validUntil', isLessThan: now).limit(30).get();
      if (q1.docs.isEmpty && q2.docs.isEmpty) break;
      await handle(q1, seen);
      await handle(q2, seen);
    }
  }

  static Future<void> _run(String tenantId) async {
    final base = FirebaseFirestore.instance.collection('igrejas').doc(tenantId);
    await _purgeCollection(
        base.collection(ChurchTenantPostsCollections.noticias));
    await _purgeCollection(base.collection(ChurchTenantPostsCollections.avisos));
  }
}
