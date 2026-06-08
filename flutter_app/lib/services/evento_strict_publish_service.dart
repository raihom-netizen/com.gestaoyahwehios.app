import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/eventos_publish_verification_service.dart';
import 'package:gestao_yahweh/services/feed_media_publish_service.dart';
import 'package:gestao_yahweh/services/feed_publish_preflight.dart';
import 'package:gestao_yahweh/services/mural_post_media_payload.dart';
import 'package:gestao_yahweh/services/publication_engine.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show dedupeImageRefsByStorageIdentity;

/// Publicação de evento — upload validado → Firestore → confirmação (sem falso sucesso).
abstract final class EventoStrictPublishService {
  EventoStrictPublishService._();

  /// PASSO 3–9: fotos → vídeo (já no Storage) → verificar → Firestore → confirmar.
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
  }) async {
    await FeedPublishPreflight.prepareForFirestoreSave();

    var allUrls = dedupeImageRefsByStorageIdentity(existingUrls);

    if (newImagesBytes != null && newImagesBytes.isNotEmpty) {
      final uploaded = await MuralPostMediaPayload.uploadNewPhotosBeforePublish(
        tenantId: tenantId,
        postType: 'evento',
        postId: docRef.id,
        newImages: newImagesBytes,
        startSlotIndex: startSlotIndex,
      );
      allUrls = dedupeImageRefsByStorageIdentity([...allUrls, ...uploaded]);
    } else if (newImagePaths != null && newImagePaths.isNotEmpty) {
      final uploaded =
          await MuralPostMediaPayload.uploadNewPhotosBeforePublishFromPaths(
        tenantId: tenantId,
        postType: 'evento',
        postId: docRef.id,
        localPaths: newImagePaths,
        startSlotIndex: startSlotIndex,
      );
      allUrls = dedupeImageRefsByStorageIdentity([...allUrls, ...uploaded]);
    }

    final fotoPaths = EventosPublishVerificationService.storagePathsFromUrls(
      allUrls,
    );

    await EventosPublishVerificationService.verifyStorageMetadata(
      photoPaths: fotoPaths,
      videoPath: videoStoragePath,
    );

    final aspectRatio = (corePayload['media_info'] is Map
            ? (corePayload['media_info'] as Map)['aspect_ratio']
            : null) is num
        ? ((corePayload['media_info'] as Map)['aspect_ratio'] as num)
            .toDouble()
        : 1.0;

    final payload = Map<String, dynamic>.from(corePayload);
    payload.addAll(
      MuralPostMediaPayload.buildMediaFields(
        allUrls: allUrls,
        aspectRatio: aspectRatio.clamp(0.45, 1.9),
        hasVideo: hasVideo,
        allowDeleteSentinels: !isNewDoc,
      ),
    );
    payload['fotos'] = fotoPaths;
    if (videoStoragePath != null && videoStoragePath.trim().isNotEmpty) {
      payload['videoPath'] = videoStoragePath.trim();
    }
    payload['ativo'] = true;
    payload['publicado'] = true;
    payload['status'] = 'publicado';

    await FeedMediaPublishService.publishNow(
      docRef: docRef,
      payload: payload,
      isNewDoc: isNewDoc,
      postType: 'evento',
      publicSite: publicSite,
    );

    await EventosPublishVerificationService.verifyDocumentExists(docRef);

    PublicationEngine.scheduleDistribution(
      tenantId: tenantId,
      kind: PublicationKind.evento,
      postId: docRef.id,
      isNewDoc: isNewDoc,
      publicSite: publicSite,
    );

    return docRef.id;
  }
}
