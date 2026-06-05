import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:gestao_yahweh/core/media_upload_limits.dart'
    show kMediaEventVideoMaxSeconds, kStandardUploadImageQuality;
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart'
    show kMaxEventFeedPhotosPerPost;
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/services/firestore_stream_utils.dart';
import 'package:gestao_yahweh/services/storage_upload_persistence_service.dart';

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase/firebase_service.dart';
import 'media_upload_service.dart';
import 'video_duration.dart';

/// Regra de negócio: cada evento pode ter no máximo 2 vídeos (90s cada), 20 fotos.
/// Vídeos: verificação de duração no upload; fotos: comprimidas em Full HD (1920x1080).
/// Vídeo: capa estática no Storage como `video_poster_*.jpg` (sem prefixo `thumb_`); URL no Firestore.
class EventoGalleryService {
  EventoGalleryService._();
  static final EventoGalleryService instance = EventoGalleryService._();

  Future<FirebaseFirestore> _firestore() => FirebaseService.firestore(requireAuth: true);
  static const int _maxVideosPerEvent = 2;
  static const int _maxVideoSeconds = kMediaEventVideoMaxSeconds;
  static const int _maxPhotosPerEvent = kMaxEventFeedPhotosPerPost;
  static const int _photoQuality = kStandardUploadImageQuality;
  static const int _photoMaxWidth = 1920;
  static const int _photoMaxHeight = 1080;

  /// Adiciona mídia a um evento em `igrejas/{tenantId}/eventos/{eventoId}`.
  /// Vídeo: MP4/M4V ≤26 MB envia direto; senão comprime 720p HD, thumb, upload e salva URL + thumb.
  /// Foto: upload em alta resolução e salva URL (getDownloadURL).
  Future<void> adicionarMidiaAoEvento(
    String tenantId,
    String eventoId,
    File arquivo,
    bool isVideo,
  ) async {
    final db = await _firestore();
    final tid = tenantId.trim();
    final eventoRef = db
        .collection('igrejas')
        .doc(tid)
        .collection('eventos')
        .doc(eventoId);
    final storagePrefix =
        '${ChurchStorageLayout.churchRoot(tid)}/${ChurchStorageLayout.kSegEventos}/$eventoId';
    await adicionarMidiaAoEventoRef(
      eventoRef,
      storagePrefix,
      arquivo,
      isVideo,
      photoField: 'fotos',
    );
  }

  /// Adiciona mídia a um evento referenciado por [eventRef] (ex.: tenants/tenantId/noticias/docId).
  /// [storagePathPrefix] ex.: 'tenants/xyz/eventos/docId'. [photoField]: 'fotos' ou 'imageUrls'.
  Future<void> adicionarMidiaAoEventoRef(
    DocumentReference<Map<String, dynamic>> eventRef,
    String storagePathPrefix,
    File arquivo,
    bool isVideo, {
    String photoField = 'imageUrls',
  }) async {
    await ensureFirebaseReadyForMediaUpload();
    if (isVideo) {
      final snap = await eventRef.get();
      final data = snap.data();
      final videosAtuais = (data != null && data['videos'] != null)
          ? (data['videos'] is List ? data['videos'] as List : [])
          : <dynamic>[];
      if (videosAtuais.length >= _maxVideosPerEvent) {
        throw Exception('Limite atingido: cada evento pode ter no máximo $_maxVideosPerEvent vídeos.');
      }
      final durationSec = await getVideoDurationSeconds(XFile(arquivo.path));
      if (durationSec != null && durationSec > _maxVideoSeconds) {
        throw Exception('Vídeo deve ter no máximo $_maxVideoSeconds segundos. Este tem $durationSec s.');
      }
    } else {
      final snap = await eventRef.get();
      final data = snap.data();
      final fotosAtuais = (data != null && data[photoField] != null)
          ? (data[photoField] is List ? (data[photoField] as List).length : 0)
          : 0;
      if (fotosAtuais >= _maxPhotosPerEvent) {
        throw Exception('Limite atingido: cada evento pode ter no máximo $_maxPhotosPerEvent fotos.');
      }
    }

    await FirestoreStreamUtils.refreshAuthTokenIfNeeded(force: true);

    final fileName = '${DateTime.now().millisecondsSinceEpoch}';

    if (isVideo) {
      final prepared = await MediaService.prepareEventVideoForUpload(arquivo.path);
      if (prepared == null) {
        throw Exception('Falha ao preparar o vídeo para envio.');
      }
      final compressed = File(prepared.outputPath);
      File? thumbFile = prepared.thumbnailFile;
      final storageVideoPath = '$storagePathPrefix/$fileName.mp4';

      await StorageUploadPersistenceService.enqueueFileJob(
        storagePath: storageVideoPath,
        localFilePath: compressed.path,
        contentType: 'video/mp4',
      );

      final videoUrlFuture = _uploadToStorage(
        storagePathPrefix,
        compressed,
        '$fileName.mp4',
        'video/mp4',
      );
      final thumbUrlFuture = (thumbFile != null && thumbFile.existsSync())
          ? _uploadToStorage(
              storagePathPrefix,
              thumbFile,
              'video_poster_$fileName.jpg',
              'image/jpeg',
            )
          : Future<String>.value('');
      final urls = await Future.wait([videoUrlFuture, thumbUrlFuture]);
      final videoUrl = urls[0];
      final thumbUrl = urls[1];

      final novoVideo = {
        'url': videoUrl,
        'thumb': thumbUrl,
        'videoUrl': videoUrl,
        'thumbUrl': thumbUrl,
      };
      final snap = await eventRef.get();
      final list = snap.exists && snap.data() != null
          ? List<Map<String, dynamic>>.from((snap.data()!['videos'] as List?) ?? [])
          : <Map<String, dynamic>>[];
      list.add(novoVideo);
      await eventRef.set({'videos': list}, SetOptions(merge: true));
    } else {
      final File fileToUpload = await _compressPhotoToFullHd(arquivo);
      final downloadUrl = await _uploadToStorage(
        storagePathPrefix,
        fileToUpload,
        '$fileName.jpg',
        'image/jpeg',
      );
      if (fileToUpload.path != arquivo.path && fileToUpload.existsSync()) {
        try { fileToUpload.deleteSync(); } catch (_) {}
      }
      final snap = await eventRef.get();
      final list = snap.exists && snap.data() != null
          ? List<String>.from((snap.data()![photoField] as List?)?.map((e) => e.toString()) ?? [])
          : <String>[];
      list.add(downloadUrl);
      await eventRef.set({photoField: list}, SetOptions(merge: true));
    }
  }

  /// Comprime foto para Full HD (1920x1080) mantendo proporção; qualidade 90.
  Future<File> _compressPhotoToFullHd(File arquivo) async {
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_event_fhd.jpg');
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

  Future<String> _uploadToStorage(
    String pathPrefix,
    File file,
    String name,
    String contentType,
  ) async {
    return MediaUploadService.uploadFileWithRetry(
      storagePath: '$pathPrefix/$name',
      file: file,
      contentType: contentType,
    );
  }
}
