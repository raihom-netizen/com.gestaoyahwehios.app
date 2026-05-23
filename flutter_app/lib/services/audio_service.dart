import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Gravação de voz ultra-leve para o Chat Igreja (AAC/M4A, upload instantâneo após parar).
class ChatAudioService {
  AudioRecorder? _recorder;
  String? _path;
  AudioEncoder _encoder = AudioEncoder.aacLc;

  bool get isRecording => _recorder != null;
  String? get currentPath => _path;

  Future<bool> hasPermission() async {
    final r = AudioRecorder();
    try {
      return r.hasPermission();
    } finally {
      await r.dispose();
    }
  }

  /// Inicia gravação em ficheiro temporário `.m4a` (AAC) quando suportado.
  Future<String?> startRecording() async {
    if (kIsWeb) return null;
    await stopRecording(send: false);

    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      return null;
    }

    _encoder = AudioEncoder.aacLc;
    if (!await recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      _encoder = AudioEncoder.wav;
    }

    final dir = await getTemporaryDirectory();
    final ext = _encoder == AudioEncoder.wav ? 'wav' : 'm4a';
    final path =
        '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await recorder.start(
      MediaService.chatVoiceRecordConfig(encoder: _encoder),
      path: path,
    );
    _recorder = recorder;
    _path = path;
    return path;
  }

  /// Para gravação; se [send] false, apaga o ficheiro.
  Future<File?> stopRecording({required bool send}) async {
    if (kIsWeb) return null;
    final recorder = _recorder;
    final expected = _path;
    _recorder = null;
    _path = null;

    if (recorder == null) return null;

    String? outPath;
    try {
      if (send) {
        outPath = await recorder.stop();
      } else {
        await recorder.cancel();
      }
    } catch (_) {}
    await recorder.dispose();

    final path = outPath ?? expected;
    if (!send || path == null || path.isEmpty) {
      if (path != null && path.isNotEmpty) {
        try {
          final f = File(path);
          if (f.existsSync()) await f.delete();
        } catch (_) {}
      }
      return null;
    }
    final file = File(path);
    return file.existsSync() ? file : null;
  }

  Future<void> dispose() async {
    await stopRecording(send: false);
  }
}
