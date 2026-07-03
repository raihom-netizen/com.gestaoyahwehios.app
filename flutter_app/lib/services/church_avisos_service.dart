import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/church_central_storage_upload.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_canonical_media_delete_service.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/utils/admin_feed_firestore_bridge.dart';
import 'package:gestao_yahweh/utils/firestore_publish_recovery.dart';
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

  static String churchId(String hint) {
    final raw = hint.trim();
    if (raw.isEmpty) return '';
    final mapped = TenantResolverService.mapLegacySeedToCanonical(raw);
    if (mapped != null && mapped.isNotEmpty) return mapped;
    if (RegExp(r'^igreja_[a-z0-9_]+$').hasMatch(raw)) return raw;
    return ChurchRepository.churchId(raw);
  }

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
      final docs = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchModuleFirestoreListRead.queryPlainFirst(
          reference: ChurchUiCollections.avisos(cid),
          cacheKey: '${cid.trim()}_avisos_purge',
          limit: 60,
          orderByField: 'createdAt',
          orderDescending: true,
          sortDocs: ChurchModuleFirestoreListRead.filterPublishedFeedRecords,
        ),
        maxAttempts: 3,
      );
      for (final d in docs) {
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
      'photoStoragePaths': storagePaths,
      'imageStoragePaths': storagePaths,
      if (imageUrls.isNotEmpty) ...{
        'imageUrl': imageUrls.first,
        'coverPhotoUrl': imageUrls.first,
        'fotoUrl': imageUrls.first,
      },
      if (expTs != null) ...{
        'avisoExpiresAt': expTs,
        'validUntil': validUntil,
      },
    };

    await AdminFeedFirestoreBridge.upsertDocRef(
      docRef: docRef,
      data: payload,
      isNewDoc: true,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload),
        maxAttempts: 4,
        criticalWrite: true,
      ),
    );

    return postId;
  }

  /// Atualiza aviso existente (título, mensagem, validade e fotos opcionais).
  static Future<void> update({
    required String churchIdHint,
    required String docId,
    required String title,
    required String body,
    required bool permanent,
    DateTime? expiresAtEndOfDay,
    List<String> existingImageUrls = const [],
    List<Uint8List> newPhotoBytes = const [],
    String role = '',
    List<String>? permissions,
  }) async {
    if (!canManage(role, permissions: permissions)) {
      throw StateError('Sem permissão para editar avisos.');
    }

    final cid = churchId(churchIdHint);
    final id = docId.trim();
    if (cid.isEmpty || id.isEmpty) {
      throw StateError('Aviso não identificado para edição.');
    }

    final titulo = title.trim();
    if (titulo.isEmpty) throw StateError('Informe o título do aviso.');

    if (!permanent && expiresAtEndOfDay == null) {
      throw StateError('Escolha a data de vencimento ou marque como permanente.');
    }

    final keepUrls = <String>[];
    for (final raw in existingImageUrls) {
      final u = raw.trim();
      if (u.isNotEmpty && !keepUrls.contains(u)) keepUrls.add(u);
      if (keepUrls.length >= kMaxPhotos) break;
    }

    final remainingSlots = (kMaxPhotos - keepUrls.length).clamp(0, kMaxPhotos);
    final newImages = newPhotoBytes
        .where((b) => b.isNotEmpty)
        .take(remainingSlots)
        .toList();

    final uploadedUrls = <String>[];
    final uploadedPaths = <String>[];
    for (var i = 0; i < newImages.length; i++) {
      final slotIndex = keepUrls.length + i;
      final uploaded = await ChurchCentralStorageUpload.uploadAvisoPhoto(
        churchId: cid,
        postId: id,
        slotIndex: slotIndex,
        rawBytes: newImages[i],
        onProgress: null,
      );
      uploadedUrls.add(uploaded.downloadUrl);
      uploadedPaths.add(uploaded.storagePath);
    }

    final mergedUrls = <String>[...keepUrls, ...uploadedUrls]
        .where((e) => e.trim().isNotEmpty)
        .toList();

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
      'updatedAt': FieldValue.serverTimestamp(),
      'publicado': true,
      'status': 'publicado',
      'publishState': 'published',
      'ativo': true,
      'permanent': permanent,
      if (expTs != null) ...{
        'avisoExpiresAt': expTs,
        'validUntil': validUntil,
      } else ...{
        'avisoExpiresAt': FieldValue.delete(),
        'validUntil': FieldValue.delete(),
      },
    };

    if (mergedUrls.isNotEmpty) {
      payload.addAll({
        'imageUrls': mergedUrls,
        'imageUrl': mergedUrls.first,
        'coverPhotoUrl': mergedUrls.first,
        'fotoUrl': mergedUrls.first,
      });
      if (uploadedPaths.isNotEmpty && keepUrls.isEmpty) {
        payload['photoStoragePaths'] = uploadedPaths;
        payload['imageStoragePaths'] = uploadedPaths;
      }
    } else {
      payload.addAll({
        'imageUrls': FieldValue.delete(),
        'imageUrl': FieldValue.delete(),
        'coverPhotoUrl': FieldValue.delete(),
        'fotoUrl': FieldValue.delete(),
        'photoStoragePaths': FieldValue.delete(),
        'imageStoragePaths': FieldValue.delete(),
      });
    }

    final docRef = ChurchUiCollections.avisos(cid).doc(id);
    await AdminFeedFirestoreBridge.upsertDocRef(
      docRef: docRef,
      data: payload,
      isNewDoc: false,
      directWrite: () => runFirestorePublishWithRecovery(
        () => docRef.set(payload, SetOptions(merge: true)),
        maxAttempts: 4,
        criticalWrite: true,
      ),
    );

    unawaited(ChurchAvisosLoadService.invalidate(cid));
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
      if (kIsWeb) {
        await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
      }
      final snap = await FirestoreWebGuard.runWithWebRecovery(
        () => ChurchUiCollections.avisos(cid).doc(id).get(),
        maxAttempts: 4,
      );
      if (!snap.exists) return;
      docData = snap.data();
    }

    await AdminFeedFirestoreBridge.deleteFeedPosts(
      churchId: cid,
      collection: 'avisos',
      docIds: [id],
      directDelete: () => runFirestorePublishWithRecovery(
        () => ChurchUiCollections.avisos(cid).doc(id).delete(),
        maxAttempts: 4,
        criticalWrite: true,
      ),
    );

    ChurchCanonicalMediaDeleteService.scheduleFeedPostDeleted(
      tenantId: cid,
      postId: id,
      isEvento: false,
      data: docData,
    );
    unawaited(ChurchAvisosLoadService.invalidate(cid));
  }

  /// Exclusão em lote — batch Firestore + limpeza Storage + invalidar cache.
  static Future<int> deleteMany({
    required String churchIdHint,
    required Iterable<String> docIds,
    Map<String, Map<String, dynamic>> dataById = const {},
  }) async {
    final cid = churchId(churchIdHint);
    final ids = docIds
        .map((e) => e.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (cid.isEmpty || ids.isEmpty) return 0;

    final col = ChurchUiCollections.avisos(cid);
    const chunkSize = 450;

    for (var i = 0; i < ids.length; i += chunkSize) {
      final slice = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );
      await AdminFeedFirestoreBridge.deleteFeedPosts(
        churchId: cid,
        collection: 'avisos',
        docIds: slice,
        directDelete: () => runFirestorePublishWithRecovery(
          () async {
            final batch = ChurchRepository.batch();
            for (final id in slice) {
              batch.delete(col.doc(id));
            }
            await batch.commit();
          },
          maxAttempts: 4,
          criticalWrite: true,
        ),
      );
      for (final id in slice) {
        ChurchCanonicalMediaDeleteService.scheduleFeedPostDeleted(
          tenantId: cid,
          postId: id,
          isEvento: false,
          data: dataById[id],
        );
      }
    }

    unawaited(ChurchAvisosLoadService.invalidate(cid));
    return ids.length;
  }
}
