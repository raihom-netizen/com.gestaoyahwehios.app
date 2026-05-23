import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show
        eventNoticiaPhotoUrls,
        eventNoticiaVideosFromDoc,
        looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/services/video_handler_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageObjectPathFromHttpUrl,
        isFirebaseStorageHttpUrl,
        sanitizeImageUrl;
import 'package:image_picker/image_picker.dart';

/// Vídeos hospedados no Storage para posts do mural (avisos/eventos em `noticias`).
class MuralPostHostedVideoEditor {
  MuralPostHostedVideoEditor({
    required this.tenantId,
    required this.postDocRef,
    required this.maxVideos,
    this.maxVideoSeconds = 60,
  });

  final String tenantId;
  final DocumentReference<Map<String, dynamic>> postDocRef;
  final int maxVideos;
  final int maxVideoSeconds;

  final List<Map<String, String>> videos = [];

  static List<Map<String, String>> loadFromDoc(Map<String, dynamic>? data) {
    return eventNoticiaVideosFromDoc(data)
        .map(
          (e) => <String, String>{
            'videoUrl': (e['videoUrl'] ?? '').toString(),
            'thumbUrl': (e['thumbUrl'] ?? '').toString(),
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> firestoreVideosPayload() => videos
      .map(
        (e) => <String, dynamic>{
          'videoUrl': (e['videoUrl'] ?? '').toString().trim(),
          'thumbUrl': (e['thumbUrl'] ?? '').toString().trim(),
        },
      )
      .where((m) => (m['videoUrl'] as String).isNotEmpty)
      .toList();

  String primaryVideoUrl(String youtubeOrVimeoFallback) {
    if (videos.isNotEmpty) {
      final u = (videos.first['videoUrl'] ?? '').toString().trim();
      if (u.isNotEmpty) return u;
    }
    return youtubeOrVimeoFallback.trim();
  }

  String primaryThumbUrl() =>
      videos.isNotEmpty ? (videos.first['thumbUrl'] ?? '').toString() : '';

  bool get hasHostedVideo =>
      videos.any((v) => (v['videoUrl'] ?? '').toString().trim().isNotEmpty);

  int? hostedVideoStorageSlotFromUrl(String videoUrl) {
    final u = sanitizeImageUrl(videoUrl.trim());
    if (u.isEmpty || !isFirebaseStorageHttpUrl(u)) return null;
    final path = firebaseStorageObjectPathFromHttpUrl(u);
    if (path == null || path.isEmpty) return null;
    if (!path.contains('/eventos/videos/')) return null;
    final m = RegExp(r'_v(\d+)\.mp4$', caseSensitive: false).firstMatch(path);
    if (m != null) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null) return n.clamp(0, 1);
    }
    return null;
  }

  int nextHostedVideoStorageSlot() {
    final used = <int>{};
    for (var i = 0; i < videos.length; i++) {
      final url = (videos[i]['videoUrl'] ?? '').toString();
      final s = hostedVideoStorageSlotFromUrl(url);
      if (s != null) {
        used.add(s);
      } else {
        final u = sanitizeImageUrl(url.trim());
        final p = firebaseStorageObjectPathFromHttpUrl(u) ?? '';
        if (u.isNotEmpty &&
            isFirebaseStorageHttpUrl(u) &&
            p.contains('/eventos/videos/')) {
          used.add(i.clamp(0, 1));
        }
      }
    }
    for (var s = 0; s < maxVideos; s++) {
      if (!used.contains(s)) return s;
    }
    return -1;
  }

  Future<({bool added, String? error})> pickAndUploadHostedVideo({
    required void Function(void Function()) setState,
    required bool Function() mounted,
    required void Function(String message) showSnack,
  }) async {
    if (videos.length >= maxVideos) {
      showSnack(
        'Limite de $maxVideos vídeo(s) por publicação. Remova um para adicionar outro.',
      );
      return (added: false, error: 'limit');
    }
    final snap = await postDocRef.get();
    final existing = eventNoticiaVideosFromDoc(snap.data());
    if (existing.length >= maxVideos) {
      showSnack(
        'Esta publicação já tem o máximo de vídeos. Remova um para adicionar outro.',
      );
      return (added: false, error: 'limit');
    }
    final slot = nextHostedVideoStorageSlot();
    if (slot < 0) {
      showSnack('Limite de vídeos no armazenamento. Remova um vídeo.');
      return (added: false, error: 'slot');
    }

    if (kIsWeb) {
      try {
        showSnack('A preparar vídeo. Máx. ${maxVideoSeconds}s.');
        final result = await VideoHandlerService.instance.pickCompressAndUpload(
          tenantId: tenantId,
          eventPostDocId: postDocRef.id,
          videoSlotIndex: slot,
          maxDuration: Duration(seconds: maxVideoSeconds),
        );
        if (result == null) return (added: false, error: 'cancel');
        videos.add({
          'videoUrl': result.videoUrl,
          'thumbUrl': result.thumbUrl,
        });
        setState(() {});
        return (added: true, error: null);
      } catch (e) {
        return (added: false, error: '$e');
      }
    }

    final xfile = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      maxDuration: Duration(seconds: maxVideoSeconds),
    );
    if (xfile == null || xfile.path.isEmpty) {
      return (added: false, error: 'cancel');
    }

    final listIndex = videos.length;
    videos.add({'videoUrl': '', 'thumbUrl': ''});
    setState(() {});
    showSnack('Vídeo anexado — compressão e envio em segundo plano.');

    try {
      final result =
          await VideoHandlerService.instance.compressAndUploadFromPath(
        localPath: xfile.path,
        tenantId: tenantId,
        eventPostDocId: postDocRef.id,
        videoSlotIndex: slot,
      );
      if (!mounted()) {
        return (added: false, error: 'unmounted');
      }
      if (result == null) {
        if (listIndex >= 0 && listIndex < videos.length) {
          videos.removeAt(listIndex);
        }
        setState(() {});
        return (added: false, error: 'compress');
      }
      if (listIndex >= 0 && listIndex < videos.length) {
        videos[listIndex] = {
          'videoUrl': result.videoUrl,
          'thumbUrl': result.thumbUrl,
        };
      }
      setState(() {});
      return (added: true, error: null);
    } catch (e) {
      if (listIndex >= 0 && listIndex < videos.length) {
        videos.removeAt(listIndex);
      }
      setState(() {});
      return (added: false, error: '$e');
    }
  }

  Future<void> mergeVideosToFirestoreIfPublished() async {
    if (videos.isEmpty) return;
    try {
      final snap = await postDocRef.get();
      if (!snap.exists) return;
      final data = snap.data() ?? <String, dynamic>{};
      final photoUrls = eventNoticiaPhotoUrls(data)
          .where((u) => !looksLikeHostedVideoFileUrl(u.trim()))
          .toList();
      final firstUrl = photoUrls.isNotEmpty ? photoUrls.first : '';
      await postDocRef.set(
        {
          'videoUrl': primaryVideoUrl(''),
          'thumbUrl': primaryThumbUrl(),
          'videos': firestoreVideosPayload(),
          if (firstUrl.isNotEmpty) 'imageUrl': firstUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
