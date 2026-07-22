import 'package:cloud_functions/cloud_functions.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// Pacote de URLs de mídia para partilha — gerado no servidor ([getNoticiaSharePack]).
class NoticiaSharePack {
  const NoticiaSharePack({
    this.photoUrls = const [],
    this.feedCoverUrl,
    this.videoThumbUrl,
    this.hostedVideoUrl,
  });

  final List<String> photoUrls;
  final String? feedCoverUrl;
  final String? videoThumbUrl;
  final String? hostedVideoUrl;

  factory NoticiaSharePack.fromMap(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return const NoticiaSharePack();
    final urls = <String>[];
    void add(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (s.startsWith('http')) urls.add(s);
    }

    final list = raw['photoUrls'];
    if (list is List) {
      for (final e in list) {
        add(e);
      }
    }
    add(raw['feedCoverUrl']);
    add(raw['videoThumbUrl']);

    return NoticiaSharePack(
      photoUrls: urls,
      feedCoverUrl: (raw['feedCoverUrl'] ?? '').toString().trim().isNotEmpty
          ? (raw['feedCoverUrl'] ?? '').toString().trim()
          : null,
      videoThumbUrl: (raw['videoThumbUrl'] ?? '').toString().trim().isNotEmpty
          ? (raw['videoThumbUrl'] ?? '').toString().trim()
          : null,
      hostedVideoUrl: (raw['hostedVideoUrl'] ?? '').toString().trim().isNotEmpty
          ? (raw['hostedVideoUrl'] ?? '').toString().trim()
          : null,
    );
  }
}

/// Cache RAM + callable CF — partilha sem resolver Storage no cliente.
abstract final class NoticiaSharePrefetchService {
  NoticiaSharePrefetchService._();

  static final _functions =
      FirebaseFunctions.instanceFor(app: firebaseDefaultApp, region: 'us-central1');

  static final Map<String, _RamHit> _ram = {};
  static const Duration _ramTtl = Duration(minutes: 25);

  static String _key(String tenantId, String collection, String postId) =>
      '${tenantId.trim()}|$collection|${postId.trim()}';

  static NoticiaSharePack? peek({
    required String tenantId,
    required String collection,
    required String postId,
  }) {
    final hit = _ram[_key(tenantId, collection, postId)];
    if (hit == null) return null;
    if (DateTime.now().difference(hit.at) > _ramTtl) {
      _ram.remove(_key(tenantId, collection, postId));
      return null;
    }
    return hit.pack;
  }

  static List<String> httpPhotoUrlsFromPost(Map<String, dynamic> post) {
    final seen = <String>{};
    final out = <String>[];
    void add(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (!s.startsWith('http') || seen.contains(s)) return;
      final low = s.toLowerCase().split('?').first;
      if (low.contains('youtube.com') ||
          low.contains('youtu.be') ||
          low.contains('vimeo.com')) {
        return;
      }
      if (RegExp(r'\.(mp4|webm|mov|m4v|m3u8)$').hasMatch(low) ||
          (low.contains('/videos/') &&
              !RegExp(r'\.(jpg|jpeg|png|webp|gif)$').hasMatch(low))) {
        return;
      }
      seen.add(s);
      out.add(s);
    }

    final photos = post['photoUrls'];
    if (photos is List) {
      for (final e in photos) {
        add(e);
      }
    }
    add(post['feedCoverUrl']);
    add(post['shareCoverUrl']);
    add(post['imagem_url']);
    add(post['imageUrl']);
    add(post['defaultImageUrl']);
    add(post['videoThumbUrl']);
    return out;
  }

  /// Vídeo hospedado já com URL https no doc (partilha rápida).
  static String? hostedVideoUrlFromPost(Map<String, dynamic> post) {
    bool looksVideo(String s) {
      final low = s.toLowerCase().split('?').first;
      if (low.contains('youtube.com') ||
          low.contains('youtu.be') ||
          low.contains('vimeo.com')) {
        return false;
      }
      return RegExp(r'\.(mp4|webm|mov|m4v|m3u8)$').hasMatch(low) ||
          (low.contains('/videos/') &&
              !RegExp(r'\.(jpg|jpeg|png|webp|gif)$').hasMatch(low));
    }

    String? pick(dynamic v) {
      final s = (v ?? '').toString().trim();
      if (!s.startsWith('http') || !looksVideo(s)) return null;
      return s;
    }

    for (final k in ['hostedVideoUrl', 'videoUrl', 'video_url']) {
      final u = pick(post[k]);
      if (u != null) return u;
    }
    final videos = post['videos'];
    if (videos is List) {
      for (final e in videos) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        for (final k in ['videoUrl', 'video_url', 'url', 'downloadUrl', 'downloadURL']) {
          final u = pick(m[k]);
          if (u != null) return u;
        }
      }
    }
    return null;
  }

  /// Pré-aquece pack no servidor (fire-and-forget ao abrir folha de partilha).
  static Future<NoticiaSharePack?> warm({
    required String tenantId,
    required String postId,
    String collection = 'eventos',
  }) =>
      fetch(
        tenantId: tenantId,
        postId: postId,
        collection: collection,
      );

  static Future<NoticiaSharePack?> fetch({
    required String tenantId,
    required String postId,
    String collection = 'eventos',
    Map<String, dynamic>? postDataHint,
  }) async {
    final tid = tenantId.trim();
    final pid = postId.trim();
    final col = collection.trim() == 'avisos' ? 'avisos' : 'eventos';
    if (tid.isEmpty || pid.isEmpty) return null;

    final cached = peek(tenantId: tid, collection: col, postId: pid);
    if (cached != null &&
        (cached.photoUrls.isNotEmpty || cached.hostedVideoUrl != null)) {
      return cached;
    }

    if (postDataHint != null) {
      final local = httpPhotoUrlsFromPost(postDataHint);
      final video = hostedVideoUrlFromPost(postDataHint);
      if (local.isNotEmpty || video != null) {
        final pack = NoticiaSharePack(
          photoUrls: local,
          feedCoverUrl: local.isNotEmpty ? local.first : null,
          hostedVideoUrl: video,
        );
        _ram[_key(tid, col, pid)] = _RamHit(pack, DateTime.now());
        return pack;
      }
    }

    try {
      final res = await _functions
          .httpsCallable('getNoticiaSharePack')
          .call<Map<String, dynamic>>({
        'tenantId': tid,
        'postId': pid,
        'collection': col,
      })
          .timeout(const Duration(seconds: 12));
      final pack = NoticiaSharePack.fromMap(res.data);
      if (pack.photoUrls.isNotEmpty || pack.hostedVideoUrl != null) {
        _ram[_key(tid, col, pid)] = _RamHit(pack, DateTime.now());
      }
      return pack;
    } catch (e) {
      if (kDebugMode) debugPrint('getNoticiaSharePack: $e');
      return null;
    }
  }
}

class _RamHit {
  _RamHit(this.pack, this.at);
  final NoticiaSharePack pack;
  final DateTime at;
}

