import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/evento_publish_service.dart';

/// Evento — fachada legada → [EventoPublishService].
abstract final class EventoStrictPublishService {
  EventoStrictPublishService._();

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
    String? localVideoPath,
    bool publicSite = true,
    DateTime? eventStartAt,
    String? location,
    bool syncAgenda = true,
    String? agendaCategory,
    String? agendaColorHex,
    void Function(double progress)? onUploadProgress,
  }) =>
      EventoPublishService.publish(
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
        localVideoPath: localVideoPath,
        publicSite: publicSite,
        eventStartAt: eventStartAt,
        location: location,
        syncAgenda: syncAgenda,
        agendaCategory: agendaCategory,
        agendaColorHex: agendaColorHex,
        onUploadProgress: onUploadProgress,
      );
}
