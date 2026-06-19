import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/church_publish_flow_log.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_resilient_publish.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/avisos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/church_feed_linear_publish_service.dart';
import 'package:gestao_yahweh/services/church_publish_context.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Publicação de aviso — pipeline **linear** único: bootstrap → Storage → Firestore → site.
///
/// Proibido neste módulo: `publishState`, stub Firestore antes do Storage, write-first.
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

  /// Núcleo Firebase + Auth (sem warm de upload).
  static Future<void> ensureReady({String logLabel = 'aviso_prepare'}) async {
    await EcoFirePublishBootstrap.ensureHard(
      logLabel: logLabel,
      strict: true,
    );
  }

  /// Bootstrap EcoFire — Firebase + Storage + Auth (sem warm duplicado).
  static Future<void> prepareFullPipeline({
    String logLabel = 'aviso_prepare',
    bool withPhotos = true,
    void Function(double progress)? onProgress,
  }) async {
    onProgress?.call(0.06);
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          FirebaseBootstrapService.resetPublishWarmState();
          await FirebaseBootstrapService.ensureStorageAlwaysLinked(
            refreshAuthToken: true,
          );
        }
        await AppFinalizeBootstrap.ensureSessionForPublish(
          logLabel: withPhotos ? '${logLabel}_photos' : logLabel,
        );
        if (withPhotos) {
          await ensureFirebaseReadyForMediaUpload();
        }
        await EcoFirePublishBootstrap.ensureHard(
          logLabel: withPhotos ? '${logLabel}_photos' : logLabel,
          strict: true,
        );
        onProgress?.call(0.12);
        if (kIsWeb) {
          await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
        }
        onProgress?.call(0.14);
        return;
      } catch (e, st) {
        last = e;
        ChurchPublishFlowLog.logCatch(e, st, label: 'aviso_bootstrap_$attempt');
        if (attempt < 2 && isFirebaseNoAppError(e)) {
          await Future<void>.delayed(
            Duration(milliseconds: 320 * (attempt + 1)),
          );
          continue;
        }
        rethrow;
      }
    }
    if (last != null) {
      if (last is Exception) throw last;
      throw StateError(last.toString());
    }
    throw StateError('Firebase indisponível ($logLabel).');
  }

  /// Upload Storage (`capa_aviso.jpg`) → metadados + `imageUrl` → Firestore → distribuição.
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
    final churchId = ChurchPublishContext.churchIdForPublish(tenantId);
    final hasNewPhotos =
        (newImagesBytes?.isNotEmpty ?? false) ||
        (newImagePaths?.isNotEmpty ?? false);

    if (isNewDoc && !hasNewPhotos && existingUrls.isEmpty) {
      throw StateError('Adicione pelo menos uma foto válida ao aviso.');
    }

    await prepareFullPipeline(
      logLabel: hasNewPhotos ? 'aviso_publish_photos' : 'aviso_publish',
      withPhotos: hasNewPhotos,
      onProgress: onUploadProgress == null
          ? null
          : (p) => onUploadProgress!(p.clamp(0.06, 0.14)),
    );

    try {
      return await ChurchFeedLinearPublishService.publishAviso(
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
    } catch (e) {
      if (EcoFireResilientPublish.shouldQueueSilently(e)) {
        ChurchPublishFlowLog.logCatch(e, StackTrace.current, label: 'aviso_offline');
        rethrow;
      }
      rethrow;
    }
  }
}
