import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_canonical_media_delete_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Modelo leve para UI — aviso publicado na igreja.
class ChurchAvisoItem {
  const ChurchAvisoItem({
    required this.id,
    required this.title,
    required this.body,
    required this.imageUrls,
    required this.createdAt,
    required this.permanent,
    this.expiresAt,
    this.authorName = '',
  });

  final String id;
  final String title;
  final String body;
  final List<String> imageUrls;
  final DateTime? createdAt;
  final bool permanent;
  final DateTime? expiresAt;
  final String authorName;

  bool get hasImages => imageUrls.isNotEmpty;

  factory ChurchAvisoItem.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final urls = <String>[];
    void addUrl(dynamic raw) {
      final t = (raw ?? '').toString().trim();
      if (t.isNotEmpty && !urls.contains(t)) urls.add(t);
    }

    final list = m['imageUrls'];
    if (list is List) {
      for (final e in list) {
        addUrl(e);
      }
    }
    addUrl(m['imageUrl']);
    addUrl(m['coverPhotoUrl']);
    addUrl(m['fotoUrl']);

    DateTime? created;
    final c = m['createdAt'];
    if (c is Timestamp) created = c.toDate();

    DateTime? exp;
    final e1 = m['avisoExpiresAt'] ?? m['validUntil'];
    if (e1 is Timestamp) exp = e1.toDate();

    return ChurchAvisoItem(
      id: d.id,
      title: (m['title'] ?? m['titulo'] ?? '').toString().trim(),
      body: (m['body'] ?? m['text'] ?? m['mensagem'] ?? '').toString().trim(),
      imageUrls: urls,
      createdAt: created,
      permanent: m['permanent'] == true || exp == null,
      expiresAt: exp,
      authorName: (m['authorName'] ?? m['autor'] ?? '').toString().trim(),
    );
  }
}

/// Publicação, exclusão e expiração de avisos — `igrejas/{churchId}/avisos`.
abstract final class ChurchAvisosService {
  ChurchAvisosService._();

  static const int kMaxPhotos = 3;

  static String churchId(String hint) => ChurchRepository.churchId(hint.trim());

  static bool canManage(
    String role, {
    List<String>? permissions,
  }) =>
      AppPermissions.canManageChurchMuralEventsAgenda(role, permissions: permissions);

  /// Aviso activo no painel/site (não expirado).
  static bool isActive(ChurchAvisoItem item, {DateTime? now}) {
    if (item.permanent || item.expiresAt == null) return true;
    return item.expiresAt!.isAfter(now ?? DateTime.now());
  }

  /// Remove avisos vencidos há mais de 1 dia (Firestore + Storage).
  static Future<void> purgeExpired({required String churchIdHint}) async {
    final cid = churchId(churchIdHint);
    if (cid.isEmpty) return;

    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    try {
      if (kIsWeb) {
        await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
      }
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchUiCollections.avisos(cid)
            .where('publicado', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(60)
            .get(),
        maxAttempts: 3,
      );
      for (final d in snap.docs) {
        if (d.data()['permanent'] == true) continue;
        final exp = d.data()['avisoExpiresAt'] ?? d.data()['validUntil'];
        if (exp is! Timestamp) continue;
        if (!exp.toDate().isBefore(cutoff)) continue;
        await deleteOne(churchIdHint: cid, docId: d.id, data: d.data());
      }
    } catch (e) {
      debugPrint('ChurchAvisosService.purgeExpired: $e');
    }
  }

  /// Publica aviso: Storage (até 3 fotos) → Firestore (push FCM via Cloud Function).
  static Future<String> publish({
    required String churchIdHint,
    required String title,
    required String body,
    required bool permanent,
    DateTime? expiresAtEndOfDay,
    required List<Uint8List> photoBytes,
    String role = '',
    List<String>? permissions,
  }) async {
    if (!canManage(role, permissions: permissions)) {
      throw StateError('Sem permissão para publicar avisos.');
    }

    final cid = churchId(churchIdHint);
    if (cid.isEmpty) throw StateError('Igreja não identificada.');

    final titulo = title.trim();
    if (titulo.isEmpty) throw StateError('Informe o título do aviso.');

    final imgs = photoBytes.where((b) => b.isNotEmpty).take(kMaxPhotos).toList();
    if (imgs.isEmpty) {
      throw StateError('Inclua pelo menos uma foto no aviso.');
    }

    if (!permanent && expiresAtEndOfDay == null) {
      throw StateError('Escolha a data de vencimento ou marque como permanente.');
    }

    await purgeExpired(churchIdHint: cid);

    final user = FirebaseAuth.instance.currentUser;
    final docRef = ChurchUiCollections.avisos(cid).doc();
    final postId = docRef.id;

    final imageUrls = <String>[];
    final storagePaths = <String>[];

    for (var i = 0; i < imgs.length; i++) {
      final uploaded = await ChurchCentralStorageUpload.uploadAvisoPhoto(
        churchId: cid,
        postId: postId,
        slotIndex: i,
        rawBytes: imgs[i],
        onProgress: null,
      );
      imageUrls.add(uploaded.downloadUrl);
      storagePaths.add(uploaded.storagePath);
    }

    final now = FieldValue.serverTimestamp();
    Timestamp? expTs;
    Timestamp? validUntil;
    if (!permanent && expiresAtEndOfDay != null) {
      final end = DateTime(
        expiresAtEndOfDay.year,
        expiresAtEndOfDay.month,
        expiresAtEndOfDay.day,
        23,
        59,
        59,
      );
      expTs = Timestamp.fromDate(end);
      validUntil = expTs;
    }

    final payload = <String, dynamic>{
      'type': 'aviso',
      'title': titulo,
      'titulo': titulo,
      'body': body.trim(),
      'text': body.trim(),
      'mensagem': body.trim(),
      'createdAt': now,
      'updatedAt': now,
      'authorUid': user?.uid ?? '',
      'authorName': (user?.displayName ?? '').trim(),
      'publicSite': true,
      'publicado': true,
      'status': 'publicado',
      'publishState': 'published',
      'ativo': true,
      'permanent': permanent,
      'imageUrls': imageUrls,
      'imageUrl': imageUrls.first,
      'coverPhotoUrl': imageUrls.first,
      'fotoUrl': imageUrls.first,
      'photoStoragePaths': storagePaths,
      'imageStoragePaths': storagePaths,
      if (expTs != null) ...{
        'avisoExpiresAt': expTs,
        'validUntil': validUntil,
      },
    };

    if (kIsWeb) {
      await FirestoreWebGuard.ensurePanelReadReady().catchError((_) {});
    }
    await FirestoreWebGuard.runWithWebRecovery(
      () => docRef.set(payload),
      maxAttempts: 4,
    );

    return postId;
  }

  /// Exclui um aviso (Firestore + Storage em background).
  static Future<void> deleteOne({
    required String churchIdHint,
    required String docId,
    Map<String, dynamic>? data,
  }) async {
    final cid = churchId(churchIdHint);
    final id = docId.trim();
    if (cid.isEmpty || id.isEmpty) return;

    Map<String, dynamic>? docData = data;
    if (docData == null) {
      final snap = await ChurchUiCollections.avisos(cid).doc(id).get();
      if (!snap.exists) return;
      docData = snap.data();
    }

    await FirestoreWebGuard.runWithWebRecovery(
      () => ChurchUiCollections.avisos(cid).doc(id).delete(),
      maxAttempts: 4,
    );

    ChurchCanonicalMediaDeleteService.scheduleFeedPostDeleted(
      tenantId: cid,
      postId: id,
      isEvento: false,
      data: docData,
    );
  }

  /// Exclusão em lote.
  static Future<void> deleteMany({
    required String churchIdHint,
    required Iterable<String> docIds,
    required Map<String, Map<String, dynamic>> dataById,
  }) async {
    for (final id in docIds) {
      await deleteOne(
        churchIdHint: churchIdHint,
        docId: id,
        data: dataById[id],
      );
    }
  }
}
