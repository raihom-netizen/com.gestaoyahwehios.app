import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/church_panel_modules_removed.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/ios_publish_image_pipeline.dart';
import 'package:gestao_yahweh/services/evento_media_upload.dart';
import 'package:gestao_yahweh/services/ecofire_feed_photo_slot.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        dedupeImageRefsByStorageIdentity,
        isValidImageUrl,
        sanitizeImageUrl;

/// Publicação de fotos evento — upload directo no Storage (pasta do post).
///
/// Avisos usam [ChurchAvisosService]; ramo aviso aqui bloqueado.
abstract final class EcoFireFeedPublishService {
  EcoFireFeedPublishService._();

  static const Duration uploadTimeout = Duration(seconds: 45);

  static bool _isEventoPostType(String postType) {
    final t = postType.trim().toLowerCase();
    return t == 'evento' || t == 'noticia' || t == 'noticias';
  }

  /// Um slot — comprime, envia um ficheiro, devolve URL HTTPS.
  static Future<EcoFireFeedPhotoSlot> uploadPhotoSlot({
    required String tenantId,
    required String postType,
    required String postId,
    required int slotIndex,
    Uint8List? bytes,
    String? localPath,
    bool alreadyCompressed = false,
    void Function(double progress)? onProgress,
  }) async {
    if (!_isEventoPostType(postType)) {
      throw const ChurchPanelModuleRemovedException('Avisos');
    }

    final churchId = tenantId.trim();
    Uint8List raw;
    if (bytes != null && bytes.isNotEmpty) {
      raw = bytes;
    } else if (!kIsWeb && localPath != null && localPath.trim().isNotEmpty) {
      raw = await IosPublishImagePipeline.compressForPublishFromPath(
        localPath.trim(),
      );
    } else {
      throw StateError('Sem imagem para enviar.');
    }
    return EventoMediaUpload.uploadPhotoSlot(
      churchId: churchId,
      postId: postId,
      slotIndex: slotIndex,
      rawBytes: raw,
      alreadyCompressed: alreadyCompressed || (bytes != null && bytes.isNotEmpty),
      onProgress: onProgress,
    );
  }

  /// Lote — web (bytes) ou mobile (paths). Eventos: até 10 em paralelo.
  static Future<List<EcoFireFeedPhotoSlot>> uploadPendingPhotoSlots({
    required String tenantId,
    required String postType,
    required String postId,
    required int startSlotIndex,
    List<Uint8List>? bytesList,
    List<String>? localPaths,
    bool alreadyCompressed = false,
    void Function(double progress)? onProgress,
  }) async {
    if (!_isEventoPostType(postType)) {
      throw const ChurchPanelModuleRemovedException('Avisos');
    }

    final maxParallel = EventoMediaUpload.maxParallelSlots;

    if (kIsWeb) {
      final images = bytesList ?? const <Uint8List>[];
      if (images.isEmpty) return const [];

      return EventoMediaUpload.uploadPhotoBatch(
        churchId: tenantId,
        postId: postId,
        startSlotIndex: startSlotIndex,
        bytesList: images,
        alreadyCompressed: true,
        onProgress: onProgress,
      );
    }

    final mobileBytes = bytesList ?? const <Uint8List>[];
    if (mobileBytes.isNotEmpty) {
      return EventoMediaUpload.uploadPhotoBatch(
        churchId: tenantId,
        postId: postId,
        startSlotIndex: startSlotIndex,
        bytesList: mobileBytes,
        alreadyCompressed: alreadyCompressed,
        onProgress: onProgress,
      );
    }

    final paths = localPaths
            ?.map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList() ??
        const <String>[];
    if (paths.isEmpty) return const [];

    final slots = List<EcoFireFeedPhotoSlot?>.filled(paths.length, null);
    var completed = 0;

    Future<void> uploadOne(int i) async {
      final f = File(paths[i]);
      if (!await f.exists()) {
        throw StateError('Foto ${i + 1} não encontrada no aparelho.');
      }
      slots[i] = await uploadPhotoSlot(
        tenantId: tenantId,
        postType: postType,
        postId: postId,
        slotIndex: startSlotIndex + i,
        localPath: paths[i],
      );
      completed++;
      onProgress?.call(completed / paths.length);
    }

    for (var start = 0; start < paths.length; start += maxParallel) {
      final end = (start + maxParallel).clamp(0, paths.length);
      await Future.wait([
        for (var i = start; i < end; i++) uploadOne(i),
      ]);
    }
    return slots.whereType<EcoFireFeedPhotoSlot>().toList();
  }

  /// Converte paths ou URLs mistos em URLs HTTPS para o Firestore.
  static Future<List<String>> refsToPlayableUrls(List<String> refs) async {
    final out = <String>[];
    final futures = <Future<String?>>[];
    final indices = <int>[];
    for (var i = 0; i < refs.length; i++) {
      final t = refs[i].trim();
      if (t.isEmpty) continue;
      if (t.startsWith('http')) {
        final u = sanitizeImageUrl(t);
        if (isValidImageUrl(u)) out.add(u);
        continue;
      }
      indices.add(i);
      futures.add(EcoFireStorageUpload.downloadUrlFromStoragePath(t));
    }
    final results = await Future.wait(futures, eagerError: false);
    for (var j = 0; j < results.length; j++) {
      final u = results[j];
      if (u != null && u.isNotEmpty) {
        out.add(sanitizeImageUrl(u));
      }
    }
    return dedupeImageRefsByStorageIdentity(out);
  }
}
