import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/yahweh_heavy_work.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:image_picker/image_picker.dart';

/// Evita OutOfMemory — comprime no disco antes de carregar original na RAM.
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
        final compressed = await _compressFromPath(path, maxEdge: maxEdge, quality: quality);
        if (compressed.isNotEmpty) {
          return extraPass != null ? await extraPass(compressed) : compressed;
        }
      }
    }
    final raw = await file.readAsBytes();
    if (raw.length > maxRawReadBytes) {
      throw StateError(
        'Imagem demasiado grande (${raw.length ~/ (1024 * 1024)} MB).',
      );
    }
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
    return _compressFromPath(path, maxEdge: maxEdge, quality: quality);
  }

  static Future<Uint8List> patrimonioFromPicker(XFile file) async {
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
    return ImageHelper.compressPatrimonioPhotoForUpload(raw);
  }

  /// Foto de perfil (membros / chat) — compressão no disco, sem OOM.
  static Future<Uint8List> memberProfileFromPicker(XFile file) =>
      fromPickerFile(file, maxEdge: 1280, quality: 88);

  static Future<Uint8List> _compressFromPath(
    String path, {
    required int maxEdge,
    required int quality,
  }) async {
    if (kIsWeb) {
      final raw = await YahwehHeavyWork.readFileBytes(path);
      return _compressList(Uint8List.fromList(raw), maxEdge: maxEdge, quality: quality);
    }
    for (final format in [CompressFormat.webp, CompressFormat.jpeg]) {
      final result = await YahwehHeavyWork.run(
        _compressPathIsolate,
        _CompressPathMessage(path, maxEdge, quality, format),
      );
      if (result.isNotEmpty) {
        return Uint8List.fromList(result);
      }
    }
    final raw = await YahwehHeavyWork.readFileBytes(path);
    if (raw.isEmpty) {
      throw StateError('Não foi possível ler a imagem.');
    }
    return Uint8List.fromList(raw);
  }

  static Future<Uint8List> _compressList(
    Uint8List raw, {
    required int maxEdge,
    required int quality,
  }) async {
    if (raw.isEmpty) return raw;
    for (final format in [CompressFormat.webp, CompressFormat.jpeg]) {
      final result = kIsWeb
          ? await FlutterImageCompress.compressWithList(
              raw,
              minWidth: maxEdge,
              minHeight: maxEdge,
              quality: quality,
              format: format,
            )
          : await YahwehHeavyWork.run(
              _compressListIsolate,
              _CompressListMessage(raw, maxEdge, quality, format),
            );
      if (result.isNotEmpty) return Uint8List.fromList(result);
    }
    return raw;
  }
}

class _CompressPathMessage {
  const _CompressPathMessage(this.path, this.maxEdge, this.quality, this.format);
  final String path;
  final int maxEdge;
  final int quality;
  final CompressFormat format;
}

Future<List<int>> _compressPathIsolate(_CompressPathMessage msg) async {
  final out = await FlutterImageCompress.compressWithFile(
    msg.path,
    minWidth: msg.maxEdge,
    minHeight: msg.maxEdge,
    quality: msg.quality,
    format: msg.format,
  );
  return out ?? <int>[];
}

class _CompressListMessage {
  const _CompressListMessage(this.bytes, this.maxEdge, this.quality, this.format);
  final Uint8List bytes;
  final int maxEdge;
  final int quality;
  final CompressFormat format;
}

Future<List<int>> _compressListIsolate(_CompressListMessage msg) async {
  return FlutterImageCompress.compressWithList(
    msg.bytes,
    minWidth: msg.maxEdge,
    minHeight: msg.maxEdge,
    quality: msg.quality,
    format: msg.format,
  );
}
