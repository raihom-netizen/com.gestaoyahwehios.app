import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_tenant_posts_collections.dart';
import 'package:gestao_yahweh/core/event_noticia_media.dart'
    show eventNoticiaPhotoUrls, looksLikeHostedVideoFileUrl;
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        imageUrlFromMap,
        imageUrlsListFromMap,
        isValidImageUrl,
        preloadNetworkImages,
        sanitizeImageUrl;

DateTime? _lastPanelImageWarmupAt;

/// Coleta URLs de foto de um documento de membro (lista do painel).
List<String> _memberPhotoUrls(Map<String, dynamic> m) {
  final out = <String>[];
  void push(String raw) {
    final s = sanitizeImageUrl(raw);
    if (s.isEmpty || !isValidImageUrl(s) || looksLikeHostedVideoFileUrl(s)) {
      return;
    }
    if (!out.contains(s)) out.add(s);
  }

  final primary = imageUrlFromMap(m);
  if (primary.isNotEmpty) push(primary);
  for (final k in [
    'fotoUrl',
    'FOTO_URL_OU_ID',
    'photoURL',
    'foto_url',
    'fotoUrlCard',
  ]) {
    push((m[k] ?? '').toString());
  }
  return out;
}

/// URLs de galeria do patrimônio (mesma ideia que o módulo, sem importar símbolos privados).
List<String> _patrimonioPhotoUrls(Map<String, dynamic> m) {
  final out = <String>[];
  void push(String raw) {
    final s = sanitizeImageUrl(raw);
    if (s.isEmpty || !isValidImageUrl(s) || looksLikeHostedVideoFileUrl(s)) {
      return;
    }
    if (!out.contains(s)) out.add(s);
  }

  final rawList = m['fotoUrls'];
  if (rawList is List) {
    for (final e in rawList) {
      if (e is String) {
        push(e);
      } else if (e is Map) {
        for (final k in [
          'url',
          'imageUrl',
          'downloadURL',
          'downloadUrl',
          'fotoUrl',
          'photoUrl',
        ]) {
          final v = e[k];
          if (v != null) {
            push(v.toString());
            break;
          }
        }
      }
    }
  }
  for (final k in ['imageUrl', 'defaultImageUrl', 'fotoUrl', 'photoUrl']) {
    push((m[k] ?? '').toString());
  }
  out.addAll(imageUrlsListFromMap(m));
  return dedupeImageRefsByStorageIdentity(out);
}

/// Pré-carrega na memória do Flutter até ~10 itens recentes por módulo (membros, notícias,
/// avisos, patrimônio) após abrir o painel da igreja — reduz “flash” ao navegar.
///
/// [resolvedTenantId]: quando já foi resolvido no painel, evita segunda ida ao Firestore
/// só para resolver o id. Atraso curto: só o suficiente para não disputar o 1.º frame.
///
/// [force]: ignorar debounce (ex.: 1.ª abertura do painel). Ao voltar ao app, o debounce evita
/// rajadas de Firestore + decode quando o SO retoma várias vezes seguidas.
Future<void> scheduleYahwehPanelImageWarmup(
  BuildContext context,
  String tenantId, {
  String? resolvedTenantId,
  bool force = false,
}) async {
  final now = DateTime.now();
  if (!force &&
      _lastPanelImageWarmupAt != null &&
      now.difference(_lastPanelImageWarmupAt!) <
          const Duration(seconds: 50)) {
    return;
  }
  _lastPanelImageWarmupAt = now;

  // Não disputa com o 1.º frame / streams de membros e departamentos.
  await Future<void>.delayed(const Duration(milliseconds: 120));
  if (!context.mounted) return;
  final raw = tenantId.trim();
  if (raw.isEmpty) return;
  final resolved = (resolvedTenantId != null && resolvedTenantId.trim().isNotEmpty)
      ? resolvedTenantId.trim()
      : await TenantResolverService.resolveEffectiveTenantId(raw);
  if (resolved.isEmpty || !context.mounted) return;
  final base = FirebaseFirestore.instance.collection('igrejas').doc(resolved);
  try {
    final snaps = await Future.wait([
      base.collection('membros').limit(10).get(),
      base
          .collection(ChurchTenantPostsCollections.noticias)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get(),
      base
          .collection(ChurchTenantPostsCollections.avisos)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get(),
      base.collection('patrimonio').orderBy('nome').limit(10).get(),
    ]);
    if (!context.mounted) return;
    final urls = <String>[];
    for (final d in snaps[0].docs) {
      urls.addAll(_memberPhotoUrls(d.data()));
    }
    for (final d in snaps[1].docs) {
      for (final u in eventNoticiaPhotoUrls(d.data())) {
        final s = sanitizeImageUrl(u);
        if (isValidImageUrl(s) && !looksLikeHostedVideoFileUrl(s)) urls.add(s);
      }
    }
    for (final d in snaps[2].docs) {
      for (final u in eventNoticiaPhotoUrls(d.data())) {
        final s = sanitizeImageUrl(u);
        if (isValidImageUrl(s) && !looksLikeHostedVideoFileUrl(s)) urls.add(s);
      }
      for (final u in imageUrlsListFromMap(d.data())) {
        final s = sanitizeImageUrl(u);
        if (isValidImageUrl(s) && !looksLikeHostedVideoFileUrl(s)) urls.add(s);
      }
    }
    for (final d in snaps[3].docs) {
      urls.addAll(_patrimonioPhotoUrls(d.data()));
    }
    await preloadNetworkImages(
      context,
      dedupeImageRefsByStorageIdentity(urls),
      maxItems: 42,
    );
  } catch (_) {}
}
