import 'dart:async' show unawaited;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/yahweh_flow_log.dart';
import 'package:gestao_yahweh/services/firebase_storage_cleanup_service.dart';
import 'package:gestao_yahweh/services/media_upload_service.dart';
import 'package:gestao_yahweh/services/patrimonio_media_upload.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Patrimônio: Firestore primeiro → UI fecha → fotos em background.
abstract final class PatrimonioPublishService {
  PatrimonioPublishService._();

  static const String photoUploadStateField = EntityPublishStatus.photoUploadStateField;
  static const String stateCreating = EntityPublishStatus.creating;
  static const String stateUploading = EntityPublishStatus.uploading;
  static const String stateUploaded = EntityPublishStatus.published;
  static const String stateError = EntityPublishStatus.error;

  static void schedulePhotosAfterFirestoreSave({
    required DocumentReference<Map<String, dynamic>> itemRef,
    required String tenantId,
    required String itemId,
    required List<Uint8List> newImages,
    required int startSlot,
    required List<String> existingUrls,
    required List<String> existingPaths,
    required Map<String, dynamic> Function(
      List<String> urls,
      List<String> paths,
    )
        buildPayload,
    Map<String, dynamic>? previousDoc,
    void Function(List<String> urls, List<String> paths)? onPathsForCleanup,
  }) {
    unawaited(
      () async {
        await ensureFirebaseCore(requireAuth: true);
        await _uploadAndMerge(
          itemRef: itemRef,
          tenantId: tenantId,
          itemId: itemId,
          newImages: newImages,
          startSlot: startSlot,
          existingUrls: existingUrls,
          existingPaths: existingPaths,
          buildPayload: buildPayload,
          previousDoc: previousDoc,
          onPathsForCleanup: onPathsForCleanup,
        );
      }().catchError((Object e, StackTrace st) async {
        YahwehFlowLog.error('PATRIMONIO', e, st);
        try {
          await itemRef.set(
            {
              photoUploadStateField: stateError,
              'photoUploadError': e.toString(),
              'atualizadoEm': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } catch (e2, s2) {
          YahwehFlowLog.error('PATRIMONIO', e2, s2);
        }
      }),
    );
  }

  static Future<void> _uploadAndMerge({
    required DocumentReference<Map<String, dynamic>> itemRef,
    required String tenantId,
    required String itemId,
    required List<Uint8List> newImages,
    required int startSlot,
    required List<String> existingUrls,
    required List<String> existingPaths,
    required Map<String, dynamic> Function(
      List<String> urls,
      List<String> paths,
    )
        buildPayload,
    Map<String, dynamic>? previousDoc,
    void Function(List<String> urls, List<String> paths)? onPathsForCleanup,
  }) async {
    YahwehFlowLog.patrimonioStart();
    try {
      await itemRef.set(
        {photoUploadStateField: stateUploading},
        SetOptions(merge: true),
      );
    } catch (e, st) {
      YahwehFlowLog.error('PATRIMONIO', e, st);
      rethrow;
    }
    final allUrls = List<String>.from(existingUrls);
    final allPaths = List<String>.from(existingPaths);
    final nBatch = newImages.length;

    await Future.wait(
      List.generate(
        nBatch,
        (j) => FirebaseStorageCleanupService.deletePatrimonioSlotArtifacts(
          tenantId: tenantId,
          itemDocId: itemId,
          slot: startSlot + j,
        ),
      ),
    );

    const uploadConcurrency = 3;
    final results = <MediaUploadResult>[];
    for (var batchStart = 0; batchStart < nBatch; batchStart += uploadConcurrency) {
      final batchEnd = math.min(batchStart + uploadConcurrency, nBatch);
      final chunk = await Future.wait(
        List.generate(batchEnd - batchStart, (k) {
          final j = batchStart + k;
          final slot = startSlot + j;
          final path =
              ChurchStorageLayout.patrimonioPhotoPath(tenantId, itemId, slot);
          return PatrimonioMediaUpload.uploadGalleryPhoto(
            storagePath: path,
            rawBytes: newImages[j],
          );
        }),
      );
      results.addAll(chunk);
    }
    for (final r in results) {
      allUrls.add(r.downloadUrl);
      allPaths.add(r.storagePath);
    }
    if (results.isNotEmpty) {
      await Future.wait([
        for (final r in results)
          CachedNetworkImage.evictFromCache(r.downloadUrl),
      ]);
    }

    if (previousDoc != null) {
      await _cleanupReplacedPhotos(previousDoc, allUrls);
    }

    final payload = buildPayload(allUrls, allPaths);
    payload[photoUploadStateField] = stateUploaded;
    payload['photoUploadError'] = FieldValue.delete();
    payload['imageVariants'] = FieldValue.delete();
    payload['fotoVariants'] = FieldValue.delete();
    await itemRef.set(payload, SetOptions(merge: true));

    YahwehFlowLog.patrimonioUploadOk();
    FirebaseStorageCleanupService.scheduleCleanupAfterPatrimonioItemPhotoUpload(
      tenantId: tenantId,
      itemDocId: itemId,
    );
    onPathsForCleanup?.call(allUrls, allPaths);
    YahwehFlowLog.patrimonioSuccess();
  }

  static Future<void> _cleanupReplacedPhotos(
    Map<String, dynamic> prev,
    List<String> allUrls,
  ) async {
    List<String> fotoUrlsFromData(Map<String, dynamic> data) {
      final raw = data['fotoUrls'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      final one = sanitizeImageUrl(
        (data['imageUrl'] ?? data['fotoUrl'] ?? '').toString(),
      );
      return one.isEmpty ? <String>[] : [one];
    }

    final oldList = fotoUrlsFromData(prev)
        .map((e) => sanitizeImageUrl(e))
        .where((e) => e.isNotEmpty)
        .toList();
    final oldSet = oldList.toSet();
    final newSet = allUrls
        .map((e) => sanitizeImageUrl(e))
        .where((e) => e.isNotEmpty)
        .toSet();
    await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
      oldSet.difference(newSet),
    );
    final oldFirst = oldList.isEmpty ? '' : oldList.first;
    final newFirst = allUrls.isEmpty ? '' : sanitizeImageUrl(allUrls.first);
    if (oldFirst.isNotEmpty && oldFirst != newFirst) {
      await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
        FirebaseStorageCleanupService.urlsFromVariantMap(prev['imageVariants']),
      );
      await FirebaseStorageCleanupService.deleteManyByUrlPathOrGs(
        FirebaseStorageCleanupService.urlsFromVariantMap(prev['fotoVariants']),
      );
    }
  }
}
