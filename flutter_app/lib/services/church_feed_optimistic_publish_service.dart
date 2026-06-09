import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:gestao_yahweh/core/offline/offline_module_sync.dart';
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';
import 'package:gestao_yahweh/services/church_feed_media_storage_fields.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/sync_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Publicação rápida: grava texto/mídia existente → fecha UI → upload/sync em background.
abstract final class ChurchFeedOptimisticPublishService {
  ChurchFeedOptimisticPublishService._();

  static Future<String> publishAviso({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    bool publicSite = true,
    DateTime? calendarDate,
    bool syncCalendar = true,
  }) async {
    await _writeOptimisticSnapshot(
      isEvento: false,
      docRef: docRef,
      tenantId: tenantId,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      hasVideo: false,
      videoStoragePath: null,
      publicSite: publicSite,
    );
    SyncService.notifyUserActionSaved();
    unawaited(
      _backgroundPublish(
        label: 'aviso',
        publish: () => ChurchFeedLinearPublishService.publishAviso(
          docRef: docRef,
          tenantId: tenantId,
          corePayload: corePayload,
          isNewDoc: isNewDoc,
          existingPhotoRefs: existingUrls,
          startSlotIndex: startSlotIndex,
          newImagesBytes: newImagesBytes,
          newImagePaths: newImagePaths,
          publicSite: publicSite,
          calendarDate: calendarDate,
          syncCalendar: syncCalendar,
        ),
      ),
    );
    return docRef.id;
  }

  static Future<String> publishEvento({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    String? videoStoragePath,
    bool publicSite = true,
    DateTime? eventStartAt,
    String? location,
    bool syncAgenda = true,
    String? agendaCategory,
    String? agendaColorHex,
  }) async {
    await _writeOptimisticSnapshot(
      isEvento: true,
      docRef: docRef,
      tenantId: tenantId,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      hasVideo: hasVideo,
      videoStoragePath: videoStoragePath,
      publicSite: publicSite,
    );
    SyncService.notifyUserActionSaved();
    unawaited(
      _backgroundPublish(
        label: 'evento',
        publish: () => ChurchFeedLinearPublishService.publishEvento(
          docRef: docRef,
          tenantId: tenantId,
          corePayload: corePayload,
          isNewDoc: isNewDoc,
          existingPhotoRefs: existingUrls,
          startSlotIndex: startSlotIndex,
          hasVideo: hasVideo,
          newImagesBytes: newImagesBytes,
          newImagePaths: newImagePaths,
          videoStoragePath: videoStoragePath,
          publicSite: publicSite,
          eventStartAt: eventStartAt,
          location: location,
          syncAgenda: syncAgenda,
          agendaCategory: agendaCategory,
          agendaColorHex: agendaColorHex,
        ),
      ),
    );
    return docRef.id;
  }

  static Future<void> _writeOptimisticSnapshot({
    required bool isEvento,
    required DocumentReference<Map<String, dynamic>> docRef,
    required String tenantId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required bool hasVideo,
    String? videoStoragePath,
    required bool publicSite,
  }) async {
    final existingPaths = EventosPublishVerificationService.storagePathsFromUrls(
      dedupeImageRefsByStorageIdentity(existingUrls),
    );
    final aspectRatio = _aspectRatioFromPayload(corePayload);
    final payload = Map<String, dynamic>.from(corePayload);
    payload.addAll(
      ChurchFeedMediaStorageFields.buildStoragePathOnlyFields(
        photoPaths: existingPaths,
        aspectRatio: aspectRatio,
        hasVideo: hasVideo,
        videoPath: videoStoragePath,
        allowDeleteSentinels: !isNewDoc,
        isEvento: isEvento,
      ),
    );
    payload['ativo'] = true;
    payload['publicado'] = true;
    payload['status'] = 'publicado';
    payload['publicSite'] = publicSite;
    payload['updatedAt'] = FieldValue.serverTimestamp();
    if (isNewDoc) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    if (isEvento) {
      await EventosOfflineSync.set(
        ref: docRef,
        data: payload,
        tenantId: tenantId,
        merge: !isNewDoc,
      );
    } else {
      await AvisosOfflineSync.set(
        ref: docRef,
        data: payload,
        tenantId: tenantId,
        merge: !isNewDoc,
      );
    }
  }

  static double _aspectRatioFromPayload(Map<String, dynamic> payload) {
    final prev = payload['media_info'];
    if (prev is Map) {
      final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
      if (oar is num) return oar.toDouble().clamp(0.45, 1.9);
    }
    return 1.0;
  }

  static Future<void> _backgroundPublish({
    required String label,
    required Future<String> Function() publish,
  }) async {
    try {
      await publish();
    } catch (e, st) {
      SyncService.endSyncError();
      if (kDebugMode) {
        debugPrint('ChurchFeedOptimisticPublishService.$label: $e\n$st');
      }
    }
  }
}
