import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show sanitizeImageUrl;

/// Campos canónicos de fotos do patrimônio — **apenas** `foto01`…`foto04` + paths.
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

  /// Chaves legadas removidas em toda gravação (leitura ainda aceita fallback).
  static const List<String> legacyKeysToDelete = [
    'fotos',
    'fotoUrls',
    'imageUrls',
    'imageUrl',
    'fotoUrl',
    'thumbnail',
    'fotoStoragePaths',
    'imageStoragePath',
    'fotoPath',
    'fotoPrincipalPath',
    'gallery',
    'galeria',
    'fotoPrincipalThumbPath',
    'thumbStoragePath',
    'imageVariants',
    'fotoVariants',
    'publishState',
  ];

  /// Apaga duplicatas legadas no Firestore (merge).
  static void stripLegacyPhotoFields(Map<String, dynamic> payload) {
    for (final k in legacyKeysToDelete) {
      payload[k] = FieldValue.delete();
    }
  }

  /// Grava `foto01`…`foto04` por índice de slot (0–3) — sem listas duplicadas.
  static void applyIndexedSlots(
    Map<String, dynamic> payload,
    List<String> slotUrls,
    List<String> slotPaths,
  ) {
    for (var i = 0; i < maxPhotos; i++) {
      final u = sanitizeImageUrl(i < slotUrls.length ? slotUrls[i] : '');
      final p = (i < slotPaths.length ? slotPaths[i] : '').trim();
      if (u.isNotEmpty) {
        payload[slotUrlKeys[i]] = u;
        payload[slotPathKeys[i]] = p.isNotEmpty ? p : FieldValue.delete();
      } else {
        payload[slotUrlKeys[i]] = FieldValue.delete();
        payload[slotPathKeys[i]] = FieldValue.delete();
      }
    }
    stripLegacyPhotoFields(payload);
  }

  /// Grava listas ordenadas (foto01 = urls[0]) — slots canónicos apenas.
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
    stripLegacyPhotoFields(payload);
  }

  /// Lê URLs na ordem foto01 → foto04; depois legado (docs antigos).
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
    for (var i = 1; i <= maxPhotos; i++) {
      push((data['foto0$i'] ?? '').toString());
    }
    push((data['fotoUrl'] ?? data['imageUrl'] ?? data['thumbnail'] ?? '')
        .toString());
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
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .take(maxPhotos)
          .toList();
    }
    final single =
        (data['fotoPath'] ?? data['imageStoragePath'] ?? data['fotoPrincipalPath'] ?? '')
            .toString()
            .trim();
    if (single.isNotEmpty) return [single];
    return const [];
  }
}
