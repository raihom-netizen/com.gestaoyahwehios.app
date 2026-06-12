import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';

/// Publicação de aviso — Firebase OK → upload Storage → Firestore → distribuição.
///
/// Storage: `igrejas/{churchId}/avisos/{postId}/capa_aviso.jpg` + `galeria_XX.jpg`
abstract final class AvisoPublishService {
  AvisoPublishService._();

  static String resolveChurchId(String tenantHint) =>
      ChurchRepository.churchId(tenantHint.trim());

  static DocumentReference<Map<String, dynamic>> docRef({
    required String churchId,
    required String docId,
  }) =>
      AvisosPublishVerificationService.avisoDocRef(
        igrejaId: churchId,
        docId: docId,
      );

  static Future<void> ensureReady({String logLabel = 'aviso_prepare'}) async {
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
    List<Uint8List>? newImagesBytes,
    List<String>? newImagePaths,
    bool publicSite = true,
    DateTime? calendarDate,
    bool syncCalendar = true,
    void Function(double progress)? onUploadProgress,
  }) async {
    final churchId = resolveChurchId(tenantId);
    return FirebaseBootstrapService.runGuarded(
      () async {
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: 'aviso_publish',
        );
        return ChurchFeedLinearPublishService.publishAviso(
          docRef: docRef,
          tenantId: churchId,
          corePayload: corePayload,
          isNewDoc: isNewDoc,
          existingPhotoRefs: existingUrls,
          startSlotIndex: startSlotIndex,
          newImagesBytes: newImagesBytes,
          newImagePaths: newImagePaths,
          publicSite: publicSite,
          calendarDate: calendarDate,
          syncCalendar: syncCalendar,
          onUploadProgress: onUploadProgress,
        );
      },
      debugLabel: 'aviso_publish',
      requireAuth: true,
    );
  }
}
