import 'dart:typed_data';

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

bool get utilitariosVideoCompressSupported => false;
bool get utilitariosVideoToolsSupported => false;

Future<UtilitariosVideoToolResult> utilitariosCompressVideoFile({
  required String inputPath,
  required UtilitariosCompressLevel level,
}) async {
  throw StateError(
    'Ferramentas de vídeo disponíveis no app Android e iPhone.',
  );
}

Future<UtilitariosVideoToolResult> utilitariosConvertVideoToMp4({
  required String inputPath,
  required UtilitariosVideoConvertOptions options,
}) async {
  throw StateError(
    'Conversão de vídeo disponível no app Android e iPhone.',
  );
}

Future<UtilitariosVideoToolResult> utilitariosExtractAudioFromVideo({
  required String inputPath,
  required UtilitariosAudioExtractFormat format,
}) async {
  throw StateError(
    'Extração de áudio disponível no app Android e iPhone.',
  );
}
