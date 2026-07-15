import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

import 'utilitarios_local_service.dart';
import 'utilitarios_video_models.dart';

class UtilitariosVideoToolResult {
  const UtilitariosVideoToolResult({
    required this.outputPath,
    required this.bytes,
    this.note,
  });

  final String outputPath;
  final Uint8List bytes;
  final String? note;
}

typedef UtilitariosVideoCompressResult = UtilitariosVideoToolResult;

bool get utilitariosVideoCompressSupported =>
    Platform.isAndroid || Platform.isIOS;

bool get utilitariosVideoToolsSupported => utilitariosVideoCompressSupported;

String _quotePath(String path) {
  final escaped = path.replaceAll('"', r'\"');
  return '"$escaped"';
}

Future<String> _tempOutputPath(String ext) async {
  final tmp = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  return '${tmp.path}/ct_video_$stamp.$ext';
}

Future<UtilitariosVideoToolResult> _resultFromPath(String path) async {
  final file = File(path);
  if (!await file.exists() || await file.length() == 0) {
    throw StateError('Arquivo gerado inválido. Tente outro vídeo.');
  }
  final bytes = await file.readAsBytes();
  return UtilitariosVideoToolResult(outputPath: path, bytes: bytes);
}

/// Copia o vídeo para pasta temporária com nome seguro (iOS/Android).
Future<String> _prepareVideoInputPath(String inputPath) async {
  final input = File(inputPath);
  if (!await input.exists()) {
    throw StateError('Arquivo de vídeo não encontrado.');
  }
  final ext = p.extension(inputPath).toLowerCase();
  const allowed = {'.mp4', '.mov', '.m4v', '.avi', '.mkv', '.webm', '.3gp'};
  final safeExt = allowed.contains(ext) ? ext : '.mp4';
  final tmp = await getTemporaryDirectory();
  final staged = File(
    '${tmp.path}/ct_vid_${DateTime.now().microsecondsSinceEpoch}$safeExt',
  );
  await input.copy(staged.path);
  if (!await staged.exists() || await staged.length() == 0) {
    throw StateError('Não foi possível preparar o vídeo. Tente outro arquivo.');
  }
  return staged.path;
}

List<String> _inputPathCandidates(String inputPath, String staged) {
  final out = <String>[staged];
  final raw = inputPath.trim();
  if (raw.isNotEmpty && raw != staged) out.add(raw);
  return out;
}

Future<void> _resetNativeCompressor() async {
  try {
    await VideoCompress.cancelCompression();
  } catch (_) {}
}

Future<bool> _ffmpegSucceeded(String command) async {
  final session = await FFmpegKit.execute(command);
  final rc = await session.getReturnCode();
  final ok = ReturnCode.isSuccess(rc);
  if (!ok) {
    final logs = await session.getAllLogsAsString();
    debugPrint('[UtilitariosVideo] FFmpeg falhou: $command');
    if (logs != null && logs.trim().isNotEmpty) {
      debugPrint('[UtilitariosVideo] $logs');
    }
  }
  return ok;
}

Future<void> _runFfmpeg(String command) async {
  final ok = await _ffmpegSucceeded(command);
  if (!ok) {
    throw StateError('Não foi possível processar o vídeo. Tente outro arquivo.');
  }
}

/// Qualidade nativa alinhada à UI (1080p / 900p / 720p).
VideoQuality _nativeQualityForLevel(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => VideoQuality.Res1920x1080Quality,
    UtilitariosCompressLevel.media => VideoQuality.Res960x540Quality,
    UtilitariosCompressLevel.alta => VideoQuality.Res1280x720Quality,
  };
}

List<VideoQuality> _nativeQualityChain(UtilitariosCompressLevel level) {
  final primary = _nativeQualityForLevel(level);
  return <VideoQuality>{
    primary,
    VideoQuality.MediumQuality,
    VideoQuality.LowQuality,
    VideoQuality.DefaultQuality,
    VideoQuality.HighestQuality,
  }.toList();
}

int _frameRateFor(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => 30,
    UtilitariosCompressLevel.media => 24,
    UtilitariosCompressLevel.alta => 22,
  };
}

String _ffmpegVideoScaleFilter(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa =>
      'scale=1920:1080:force_original_aspect_ratio=decrease',
    UtilitariosCompressLevel.media =>
      'scale=1600:900:force_original_aspect_ratio=decrease',
    UtilitariosCompressLevel.alta =>
      'scale=1280:720:force_original_aspect_ratio=decrease',
  };
}

int _ffmpegVideoCrf(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => 22,
    UtilitariosCompressLevel.media => 26,
    UtilitariosCompressLevel.alta => 30,
  };
}

String _ffmpegAudioBitrate(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => '160k',
    UtilitariosCompressLevel.media => '128k',
    UtilitariosCompressLevel.alta => '96k',
  };
}

String _ffmpegScaleFilter(UtilitariosVideoExportResolution resolution) {
  return switch (resolution) {
    UtilitariosVideoExportResolution.fullHd =>
      'scale=1920:1080:force_original_aspect_ratio=decrease',
    UtilitariosVideoExportResolution.fourK =>
      'scale=3840:2160:force_original_aspect_ratio=decrease',
  };
}

Future<UtilitariosVideoToolResult> _compressWithVideoCompress({
  required String inputPath,
  required UtilitariosCompressLevel level,
  required VideoQuality quality,
}) async {
  await _resetNativeCompressor();
  final info = await VideoCompress.compressVideo(
    inputPath,
    quality: quality,
    deleteOrigin: false,
    includeAudio: true,
    frameRate: _frameRateFor(level),
  );
  final outPath = info?.path?.trim() ?? '';
  if (outPath.isEmpty) {
    throw StateError('Compressor nativo não gerou arquivo.');
  }
  return _resultFromPath(outPath);
}

Future<UtilitariosVideoToolResult?> _tryNativeCompress({
  required List<String> paths,
  required UtilitariosCompressLevel level,
}) async {
  for (final path in paths) {
    for (final quality in _nativeQualityChain(level)) {
      try {
        return await _compressWithVideoCompress(
          inputPath: path,
          level: level,
          quality: quality,
        );
      } catch (e) {
        debugPrint(
          '[UtilitariosVideo] Nativo falhou ($quality · $path): $e',
        );
      }
    }
  }
  return null;
}

Future<UtilitariosVideoToolResult?> _compressVideoFastFfmpeg({
  required String inputPath,
  required UtilitariosCompressLevel level,
}) async {
  final outPath = await _tempOutputPath('mp4');
  final scale = _ffmpegVideoScaleFilter(level);
  final crf = _ffmpegVideoCrf(level);
  final audio = _ffmpegAudioBitrate(level);

  if (Platform.isIOS) {
    final iosCmd = [
      '-y',
      '-i',
      _quotePath(inputPath),
      '-vf',
      scale,
      '-c:v',
      'h264_videotoolbox',
      '-b:v',
      level == UtilitariosCompressLevel.alta ? '2M' : '4M',
      '-c:a',
      'aac',
      '-b:a',
      audio,
      '-movflags',
      '+faststart',
      _quotePath(outPath),
    ].join(' ');
    if (await _ffmpegSucceeded(iosCmd)) {
      return _resultFromPath(outPath);
    }
  }

  final cmd = [
    '-y',
    '-i',
    _quotePath(inputPath),
    '-vf',
    scale,
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-crf',
    '$crf',
    '-pix_fmt',
    'yuv420p',
    '-movflags',
    '+faststart',
    '-c:a',
    'aac',
    '-b:a',
    audio,
    _quotePath(outPath),
  ].join(' ');
  if (!await _ffmpegSucceeded(cmd)) return null;
  return _resultFromPath(outPath);
}

Future<UtilitariosVideoToolResult?> _compressVideoSmartFfmpeg({
  required String inputPath,
  required UtilitariosCompressLevel level,
}) async {
  final outPath = await _tempOutputPath('mp4');
  final scale = _ffmpegVideoScaleFilter(level);
  final crf = _ffmpegVideoCrf(level);
  final audio = _ffmpegAudioBitrate(level);
  final cmd = [
    '-y',
    '-i',
    _quotePath(inputPath),
    '-vf',
    scale,
    '-c:v',
    'libx264',
    '-preset',
    'medium',
    '-crf',
    '$crf',
    '-profile:v',
    'high',
    '-pix_fmt',
    'yuv420p',
    '-movflags',
    '+faststart',
    '-c:a',
    'aac',
    '-b:a',
    audio,
    '-ar',
    '44100',
    _quotePath(outPath),
  ].join(' ');
  if (!await _ffmpegSucceeded(cmd)) return null;
  return _resultFromPath(outPath);
}

/// Compressão MP4: nativo primeiro (iOS/Android), FFmpeg como reserva.
Future<UtilitariosVideoToolResult> _runVideoCompressPipeline({
  required String inputPath,
  required UtilitariosCompressLevel level,
}) async {
  final staged = await _prepareVideoInputPath(inputPath);
  final paths = _inputPathCandidates(inputPath, staged);

  final native = await _tryNativeCompress(paths: paths, level: level);
  if (native != null) return native;

  for (final path in paths) {
    final fast = await _compressVideoFastFfmpeg(inputPath: path, level: level);
    if (fast != null) return fast;

    final smart = await _compressVideoSmartFfmpeg(inputPath: path, level: level);
    if (smart != null) return smart;
  }

  throw StateError('Não foi possível processar o vídeo. Tente outro arquivo.');
}

Future<UtilitariosVideoToolResult> _convertWithFfmpeg({
  required String inputPath,
  required UtilitariosVideoConvertOptions options,
}) async {
  final outPath = await _tempOutputPath('mp4');
  final compress = options.compressAlso;
  final level = options.compressLevel;
  final crf = compress ? _ffmpegVideoCrf(level) : 20;
  final scale = _ffmpegScaleFilter(options.resolution);
  final audio = compress ? _ffmpegAudioBitrate(level) : '160k';
  final cmd = [
    '-y',
    '-i',
    _quotePath(inputPath),
    '-vf',
    scale,
    '-c:v',
    'libx264',
    '-preset',
    compress ? 'veryfast' : 'medium',
    '-crf',
    '$crf',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-b:a',
    audio,
    '-movflags',
    '+faststart',
    _quotePath(outPath),
  ].join(' ');
  await _runFfmpeg(cmd);
  return _resultFromPath(outPath);
}

Future<UtilitariosVideoToolResult> _runVideoConvertPipeline({
  required String inputPath,
  required UtilitariosVideoConvertOptions options,
}) async {
  final level =
      options.compressAlso ? options.compressLevel : UtilitariosCompressLevel.baixa;
  final staged = await _prepareVideoInputPath(inputPath);
  final paths = _inputPathCandidates(inputPath, staged);

  final native = await _tryNativeCompress(
    paths: paths,
    level: level,
  );
  if (native != null) {
    final note = options.resolution == UtilitariosVideoExportResolution.fourK
        ? 'Conversão via compressor nativo (4K indisponível — melhor qualidade do aparelho).'
        : 'Conversão via compressor nativo do aparelho.';
    return UtilitariosVideoToolResult(
      outputPath: native.outputPath,
      bytes: native.bytes,
      note: note,
    );
  }

  for (final path in paths) {
    try {
      return await _convertWithFfmpeg(inputPath: path, options: options);
    } catch (e) {
      debugPrint('[UtilitariosVideo] Conversão FFmpeg falhou: $e');
    }
    final fast = await _compressVideoFastFfmpeg(inputPath: path, level: level);
    if (fast != null) return fast;
  }

  throw StateError('Não foi possível processar o vídeo. Tente outro arquivo.');
}

/// Comprime vídeo para MP4 — Android/iOS.
Future<UtilitariosVideoToolResult> utilitariosCompressVideoFile({
  required String inputPath,
  required UtilitariosCompressLevel level,
}) async {
  if (!utilitariosVideoToolsSupported) {
    throw StateError(
      'Ferramentas de vídeo disponíveis no app Android e iPhone.',
    );
  }
  final input = File(inputPath);
  if (!await input.exists()) {
    throw StateError('Arquivo de vídeo não encontrado.');
  }
  await UtilitariosLocalService.ensureVideoFileWithinSize(inputPath);
  return _runVideoCompressPipeline(inputPath: inputPath, level: level);
}

/// Converte qualquer vídeo para MP4 (Full HD ou 4K) com opção de compressão.
Future<UtilitariosVideoToolResult> utilitariosConvertVideoToMp4({
  required String inputPath,
  required UtilitariosVideoConvertOptions options,
}) async {
  if (!utilitariosVideoToolsSupported) {
    throw StateError(
      'Conversão de vídeo disponível no app Android e iPhone.',
    );
  }
  final input = File(inputPath);
  if (!await input.exists()) {
    throw StateError('Arquivo de vídeo não encontrado.');
  }
  await UtilitariosLocalService.ensureVideoFileWithinSize(inputPath);
  return _runVideoConvertPipeline(inputPath: inputPath, options: options);
}

/// Extrai faixa de áudio do vídeo (M4A ou MP3).
Future<UtilitariosVideoToolResult> utilitariosExtractAudioFromVideo({
  required String inputPath,
  required UtilitariosAudioExtractFormat format,
}) async {
  if (!utilitariosVideoToolsSupported) {
    throw StateError(
      'Extração de áudio disponível no app Android e iPhone.',
    );
  }
  final input = File(inputPath);
  if (!await input.exists()) {
    throw StateError('Arquivo de vídeo não encontrado.');
  }
  await UtilitariosLocalService.ensureVideoFileWithinSize(inputPath);

  final staged = await _prepareVideoInputPath(inputPath);
  final ext = format.extension;
  final outPath = await _tempOutputPath(ext);
  final inQ = _quotePath(staged);
  final outQ = _quotePath(outPath);

  if (format == UtilitariosAudioExtractFormat.m4a) {
    final ok = await _ffmpegSucceeded(
      '-y -i $inQ -vn -c:a aac -b:a 192k -movflags +faststart $outQ',
    );
    if (ok) return _resultFromPath(outPath);
    await _runFfmpeg('-y -i $inQ -vn -acodec copy $outQ');
    return _resultFromPath(outPath);
  }

  final mp3Ok = await _ffmpegSucceeded(
    '-y -i $inQ -vn -c:a libmp3lame -q:a 2 $outQ',
  );
  if (mp3Ok) {
    return _resultFromPath(outPath);
  }

  final m4aPath = await _tempOutputPath('m4a');
  await _runFfmpeg(
    '-y -i $inQ -vn -c:a aac -b:a 192k -movflags +faststart ${_quotePath(m4aPath)}',
  );
  return UtilitariosVideoToolResult(
    outputPath: m4aPath,
    bytes: (await File(m4aPath).readAsBytes()),
    note: 'MP3 indisponível — áudio exportado em M4A (AAC).',
  );
}
