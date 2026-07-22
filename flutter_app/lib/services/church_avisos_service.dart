import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_deleted_doc_tombstones.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:gestao_yahweh/core/church_module_firestore_list_read.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_diagnostic_log.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/core/ecofire/direct_storage_url_publish.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/app_permissions.dart';
import 'package:gestao_yahweh/services/church_avisos_load_service.dart';
import 'package:gestao_yahweh/services/church_canonical_media_delete_service.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show eventNoticiaDocHasPhotoMedia;
import 'package:gestao_yahweh/core/noticia_share_utils.dart'
    show noticiaGalleryRefsForShare;
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';
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
    required this.rawData,
    required this.createdAt,
    required this.permanent,
    this.expiresAt,
    this.authorName = '',
  });

  final String id;
  final String title;
  final String body;
  final List<String> imageUrls;
  final Map<String, dynamic> rawData;
  final DateTime? createdAt;
  final bool permanent;
  final DateTime? expiresAt;
  final String authorName;

  bool get hasImages =>
      imageUrls.isNotEmpty || eventNoticiaDocHasPhotoMedia(rawData);

  /// URLs + paths Storage para carrossel (igual eventos / site público).
  List<String> mediaRefs() => noticiaGalleryRefsForShare(rawData);

  /// Metadados mínimos para limpeza Storage na exclusão.
  Map<String, dynamic> toStorageCleanupPayload() => <String, dynamic>{
        if (imageUrls.isNotEmpty) ...{
          'imageUrls': imageUrls,
          'imageUrl': imageUrls.first,
        },
      };

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
    for (final u in noticiaGalleryRefsForShare(m)) {
      addUrl(u);
    }

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
      rawData: Map<String, dynamic>.from(m),
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

  static const int kMaxPhotos = 5;
  static const Duration kPublishTimeout = Duration(minutes: 10);

  /// Legado — lista pode ler `mural_avisos` quando `avisos` está vazio.
  static const List<String> _deleteCollections = ['avisos', 'mural_avisos'];

  static CollectionReference<Map<String, dynamic>> _collection(
    String churchId,
    String sub,
  ) =>
      ChurchUiCollections.ref(sub, churchIdHint: churchId);

  static Future<void> _ensurePublishReady({bool allowOfflineQueue = true}) async {
    try {
      await ChurchMediaUploadFacade.ensureReady(requireAuth: true);
    } catch (e) {
      if (allowOfflineQueue &&
          EcoFireResilientPublish.shouldQueueFeedPublish(e)) {
        return;
      }
      rethrow;
    }
  }

  static Future<void> _publishAvisoWithRecovery({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingPhotoRefs,
    required int startSlotIndex,
    List<Uint8List>? newImagesBytes,
    required bool publicSite,
    DateTime? calendarDate,
    bool syncCalendar = true,
    void Function(double progress)? onUploadProgress,
  }) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          await YahwehModuleMediaGate.recoverNoAppAfterPublishError(
            last ?? StateError('core/no-app'),
          );
        }
        await ChurchFeedLinearPublishService.publishAviso(
          docRef: docRef,
          tenantId: tenantId,
          corePayload: corePayload,
          isNewDoc: isNewDoc,
          existingPhotoRefs: existingPhotoRefs,
          startSlotIndex: startSlotIndex,
          newImagesBytes: newImagesBytes,
          publicSite: publicSite,
          calendarDate: calendarDate,
          syncCalendar: syncCalendar,
          onUploadProgress: onUploadProgress,
        );
        return;
      } catch (e) {
        last = e;
        final retryable = isFirebaseNoAppError(e) ||
            FirestoreWebGuard.isClientTerminated(e) ||
            e is TimeoutException ||
            (e is FirebaseException &&
                const {
                  'unavailable',
                  'network-request-failed',
                  'retry-limit-exceeded',
                  'deadline-exceeded',
                  'cancelled',
                  'unknown',
                }.contains(e.code));
        if (!retryable || attempt >= 2) rethrow;
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
  }

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
    void Function(double progress)? onUploadProgress,
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

    unawaited(purgeExpired(churchIdHint: cid));

    await _ensurePublishReady();

    final user = FirebaseAuth.instance.currentUser;
    final docRef = ChurchUiCollections.avisos(cid).doc();
    final postId = docRef.id;

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

    final corePayload = <String, dynamic>{
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
      'permanent': permanent,
      if (expTs != null) ...{
        'avisoExpiresAt': expTs,
        'validUntil': validUntil,
      },
    };

    logFirebasePublishPhase(
      'avisos_service_publish_start',
      'path=${docRef.path} photos=${imgs.length}',
    );

    try {
      await _publishAvisoWithRecovery(
        docRef: docRef,
        tenantId: cid,
        corePayload: corePayload,
        isNewDoc: true,
        existingPhotoRefs: const [],
        startSlotIndex: 0,
        newImagesBytes: imgs.isNotEmpty ? imgs : null,
        publicSite: true,
        calendarDate: permanent ? null : expiresAtEndOfDay,
        syncCalendar: true,
        onUploadProgress: onUploadProgress,
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'avisos_service_publish_error',
        'path=${docRef.path}',
        error: e,
        stack: st,
      );
      if (EcoFireResilientPublish.shouldQueueFeedPublish(e)) {
        await EcoFireResilientPublish.queueFeedPublish(
          churchId: cid,
          docId: postId,
          postType: 'aviso',
          docRef: docRef,
          corePayload: corePayload,
          isNewDoc: true,
          existingUrls: const [],
          startSlotIndex: 0,
          hasVideo: false,
          bytesList: imgs.isNotEmpty ? imgs : null,
        );
        EcoFireResilientPublish.scheduleSync(reason: 'aviso_queued');
        throw ResilientPublishQueuedException('aviso:$postId');
      }
      rethrow;
    }

    // Não bloquear o retorno da publicação a limpar Hive — painel atualiza em background.
    unawaited(ChurchAvisosLoadService.invalidate(cid));
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
    void Function(double progress)? onUploadProgress,
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

    await _ensurePublishReady();

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

    final corePayload = <String, dynamic>{
      'type': 'aviso',
      'title': titulo,
      'titulo': titulo,
      'body': body.trim(),
      'text': body.trim(),
      'mensagem': body.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'permanent': permanent,
      if (expTs != null) ...{
        'avisoExpiresAt': expTs,
        'validUntil': validUntil,
      } else ...{
        'avisoExpiresAt': FieldValue.delete(),
        'validUntil': FieldValue.delete(),
      },
    };

    final docRef = ChurchUiCollections.avisos(cid).doc(id);

    logFirebasePublishPhase(
      'avisos_service_update_start',
      'path=${docRef.path} keep=${keepUrls.length} new=${newImages.length}',
    );

    try {
      await _publishAvisoWithRecovery(
        docRef: docRef,
        tenantId: cid,
        corePayload: corePayload,
        isNewDoc: false,
        existingPhotoRefs: keepUrls,
        startSlotIndex: keepUrls.length,
        newImagesBytes: newImages.isNotEmpty ? newImages : null,
        publicSite: true,
        calendarDate: permanent ? null : expiresAtEndOfDay,
        syncCalendar: true,
        onUploadProgress: onUploadProgress,
      );
    } catch (e, st) {
      logFirebasePublishPhase(
        'avisos_service_update_error',
        'path=${docRef.path}',
        error: e,
        stack: st,
      );
      if (EcoFireResilientPublish.shouldQueueFeedPublish(e)) {
        await EcoFireResilientPublish.queueFeedPublish(
          churchId: cid,
          docId: id,
          postType: 'aviso',
          docRef: docRef,
          corePayload: corePayload,
          isNewDoc: false,
          existingUrls: keepUrls,
          startSlotIndex: keepUrls.length,
          hasVideo: false,
          bytesList: newImages.isNotEmpty ? newImages : null,
        );
        EcoFireResilientPublish.scheduleSync(reason: 'aviso_update_queued');
        throw ResilientPublishQueuedException('aviso:$id');
      }
      rethrow;
    }

    await ChurchAvisosLoadService.invalidate(cid);
  }

  /// Exclui um aviso (Firestore + Storage).
  static Future<void> deleteOne({
    required String churchIdHint,
    required String docId,
    Map<String, dynamic>? data,
  }) async {
    final cid = churchId(churchIdHint);
    final id = docId.trim();
    if (cid.isEmpty || id.isEmpty) {
      throw StateError('Aviso não identificado para exclusão.');
    }

    // Lápide ANTES do delete — nenhum refresh em background «ressuscita» o aviso.
    TenantDeletedDocTombstones.mark(cid, TenantModuleKeys.avisos, [id]);

    await ensureFirebaseReadyForPublishUpload().catchError((_) {});
    if (kIsWeb) {
      await FirestoreWebGuard.prepareForPublishWrite().catchError((_) {});
    }

    var docData = data == null ? null : Map<String, dynamic>.from(data);
    final snaps = await Future.wait(
      _deleteCollections.map((sub) async {
        try {
          return await FirestoreWebGuard.runWithWebRecovery(
            () => _collection(cid, sub).doc(id).get(),
            maxAttempts: kIsWeb ? 4 : 3,
          );
        } catch (_) {
          return null;
        }
      }),
    );
    for (final snap in snaps) {
      if (snap != null && snap.exists) {
        docData = <String, dynamic>{...?docData, ...?snap.data()};
      }
    }

    await _deleteAvisoDocs(churchId: cid, docIds: [id]);

    await ChurchCanonicalMediaDeleteService.purgeFeedPostDeleted(
      tenantId: cid,
      postId: id,
      isEvento: false,
      data: docData,
    );

    ChurchAvisosLoadService.evictDocFromCaches(cid, id);
    await ChurchAvisosLoadService.invalidate(cid);
  }

  static Future<void> _deleteAvisoDocs({
    required String churchId,
    required List<String> docIds,
  }) async {
    final ids = docIds
        .map((e) => e.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;

    const chunkSize = 200;

    for (var i = 0; i < ids.length; i += chunkSize) {
      final slice = ids.sublist(
        i,
        i + chunkSize > ids.length ? ids.length : i + chunkSize,
      );

      // Batch principal: apaga só da coleção `avisos`.
      await AdminFeedFirestoreBridge.deleteFeedPosts(
        churchId: churchId,
        collection: 'avisos',
        docIds: slice,
        directDelete: () => runFirestorePublishWithRecovery(
          () async {
            final batch = ChurchRepository.batch();
            for (final id in slice) {
              batch.delete(_collection(churchId, 'avisos').doc(id));
            }
            await batch.commit();
          },
          maxAttempts: 4,
          criticalWrite: true,
        ),
      );

      // Legado: `mural_avisos` em batch separado e não-crítico.
      unawaited(_deleteLegacyMuralAvisos(churchId, slice));
    }
  }

  static Future<void> _deleteLegacyMuralAvisos(
    String churchId,
    List<String> docIds,
  ) async {
    try {
      final batch = ChurchRepository.batch();
      for (final id in docIds) {
        batch.delete(_collection(churchId, 'mural_avisos').doc(id));
      }
      await batch.commit();
    } catch (e) {
      debugPrint('AVISOS legacy mural_avisos delete: $e');
    }
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

    TenantDeletedDocTombstones.mark(cid, TenantModuleKeys.avisos, ids);

    await _deleteAvisoDocs(churchId: cid, docIds: ids);

    await Future.wait(
      ids.map((id) async {
        await ChurchCanonicalMediaDeleteService.purgeFeedPostDeleted(
          tenantId: cid,
          postId: id,
          isEvento: false,
          data: dataById[id],
        );
        ChurchAvisosLoadService.evictDocFromCaches(cid, id);
      }),
      eagerError: false,
    );

    await ChurchAvisosLoadService.invalidate(cid);
    return ids.length;
  }
}
