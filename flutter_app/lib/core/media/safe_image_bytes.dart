import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:image_picker/image_picker.dart';

/// Evita OutOfMemory — comprime bytes na isolate principal (igual Web → putData).
///
/// **Proibido:** `compressWithFile` / `FlutterImageCompress` dentro de `compute`
/// (BinaryMessenger no Android → falha de publish).
abstract final class SafeImageBytes {
  SafeImageBytes._();

  /// Rejeita leitura integral de ficheiros gigantes (OOM).
  static const int maxRawReadBytes = 28 * 1024 * 1024;

  static const int defaultMaxEdge = 1920;
  static const int defaultQuality = 85;

  static Future<Uint8List> fromPickerFile(
    XFile file, {
    int maxEdge = defaultMaxEdge,
    int quality = defaultQuality,
    Future<Uint8List> Function(Uint8List raw)? extraPass,
  }) async {
    final raw = await _readPickerBytes(file);
    var out = await _compressList(raw, maxEdge: maxEdge, quality: quality);
    if (extraPass != null) {
      out = await extraPass(out);
    }
    return out;
  }

  static Future<Uint8List> fromPath(
    String path, {
    int maxEdge = defaultMaxEdge,
    int quality = defaultQuality,
  }) async {
    if (path.trim().isEmpty) {
      throw StateError('Caminho de imagem vazio.');
    }
    if (kIsWeb) {
      throw StateError('fromPath não suportado na web.');
    }
    final f = File(path);
    if (!await f.exists()) {
      throw StateError('Ficheiro de imagem não encontrado.');
    }
    final len = await f.length();
    if (len > maxRawReadBytes) {
      throw StateError(
        'Ficheiro demasiado grande (${len ~/ (1024 * 1024)} MB).',
      );
    }
    final raw = await f.readAsBytes();
    if (raw.isEmpty) {
      throw StateError('Não foi possível ler a imagem.');
    }
    return _compressList(raw, maxEdge: maxEdge, quality: quality);
  }

  static Future<Uint8List> patrimonioFromPicker(XFile file) async {
    final raw = await _readPickerBytes(file);
    // MediaHandler já comprimiu (JPEG leve) — 1 compressão só no domínio (padrão CT).
    if (_looksLikeJpeg(raw) &&
        raw.length <= ImageHelper.kPatrimonioMaxUploadBytes) {
      return raw;
    }
    return ImageHelper.compressPatrimonioPhotoForUpload(raw);
  }

  static bool _looksLikeJpeg(Uint8List bytes) {
    if (bytes.length < 3) return false;
    return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  }

  /// Foto de perfil (membros / chat) — compressão em bytes, sem OOM.
  static Future<Uint8List> memberProfileFromPicker(XFile file) =>
      fromPickerFile(file, maxEdge: 1280, quality: 88);

  static Future<Uint8List> _readPickerBytes(XFile file) async {
    final path = file.path.trim();
    if (!kIsWeb && path.isNotEmpty) {
      final f = File(path);
      if (await f.exists()) {
        final len = await f.length();
        if (len > maxRawReadBytes) {
          throw StateError(
            'Imagem demasiado grande (${len ~/ (1024 * 1024)} MB). '
            'Use outra foto ou reduza a resolução.',
          );
        }
      }
    }
    final raw = await file.readAsBytes();
    if (raw.length > maxRawReadBytes) {
      throw StateError(
        'Imagem demasiado grande (${raw.length ~/ (1024 * 1024)} MB).',
      );
    }
    if (raw.isEmpty) {
      throw StateError('Não foi possível ler a imagem.');
    }
    return raw;
  }

  static Future<Uint8List> _compressList(
    Uint8List raw, {
    required int maxEdge,
    required int quality,
  }) async {
    if (raw.isEmpty) return raw;
    // Sempre na isolate principal — plugin nativo não funciona em compute().
    for (final format in [CompressFormat.webp, CompressFormat.jpeg]) {
      try {
        final result = await FlutterImageCompress.compressWithList(
          raw,
          minWidth: maxEdge,
          minHeight: maxEdge,
          quality: quality,
          format: format,
        );
        if (result.isNotEmpty) return Uint8List.fromList(result);
      } catch (_) {}
    }
    return raw;
  }
}
