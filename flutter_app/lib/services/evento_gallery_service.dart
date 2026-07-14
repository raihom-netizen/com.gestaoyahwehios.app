import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/data/church_ui_collections.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart'
    show kMediaEventVideoMaxSeconds, kStandardUploadImageQuality;
import 'package:gestao_yahweh/core/repositories/church_repository.dart';
import 'package:gestao_yahweh/services/evento_media_upload.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxEventFeedPhotosPerPost;
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_event_video_upload.dart';
import 'package:gestao_yahweh/services/church_media_upload_facade.dart';
import 'package:gestao_yahweh/services/video_duration.dart';

/// Galeria de evento — `igrejas/{churchId}/eventos/{eventoId}/…`.
///
/// Fotos via [EventoMediaUpload] / [UnifiedUploadService] (anti `firebase_core/no-app`).
class EventoGalleryService {
  EventoGalleryService._();
  static final EventoGalleryService instance = EventoGalleryService._();

  static const int _maxVideosPerEvent = 2;
  static const int _maxVideoSeconds = kMediaEventVideoMaxSeconds;
  static const int _maxPhotosPerEvent = kMaxEventFeedPhotosPerPost;
  static const int _photoQuality = kStandardUploadImageQuality;
  static const int _photoMaxWidth = 1920;
  static const int _photoMaxHeight = 1920;

  /// Adiciona mídia a um evento em `igrejas/{tenantId}/eventos/{eventoId}`.
  Future<void> adicionarMidiaAoEvento(
    String tenantId,
    String eventoId,
    File arquivo,
    bool isVideo,
  ) async {
    final churchId = ChurchRepository.churchId(tenantId.trim());
    final eventoRef = ChurchUiCollections.eventos(churchId).doc(eventoId);
    final storagePrefix =
        '${ChurchStorageLayout.churchRoot(churchId)}/${ChurchStorageLayout.kSegEventos}/$eventoId';
    await adicionarMidiaAoEventoRef(
      eventoRef,
      storagePrefix,
      arquivo,
      isVideo,
      photoField: 'fotos',
    );
  }

  /// Adiciona mídia a um evento referenciado por [eventRef].
  Future<void> adicionarMidiaAoEventoRef(
    DocumentReference<Map<String, dynamic>> eventRef,
    String storagePathPrefix,
    File arquivo,
    bool isVideo, {
    String photoField = 'imageUrls',
  }) async {
    await FirebaseBootstrapService.runGuarded(
      () async {
        await EventoMediaUpload.ensureUploadReady();

        if (isVideo) {
          await _adicionarVideo(eventRef, storagePathPrefix, arquivo);
        } else {
          await _adicionarFoto(
            eventRef,
            storagePathPrefix,
            arquivo,
            photoField: photoField,
          );
        }
      },
      debugLabel: 'evento_gallery_media',
    );
  }

  Future<void> _adicionarVideo(
    DocumentReference<Map<String, dynamic>> eventRef,
    String storagePathPrefix,
    File arquivo,
  ) async {
    final snap = await eventRef.get();
    final data = snap.data();
    final videosAtuais = (data != null && data['videos'] != null)
        ? (data['videos'] is List ? data['videos'] as List : [])
        : <dynamic>[];
    if (videosAtuais.length >= _maxVideosPerEvent) {
      throw Exception(
        'Limite atingido: cada evento pode ter no máximo $_maxVideosPerEvent vídeos.',
      );
    }
    final durationSec = await getVideoDurationSeconds(XFile(arquivo.path));
    if (durationSec != null && durationSec > _maxVideoSeconds) {
      throw Exception(
        'Vídeo deve ter no máximo $_maxVideoSeconds segundos. Este tem $durationSec s.',
      );
    }

    final prepared = await MediaService.prepareEventVideoForUpload(arquivo.path);
    if (prepared == null) {
      throw Exception('Falha ao preparar o vídeo para envio.');
    }
    final compressed = File(prepared.outputPath);
    final thumbFile = prepared.thumbnailFile;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}';
    final storageVideoPath = '$storagePathPrefix/$fileName.mp4';

    await StorageUploadPersistenceService.enqueueFileJob(
      storagePath: storageVideoPath,
      localFilePath: compressed.path,
      contentType: 'video/mp4',
    );

    final videoUrl = await EcoFireEventVideoUpload.putVideoFile(
      storagePath: storageVideoPath,
      file: compressed,
    );

    var thumbUrl = '';
    if (thumbFile != null && thumbFile.existsSync()) {
      final thumbBytes = await thumbFile.readAsBytes();
      final thumbResult = await ChurchMediaUploadFacade.uploadMidia(
        bytes: thumbBytes,
        storagePath: '$storagePathPrefix/video_poster_$fileName.jpg',
        logLabel: 'evento_video_thumb',
        alreadyCompressed: true,
        compressForFeed: false,
      );
      thumbUrl = thumbResult.downloadUrl;
    }

    final novoVideo = {
      'url': videoUrl,
      'thumb': thumbUrl,
      'videoUrl': videoUrl,
      'thumbUrl': thumbUrl,
    };
    final fresh = await eventRef.get();
    final list = fresh.exists && fresh.data() != null
        ? List<Map<String, dynamic>>.from(
            (fresh.data()!['videos'] as List?) ?? [],
          )
        : <Map<String, dynamic>>[];
    list.add(novoVideo);
    await eventRef.set({'videos': list}, SetOptions(merge: true));
  }

  Future<void> _adicionarFoto(
    DocumentReference<Map<String, dynamic>> eventRef,
    String storagePathPrefix,
    File arquivo, {
    required String photoField,
  }) async {
    final snap = await eventRef.get();
    final data = snap.data();
    final fotosAtuais = (data != null && data[photoField] != null)
        ? (data[photoField] is List ? (data[photoField] as List).length : 0)
        : 0;
    if (fotosAtuais >= _maxPhotosPerEvent) {
      throw Exception(
        'Limite atingido: cada evento pode ter no máximo $_maxPhotosPerEvent fotos.',
      );
    }

    final fileToUpload = await _compressPhotoToFullHd(arquivo);
    final bytes = await fileToUpload.readAsBytes();
    if (fileToUpload.path != arquivo.path && fileToUpload.existsSync()) {
      try {
        fileToUpload.deleteSync();
      } catch (_) {}
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}';
    final storagePath = '$storagePathPrefix/$fileName.jpg';
    final uploaded = await ChurchMediaUploadFacade.uploadMidia(
      bytes: bytes,
      storagePath: storagePath,
      logLabel: 'evento_galeria_foto',
      alreadyCompressed: fileToUpload.path != arquivo.path,
    );
    final downloadUrl = uploaded.downloadUrl;

    final fresh = await eventRef.get();
    final list = fresh.exists && fresh.data() != null
        ? List<String>.from(
            (fresh.data()![photoField] as List?)?.map((e) => e.toString()) ??
                [],
          )
        : <String>[];
    list.add(downloadUrl);
    await eventRef.set({photoField: list}, SetOptions(merge: true));
  }

  Future<File> _compressPhotoToFullHd(File arquivo) async {
    if (kIsWeb) return arquivo;
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}_event_fhd.jpg',
    );
    final result = await FlutterImageCompress.compressAndGetFile(
      arquivo.path,
      targetPath,
      quality: _photoQuality,
      minWidth: _photoMaxWidth,
      minHeight: _photoMaxHeight,
    );
    if (result != null) {
      final compressedFile = File(result.path);
      if (compressedFile.existsSync()) return compressedFile;
    }
    return arquivo;
  }
}
