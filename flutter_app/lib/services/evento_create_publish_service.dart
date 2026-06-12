import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/services/evento_publish_service.dart';

/// Publicação de evento — bootstrap explícito antes de Storage/Firestore.
///
/// Paths: `igrejas/{churchId}/eventos/{postId}` + Storage canónico.
abstract final class EventoCreatePublishService {
  EventoCreatePublishService._();

  static Future<void> ensureReady({String logLabel = 'evento_create'}) async {
    await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: false);
    await ensureFirebaseReadyForPublishUpload();
    await AppFinalizeBootstrap.ensureSessionForPublish(logLabel: logLabel);
  }

  static Future<String> publish({
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
    String? agendaCategory,
    String? agendaColorHex,
    void Function(double progress)? onUploadProgress,
  }) async {
    await ensureReady(logLabel: 'evento_create_publish');
    return EventoPublishService.publish(
      docRef: docRef,
      tenantId: tenantId,
      corePayload: corePayload,
      isNewDoc: isNewDoc,
      existingUrls: existingUrls,
      startSlotIndex: startSlotIndex,
      hasVideo: hasVideo,
      newImagesBytes: newImagesBytes,
      newImagePaths: newImagePaths,
      videoStoragePath: videoStoragePath,
      publicSite: publicSite,
      eventStartAt: eventStartAt,
      location: location,
      syncAgenda: true,
      agendaCategory: agendaCategory,
      agendaColorHex: agendaColorHex,
      onUploadProgress: onUploadProgress,
    );
  }
}
