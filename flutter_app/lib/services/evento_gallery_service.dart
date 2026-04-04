import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import 'media_upload_service.dart';
import 'video_duration.dart';

/// Regra de negócio: cada evento pode ter no máximo 2 vídeos (60s cada), 20 fotos.
/// Vídeos: verificação de duração no upload; fotos: comprimidas em Full HD (1920x1080).
/// Gera thumbnail para carregamento instantâneo no mural; persiste getDownloadURL() no Firestore.
class EventoGalleryService {
  EventoGalleryService._();
  static final EventoGalleryService instance = EventoGalleryService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const int _maxVideosPerEvent = 2;
  static const int _maxVideoSeconds = 60;
  static const int _maxPhotosPerEvent = 20;
  static const int _photoQuality = 90;
  static const int _photoMaxWidth = 1920;
  static const int _photoMaxHeight = 1080;

  /// Adiciona mídia a um evento da coleção [eventos] (por eventoId).
  /// Vídeo: verifica limite de 2 por evento, comprime (DefaultQuality), gera thumb, faz upload e salva URL + thumb.
  /// Foto: upload em alta resolução e salva URL (getDownloadURL).
  Future<void> adicionarMidiaAoEvento(String eventoId, File arquivo, bool isVideo) async {
    final eventoRef = _firestore.collection('eventos').doc(eventoId);
    final storagePrefix = 'eventos/$eventoId';
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

    await FirebaseAuth.instance.currentUser?.getIdToken(true);

    final fileName = '${DateTime.now().millisecondsSinceEpoch}';

    if (isVideo) {
      final MediaInfo? info = await VideoCompress.compressVideo(
        arquivo.path,
        quality: VideoQuality.DefaultQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      if (info == null || info.file == null) throw Exception('Falha ao comprimir o vídeo.');

      File? thumbFile;
      try {
        thumbFile = await VideoCompress.getFileThumbnail(arquivo.path);
      } catch (_) {}

      final videoUrl = await _uploadToStorage(
        storagePathPrefix,
        info.file!,
        '$fileName.mp4',
        'video/mp4',
      );
      String thumbUrl = '';
      if (thumbFile != null && thumbFile.existsSync()) {
        thumbUrl = await _uploadToStorage(
          storagePathPrefix,
          thumbFile,
          'thumb_$fileName.jpg',
          'image/jpeg',
        );
      }

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
