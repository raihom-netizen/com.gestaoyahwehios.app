import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show eventNoticiaHostedVideoPlayUrl, looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/services/storage_media_service.dart';

/// Pré-resolve URLs de vídeo dos próximos itens do feed (token Storage) — alivia o play ao rolar.
void scheduleMuralVideoWarmupFollowing(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  int currentIndex, {
  int lookahead = 2,
}) {
  if (kIsWeb || docs.isEmpty) return;
  for (var k = 1; k <= lookahead; k++) {
    final j = currentIndex + k;
    if (j < 0 || j >= docs.length) continue;
    final raw = eventNoticiaHostedVideoPlayUrl(docs[j].data()) ?? '';
    if (raw.isEmpty || !looksLikeHostedVideoFileUrl(raw)) continue;
    unawaited(StorageMediaService.freshPlayableMediaUrl(raw));
  }
}
