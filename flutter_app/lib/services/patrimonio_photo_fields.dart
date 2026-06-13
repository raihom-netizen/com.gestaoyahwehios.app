import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Campos canónicos de fotos do patrimônio — `foto01`…`foto04` + listas legadas.
abstract final class PatrimonioPhotoFields {
  PatrimonioPhotoFields._();

  static const List<String> slotUrlKeys = [
    'foto01',
    'foto02',
    'foto03',
    'foto04',
  ];

  static const List<String> slotPathKeys = [
    'foto01Path',
    'foto02Path',
    'foto03Path',
    'foto04Path',
  ];

  static const int maxPhotos = 4;

  /// Grava `foto01`…`foto04` por índice de slot (0–3) + campos legados.
  static void applyIndexedSlots(
    Map<String, dynamic> payload,
    List<String> slotUrls,
    List<String> slotPaths,
  ) {
    final orderedUrls = <String>[];
    final orderedPaths = <String>[];
    for (var i = 0; i < maxPhotos; i++) {
      final u = sanitizeImageUrl(i < slotUrls.length ? slotUrls[i] : '');
      final p = (i < slotPaths.length ? slotPaths[i] : '').trim();
      if (u.isNotEmpty) {
        payload[slotUrlKeys[i]] = u;
        payload[slotPathKeys[i]] = p.isNotEmpty ? p : FieldValue.delete();
        orderedUrls.add(u);
        if (p.isNotEmpty) orderedPaths.add(p);
      } else {
        payload[slotUrlKeys[i]] = FieldValue.delete();
        payload[slotPathKeys[i]] = FieldValue.delete();
      }
    }
    _applyLegacyLists(payload, orderedUrls, orderedPaths);
  }

  /// Grava listas ordenadas (foto01 = urls[0]) — slots + legado.
  static void applyToPayload(
    Map<String, dynamic> payload,
    List<String> urls,
    List<String> paths,
  ) {
    final cleanUrls = urls
        .map((e) => sanitizeImageUrl(e))
        .where((e) => e.isNotEmpty)
        .take(maxPhotos)
        .toList();
    final cleanPaths =
        paths.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    for (var i = 0; i < maxPhotos; i++) {
      if (i < cleanUrls.length) {
        payload[slotUrlKeys[i]] = cleanUrls[i];
        if (i < cleanPaths.length && cleanPaths[i].isNotEmpty) {
          payload[slotPathKeys[i]] = cleanPaths[i];
        } else {
          payload[slotPathKeys[i]] = FieldValue.delete();
        }
      } else {
        payload[slotUrlKeys[i]] = FieldValue.delete();
        payload[slotPathKeys[i]] = FieldValue.delete();
      }
    }
    _applyLegacyLists(payload, cleanUrls, cleanPaths);
  }

  static void _applyLegacyLists(
    Map<String, dynamic> payload,
    List<String> cleanUrls,
    List<String> cleanPaths,
  ) {
    if (cleanUrls.isNotEmpty) {
      payload['fotos'] = cleanUrls;
      payload['fotoUrls'] = cleanUrls;
      payload['imageUrls'] = cleanUrls;
      payload['imageUrl'] = cleanUrls.first;
      payload['fotoUrl'] = cleanUrls.first;
      payload['thumbnail'] = cleanUrls.first;
    } else {
      for (final k in [
        'fotos',
        'fotoUrls',
        'imageUrls',
        'imageUrl',
        'fotoUrl',
        'thumbnail',
      ]) {
        payload[k] = FieldValue.delete();
      }
    }

    if (cleanPaths.isNotEmpty) {
      payload['fotoStoragePaths'] = cleanPaths.take(maxPhotos).toList();
      payload['imageStoragePath'] = cleanPaths.first;
      payload['fotoPath'] = cleanPaths.first;
      payload['fotoPrincipalPath'] = cleanPaths.first;
      payload['gallery'] =
          cleanPaths.length > 1 ? cleanPaths.sublist(1) : FieldValue.delete();
    } else {
      for (final k in [
        'fotoStoragePaths',
        'imageStoragePath',
        'fotoPath',
        'fotoPrincipalPath',
        'gallery',
      ]) {
        payload[k] = FieldValue.delete();
      }
    }

    payload['fotoPrincipalThumbPath'] = FieldValue.delete();
    payload['thumbStoragePath'] = FieldValue.delete();
    payload['imageVariants'] = FieldValue.delete();
    payload['fotoVariants'] = FieldValue.delete();
  }

  /// Lê URLs na ordem foto01 → foto04; depois legado.
  static List<String> urlsFromData(Map<String, dynamic> data) {
    final fromSlots = <String>[];
    for (final k in slotUrlKeys) {
      final u = sanitizeImageUrl((data[k] ?? '').toString());
      if (u.isNotEmpty) fromSlots.add(u);
    }
    if (fromSlots.isNotEmpty) return fromSlots;

    final legacy = <String>[];
    void push(String raw) {
      final s = sanitizeImageUrl(raw);
      if (s.isNotEmpty && !legacy.contains(s)) legacy.add(s);
    }

    final raw = data['fotoUrls'];
    if (raw is List) {
      for (final e in raw) {
        push(e?.toString() ?? '');
      }
    }
    final fotos = data['fotos'];
    if (fotos is List) {
      for (final e in fotos) {
        push(e?.toString() ?? '');
      }
    }
    push((data['fotoUrl'] ?? data['imageUrl'] ?? '').toString());
    return legacy.take(maxPhotos).toList();
  }

  static List<String> pathsFromData(Map<String, dynamic> data) {
    final fromSlots = <String>[];
    for (final k in slotPathKeys) {
      final p = (data[k] ?? '').toString().trim();
      if (p.isNotEmpty) fromSlots.add(p);
    }
    if (fromSlots.isNotEmpty) return fromSlots;
    final raw = data['fotoStoragePaths'];
    if (raw is List) {
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }
    final single = (data['fotoPath'] ?? data['imageStoragePath'] ?? '').toString().trim();
    if (single.isNotEmpty) return [single];
    return const [];
  }
}
