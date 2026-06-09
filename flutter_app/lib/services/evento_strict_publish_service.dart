import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/church_feed_optimistic_publish_service.dart';

/// Evento — pipeline linear: upload → Storage → Firestore → agenda → sucesso.
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
    bool publicSite = true,
    DateTime? eventStartAt,
    String? location,
    bool syncAgenda = true,
    String? agendaCategory,
    String? agendaColorHex,
  }) =>
      ChurchFeedOptimisticPublishService.publishEvento(
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
        syncAgenda: syncAgenda,
        agendaCategory: agendaCategory,
        agendaColorHex: agendaColorHex,
      );
}
