import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/mural_fast_publish_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/mural_post_pending_media_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reenvio de publicações do mural interrompidas (app fechado, rede, etc.).
abstract final class MuralPublishOutboxService {
  MuralPublishOutboxService._();

  static const _prefsKey = 'mural_publish_outbox_v1';

  static DocumentReference<Map<String, dynamic>> _docRef(
    String tenantId,
    String postType,
    String postId,
  ) {
    final col = postType == 'aviso'
        ? ChurchTenantPostsCollections.avisos
        : ChurchTenantPostsCollections.noticias;
    return FirebaseFirestore.instance
        .collection('igrejas')
        .doc(tenantId)
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

  /// Arranque da app — conclui uploads com ficheiros ainda em cache.
  static void resumePendingOnAppStart() {
    unawaited(
      runFirebaseBackgroundTask<void>(
        () async {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString(_prefsKey);
          if (raw == null || raw.isEmpty) return;
          final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
          for (final m in list) {
            final attempts =
                (m['attemptCount'] is num ? (m['attemptCount'] as num).toInt() : 0);
            if (attempts >= 6) continue;
            await _retryFromJson(m, attemptCount: attempts + 1);
          }
        },
        debugLabel: 'mural_outbox_resume',
      ).catchError((_) {}),
    );
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
    await ensureFirebaseReadyForMediaUpload();
    final tenantId = (json['tenantId'] ?? '').toString();
    final postId = (json['postId'] ?? '').toString();
    final postType = (json['postType'] ?? 'aviso').toString();
    if (tenantId.isEmpty || postId.isEmpty) return;

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

    await docRef.set(
      {
        'publishState': MuralFastPublishService.stateUploading,
        'publishError': FieldValue.delete(),
      },
      SetOptions(merge: true),
    );

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
