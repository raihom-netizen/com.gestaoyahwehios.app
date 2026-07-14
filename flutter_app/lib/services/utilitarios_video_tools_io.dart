import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
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

Future<void> _runFfmpeg(String command) async {
  final ok = await _ffmpegSucceeded(command);
  if (!ok) {
    throw StateError('Não foi possível processar o vídeo. Tente outro arquivo.');
  }
}

Future<bool> _ffmpegSucceeded(String command) async {
  final session = await FFmpegKit.execute(command);
  final rc = await session.getReturnCode();
  return ReturnCode.isSuccess(rc);
}

VideoQuality _videoQualityFor(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => VideoQuality.HighestQuality,
    UtilitariosCompressLevel.media => VideoQuality.MediumQuality,
    UtilitariosCompressLevel.alta => VideoQuality.LowQuality,
  };
}

VideoQuality _fullHdQualityFor(UtilitariosCompressLevel? level, bool compress) {
  if (!compress || level == null) {
    return VideoQuality.Res1920x1080Quality;
  }
  return _videoQualityFor(level);
}

int _frameRateFor(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => 30,
    UtilitariosCompressLevel.media => 24,
    UtilitariosCompressLevel.alta => 22,
  };
}

/// Escala + CRF perceptual — Alta reduz resolução com preset lento (melhor que apps comuns).
String _ffmpegVideoScaleFilter(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa =>
      "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease",
    UtilitariosCompressLevel.media =>
      "scale='min(1600,iw)':'min(900,ih)':force_original_aspect_ratio=decrease",
    UtilitariosCompressLevel.alta =>
      "scale='min(1280,iw)':'min(720,ih)':force_original_aspect_ratio=decrease",
  };
}

int _ffmpegVideoCrf(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => 19,
    UtilitariosCompressLevel.media => 23,
    UtilitariosCompressLevel.alta => 28,
  };
}

String _ffmpegVideoPreset(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => 'medium',
    UtilitariosCompressLevel.media => 'slow',
    UtilitariosCompressLevel.alta => 'slow',
  };
}

String _ffmpegAudioBitrate(UtilitariosCompressLevel level) {
  return switch (level) {
    UtilitariosCompressLevel.baixa => '192k',
    UtilitariosCompressLevel.media => '128k',
    UtilitariosCompressLevel.alta => '96k',
  };
}

Future<UtilitariosVideoToolResult> _compressVideoSmartFfmpeg({
  required String inputPath,
  required UtilitariosCompressLevel level,
}) async {
  final outPath = await _tempOutputPath('mp4');
  final scale = _ffmpegVideoScaleFilter(level);
  final crf = _ffmpegVideoCrf(level);
  final preset = _ffmpegVideoPreset(level);
  final audio = _ffmpegAudioBitrate(level);
  final tune = level == UtilitariosCompressLevel.alta
      ? ['-tune', 'film']
      : <String>[];
  final cmd = [
    '-y',
    '-i',
    _quotePath(inputPath),
    '-vf',
    scale,
    '-c:v',
    'libx264',
    '-preset',
    preset,
    '-crf',
    '$crf',
    ...tune,
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
  await _runFfmpeg(cmd);
  return _resultFromPath(outPath);
}

String _ffmpegScaleFilter(UtilitariosVideoExportResolution resolution) {
  return switch (resolution) {
    UtilitariosVideoExportResolution.fullHd =>
      "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease",
    UtilitariosVideoExportResolution.fourK =>
      "scale='min(3840,iw)':'min(2160,ih)':force_original_aspect_ratio=decrease",
  };
}

int _ffmpegCrf(UtilitariosCompressLevel level, bool compress) {
  if (!compress) {
    return switch (level) {
      UtilitariosCompressLevel.baixa => 17,
      UtilitariosCompressLevel.media => 19,
      UtilitariosCompressLevel.alta => 21,
    };
  }
  return _ffmpegVideoCrf(level);
}

String _ffmpegConvertPreset(UtilitariosCompressLevel level, bool compress) {
  if (!compress) return 'medium';
  return _ffmpegVideoPreset(level);
}

Future<UtilitariosVideoToolResult> _compressWithVideoCompress({
  required String inputPath,
  required UtilitariosCompressLevel level,
  required VideoQuality quality,
}) async {
  final info = await VideoCompress.compressVideo(
    inputPath,
    quality: quality,
    deleteOrigin: false,
    includeAudio: true,
    frameRate: _frameRateFor(level),
  );
  final outPath = info?.path?.trim() ?? '';
  if (outPath.isEmpty) {
    throw StateError('Não foi possível converter o vídeo. Tente outro arquivo.');
  }
  return _resultFromPath(outPath);
}

Future<UtilitariosVideoToolResult> _convertWithFfmpeg({
  required String inputPath,
  required UtilitariosVideoConvertOptions options,
}) async {
  final outPath = await _tempOutputPath('mp4');
  final compress = options.compressAlso;
  final level = options.compressLevel;
  final crf = _ffmpegCrf(level, compress);
  final scale = _ffmpegScaleFilter(options.resolution);
  final preset = _ffmpegConvertPreset(level, compress);
  final audio = compress ? _ffmpegAudioBitrate(level) : '192k';
  final cmd = [
    '-y',
    '-i',
    _quotePath(inputPath),
    '-vf',
    scale,
    '-c:v',
    'libx264',
    '-preset',
    preset,
    '-crf',
    '$crf',
    '-profile:v',
    'high',
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
  return _compressVideoSmartFfmpeg(inputPath: inputPath, level: level);
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

  // FFmpeg para conversão confiável (Full HD, 4K e compressão).
  if (options.compressAlso) {
    return _convertWithFfmpegCompress(
      inputPath: inputPath,
      options: options,
    );
  }
  return _convertWithFfmpeg(inputPath: inputPath, options: options);
}

Future<UtilitariosVideoToolResult> _convertWithFfmpegCompress({
  required String inputPath,
  required UtilitariosVideoConvertOptions options,
}) async {
  final outPath = await _tempOutputPath('mp4');
  final level = options.compressLevel;
  final scale = _ffmpegScaleFilter(options.resolution);
  final crf = _ffmpegVideoCrf(level);
  final preset = _ffmpegVideoPreset(level);
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
    preset,
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
  await _runFfmpeg(cmd);
  return _resultFromPath(outPath);
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

  final ext = format.extension;
  final outPath = await _tempOutputPath(ext);
  final inQ = _quotePath(inputPath);
  final outQ = _quotePath(outPath);

  if (format == UtilitariosAudioExtractFormat.m4a) {
    await _runFfmpeg('-y -i $inQ -vn -c:a aac -b:a 192k -movflags +faststart $outQ');
    return _resultFromPath(outPath);
  }

  final mp3Ok = await _ffmpegSucceeded('-y -i $inQ -vn -c:a libmp3lame -q:a 2 $outQ');
  if (mp3Ok) {
    return _resultFromPath(outPath);
  }

  // Fallback: M4A (build video sem lame).
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
