import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/feed_tenant_storage_map.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_paths.dart';
import 'package:gestao_yahweh/core/firebase_publish_guard.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/pending_uploads_firestore_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';

/// Reenvio de publicações do mural interrompidas (app fechado, rede, etc.).
abstract final class MuralPublishOutboxService {
  MuralPublishOutboxService._();

  static const _prefsKey = 'mural_publish_outbox_v1';
  static bool _connectivityBound = false;

  /// Jobs no manifesto local (SharedPreferences).
  static Future<int> pendingJobCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return 0;
    try {
      return (jsonDecode(raw) as List).length;
    } catch (_) {
      return 0;
    }
  }

  static DocumentReference<Map<String, dynamic>> _docRef(
    String tenantId,
    String postType,
    String postId,
  ) {
    final col = postType == 'aviso'
        ? ChurchTenantPostsCollections.avisos
        : ChurchTenantPostsCollections.eventos;
    return         ChurchOperationalPaths.churchDoc(tenantId)
        .collection(col)
        .doc(postId);
  }

  static Future<void> registerJob({
    required String tenantId,
    required String postId,
    required String postType,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<String>? localPaths,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final list = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.removeWhere(
      (e) =>
          (e['tenantId'] ?? '').toString() == tenantId &&
          (e['postId'] ?? '').toString() == postId,
    );
    final paths = localPaths
            ?.map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    list.add({
      'tenantId': tenantId,
      'postId': postId,
      'postType': postType,
      'existingUrls': existingUrls,
      'startSlotIndex': startSlotIndex,
      'hasVideo': hasVideo,
      if (paths.isNotEmpty) 'localPaths': paths,
    });
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  static Future<void> clearJob({
    required String tenantId,
    required String postId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    list.removeWhere(
      (e) =>
          (e['tenantId'] ?? '').toString() == tenantId &&
          (e['postId'] ?? '').toString() == postId,
    );
    await prefs.setString(_prefsKey, jsonEncode(list));
  }

  /// Arranque da app — reenvia jobs pendentes (um de cada vez via [BackgroundUploadWorker]).
  static void resumePendingOnAppStart() {
    bindConnectivityResume();
    unawaited(drainPendingJobs());
  }

  /// Drena todos os jobs do mural outbox em série (sobrevive a fecho da app).
  static Future<void> drainPendingJobs() async {
    bindConnectivityResume();
    await runFirebaseBackgroundTask<void>(
      () async {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null || raw.isEmpty) return;
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final eligible = <Map<String, dynamic>>[];
        for (final m in list) {
          final attempts =
              (m['attemptCount'] is num ? (m['attemptCount'] as num).toInt() : 0);
          if (attempts >= 10) continue;
          eligible.add({...m, 'attemptCount': attempts + 1});
        }
        for (var i = 0; i < eligible.length; i += 2) {
          final batch = eligible.sublist(
            i,
            (i + 2 > eligible.length) ? eligible.length : i + 2,
          );
          await Future.wait(
            batch.map((m) => _retryFromJson(m, attemptCount: m['attemptCount'] as int)),
            eagerError: false,
          );
        }
      },
      debugLabel: 'mural_outbox_drain',
    ).catchError((e, st) {
      if (kDebugMode) {
        debugPrint('MuralPublishOutboxService.drainPendingJobs: $e\n$st');
      }
    });
  }

  static void bindConnectivityResume() {
    if (_connectivityBound) return;
    _connectivityBound = true;
    AppConnectivityService.instance.onlineStream.listen((online) {
      if (online) resumePendingOnAppStart();
    });
  }

  static Future<void> retryFromCard({
    required String tenantId,
    required String postId,
    required String postType,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
  }) async {
    await _retryFromJson({
      'tenantId': tenantId,
      'postId': postId,
      'postType': postType,
      'existingUrls': existingUrls,
      'startSlotIndex': startSlotIndex,
      'hasVideo': hasVideo,
    });
  }

  static Future<void> _retryFromJson(
    Map<String, dynamic> json, {
    int attemptCount = 1,
  }) async {
    await ensureFirebaseReadyToPublish(logLabel: 'mural_outbox_retry');
    final tenantId = (json['tenantId'] ?? '').toString();
    final postId = (json['postId'] ?? '').toString();
    final postType = (json['postType'] ?? 'aviso').toString();
    if (tenantId.isEmpty || postId.isEmpty) return;

    try {
      await _retryFromJsonInner(json, attemptCount: attemptCount);
    } catch (e, st) {
      final paths = (json['localPaths'] as List?)
              ?.map((x) => x.toString().trim())
              .where((p) => p.isNotEmpty)
              .toList() ??
          const <String>[];
      final slotHint = json['startSlotIndex'] is int
          ? json['startSlotIndex'] as int
          : int.tryParse('${json['startSlotIndex']}') ?? 0;
      final storagePathGuess = paths.isNotEmpty
          ? FeedTenantStorageMap.feedPhotoPath(
              postType: postType,
              tenantId: tenantId,
              postDocId: postId,
              slotIndex: slotHint,
            )
          : '${FirebasePaths.storageRoot(tenantId)}/${postType == 'aviso' ? 'avisos' : 'eventos'}/$postId';
      unawaited(
        PendingUploadsFirestoreService.recordFailedBytesUpload(
          tenantId: tenantId,
          module: postType == 'aviso' ? 'aviso' : 'evento',
          storagePath: storagePathGuess,
          error: e,
          localPath: paths.isEmpty ? null : paths.first,
          meta: {
            'postId': postId,
            'postType': postType,
            'source': 'mural_outbox',
          },
        ),
      );
      if (kDebugMode) {
        debugPrint('MuralPublishOutbox fail $postId: $e\n$st');
      }
      rethrow;
    }
  }

  static Future<void> _retryFromJsonInner(
    Map<String, dynamic> json, {
    int attemptCount = 1,
  }) async {
    final tenantId = (json['tenantId'] ?? '').toString();
    final postId = (json['postId'] ?? '').toString();
    final postType = (json['postType'] ?? 'aviso').toString();

    final images = await MuralPostPendingMediaCache.get(
      tenantId: tenantId,
      postId: postId,
    );
    final localPaths = (json['localPaths'] as List?)
            ?.map((e) => e.toString().trim())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    final docRef = _docRef(tenantId, postType, postId);
    final snap = await docRef.get();
    if ((images == null || images.isEmpty) && localPaths.isEmpty) {
      final state = (snap.data()?['publishState'] ?? '').toString();
      if (state == MuralFastPublishService.stateUploading) {
        await docRef.set(
          {
            'publishState': MuralFastPublishService.stateFailed,
            'publicado': false,
            'status': 'erro',
            'publishError':
                'Fotos não encontradas no aparelho. Edite o aviso/evento e envie de novo.',
          },
          SetOptions(merge: true),
        );
      }
      await clearJob(tenantId: tenantId, postId: postId);
      return;
    }

    if (!snap.exists) {
      await clearJob(tenantId: tenantId, postId: postId);
      await MuralPostPendingMediaCache.remove(
        tenantId: tenantId,
        postId: postId,
      );
      return;
    }
    final state = (snap.data()?['publishState'] ?? '').toString();
    if (state == MuralFastPublishService.statePublished) {
      await clearJob(tenantId: tenantId, postId: postId);
      await MuralPostPendingMediaCache.remove(
        tenantId: tenantId,
        postId: postId,
      );
      return;
    }

    final existingUrls = (json['existingUrls'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final startSlot = json['startSlotIndex'] is int
        ? json['startSlotIndex'] as int
        : int.tryParse('${json['startSlotIndex']}') ?? 0;
    final hasVideo = json['hasVideo'] == true;

    // Não gravar Firestore «uploading» antes do Storage — só upload + finalize.
    final buildMedia =
        ({required allUrls, required aspectRatio, required hasVideo}) =>
            MuralPostMediaPayload.buildMediaFields(
      allUrls: allUrls,
      aspectRatio: aspectRatio,
      hasVideo: hasVideo,
    );

    if (localPaths.isNotEmpty) {
      await MuralFastPublishService.uploadImagesAndFinalizePostFromPaths(
        docRef: docRef,
        tenantId: tenantId,
        postId: postId,
        postType: postType,
        localPaths: localPaths,
        existingUrls: existingUrls,
        startSlotIndex: startSlot,
        hasVideo: hasVideo,
        uploadSlot: (bytes, slot, report) =>
            MuralPostMediaPayload.uploadPhotoSlot(
          tenantId: tenantId,
          postType: postType,
          postId: postId,
          bytes: bytes,
          slotIndex: slot,
          onProgress: report,
        ),
        buildMediaFields: buildMedia,
      );
      return;
    }

    await MuralFastPublishService.uploadImagesAndFinalizePost(
      docRef: docRef,
      tenantId: tenantId,
      postId: postId,
      postType: postType,
      newImages: images!,
      existingUrls: existingUrls,
      startSlotIndex: startSlot,
      hasVideo: hasVideo,
      uploadSlot: (bytes, slot, report) => MuralPostMediaPayload.uploadPhotoSlot(
        tenantId: tenantId,
        postType: postType,
        postId: postId,
        bytes: bytes,
        slotIndex: slot,
        onProgress: report,
      ),
      buildMediaFields: buildMedia,
    );
  }
}
