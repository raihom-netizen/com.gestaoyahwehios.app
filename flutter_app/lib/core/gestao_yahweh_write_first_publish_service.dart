import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/ecofire_feed_publish_service.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';

/// **Write-First / Async-Storage** — padrão Controle Total do Gestão YAHWEH.
///
/// 1. Texto + metadados → Firestore imediato ([TenantOfflineWrite] via outbox)
/// 2. UI fecha (`Navigator.pop` + [EcofirePublishProgressUi.schedule])
/// 3. Mídia → Storage em background ([MuralPublishOutboxService] + [BackgroundUploadWorker])
///
/// **Proibido** neste módulo:
/// - `FirebaseFirestore.instance` / `FirebaseStorage.instance`
/// - ID de igreja hardcoded
/// - `localMediaPaths` / `syncStatus` genéricos / `downloadURL` antes do Storage
abstract final class GestaoYahwehWriteFirstPublishService {
  GestaoYahwehWriteFirstPublishService._();

  static String resolveChurchId(String hint) => ChurchRepository.churchId(hint);

  /// Avisos / eventos com fotos novas — **nunca** bloqueia upload antes do Firestore.
  static Future<String> publishFeedWithPendingMedia({
    required DocumentReference<Map<String, dynamic>> docRef,
    required String churchId,
    required String docId,
    required String postType,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<String> existingUrls,
    required int startSlotIndex,
    required bool hasVideo,
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    void Function(double progress)? onUploadProgress,
  }) async {
    final payload = Map<String, dynamic>.from(corePayload);
    if (existingUrls.isNotEmpty) {
      final urls =
          await EcoFireFeedPublishService.refsToPlayableUrls(existingUrls);
      if (urls.isNotEmpty) {
        payload.addAll(
          MuralPostMediaPayload.buildMediaFields(
            allUrls: urls,
            aspectRatio: _aspectFromPayload(payload),
            hasVideo: hasVideo,
            allowDeleteSentinels: !isNewDoc,
          ),
        );
      }
    }
    if (!isNewDoc) {
      payload['imageVariants'] = FieldValue.delete();
    }

    await EcoFireResilientPublish.queueFeedPublish(
      churchId: churchId,
      docId: docId,
      postType: postType,
      docRef: docRef,
      corePayload: payload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      bytesList: newImagesBytes,
      localPaths: newImagePaths,
    );
    EcoFireResilientPublish.scheduleSync(reason: '${postType}_write_first');
    onUploadProgress?.call(1.0);
    return docId;
  }

  /// Financeiro — lançamento **já** gravado; comprovante só em fila Storage.
  static Future<void> queueFinanceComprovanteAfterSave({
    required String churchId,
    required DocumentReference<Map<String, dynamic>> docRef,
    required Uint8List bytes,
    required String mimeType,
    String? fileName,
    DateTime? referenceDate,
    String? previousStoragePath,
    String? previousDownloadUrl,
  }) async {
    await EcoFireResilientPublish.queueFinanceComprovante(
      churchId: churchId,
      docRef: docRef,
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      referenceDate: referenceDate,
      previousStoragePath: previousStoragePath,
      previousDownloadUrl: previousDownloadUrl,
    );
    EcoFireResilientPublish.scheduleSync(reason: 'finance_comprovante_write_first');
  }

  static double _aspectFromPayload(Map<String, dynamic> payload) {
    final prev = payload['media_info'];
    if (prev is Map) {
      final oar = prev['aspect_ratio'] ?? prev['aspectRatio'];
      if (oar is num) return oar.toDouble().clamp(0.45, 1.9);
    }
    return 1.0;
  }
}
