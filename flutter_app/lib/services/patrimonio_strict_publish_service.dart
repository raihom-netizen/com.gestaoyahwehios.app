import 'dart:typed_data';

import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/services/patrimonio_publish_service.dart';

/// Fachada legada → [PatrimonioPublishService] (Ecofire linear).
abstract final class PatrimonioStrictPublishService {
  PatrimonioStrictPublishService._();

  static const String photoUploadStateField =
      EntityPublishStatus.photoUploadStateField;
  static const String statePublished = EntityPublishStatus.published;

  static Future<void> publish({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    required List<Uint8List> newImages,
    required int startSlot,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
    String? userUid,
    void Function(double progress)? onUploadProgress,
  }) =>
      PatrimonioPublishService.publish(
        seedTenantId: seedTenantId,
        itemId: itemId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        newImages: newImages,
        startSlot: startSlot,
        existingPaths: existingPaths,
        existingUrls: existingUrls,
        userUid: userUid,
        onUploadProgress: onUploadProgress,
      );

  static Future<void> publishMetadataOnly({
    required String seedTenantId,
    required String itemId,
    required Map<String, dynamic> corePayload,
    required bool isNewDoc,
    List<String> existingPaths = const [],
    List<String> existingUrls = const [],
    String? userUid,
  }) =>
      PatrimonioPublishService.publishMetadataOnly(
        seedTenantId: seedTenantId,
        itemId: itemId,
        corePayload: corePayload,
        isNewDoc: isNewDoc,
        existingPaths: existingPaths,
        existingUrls: existingUrls,
        userUid: userUid,
      );
}
