import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';

/// Publicação de evento — um único caminho: Firebase OK → upload → Firestore.
///
/// Storage: `igrejas/{churchId}/eventos/{postId}/…` e `…/eventos/videos/{postId}_v0.mp4`
abstract final class EventoPublishService {
  EventoPublishService._();

  static String resolveChurchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint.trim());

  static DocumentReference<Map<String, dynamic>> docRef({
    required String churchId,
    required String docId,
  }) =>
      EventosPublishVerificationService.eventoDocRef(
        igrejaId: churchId,
        docId: docId,
      );

  /// Bootstrap + pipeline linear (fotos novas só aqui — não em background).
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
    void Function(double progress)? onUploadProgress,
  }) async {
    final churchId = resolveChurchId(tenantId);
    return FirebaseBootstrapService.runGuarded(
      () async {
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: 'evento_publish',
        );
        return ChurchFeedLinearPublishService.publishEvento(
          docRef: docRef,
          tenantId: churchId,
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
          onUploadProgress: onUploadProgress,
        );
      },
      debugLabel: 'evento_publish',
      requireAuth: true,
    );
  }
}
