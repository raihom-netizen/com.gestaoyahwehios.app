import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/church_chat_fs.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Gravação de voz estilo WhatsApp para o Chat Igreja (AAC/M4A mobile; web via blob).
class ChatAudioService {
  AudioRecorder? _recorder;
  String? _path;
  AudioEncoder _encoder = AudioEncoder.aacLc;
  Uint8List? _webBytes;

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

  /// Inicia gravação (mobile: ficheiro `.m4a`; web: blob em memória).
  Future<String?> startRecording() async {
    await stopRecording(send: false);

    final recorder = AudioRecorder();
    var permitted = await recorder.hasPermission();
    if (!permitted) {
      // Segunda tentativa — alguns devices Android pedem diálogo só após start.
      try {
        permitted = await recorder.hasPermission();
      } catch (_) {}
    }
    if (!permitted) {
      await recorder.dispose();
      return null;
    }

    _encoder = AudioEncoder.aacLc;
    if (!await recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      if (await recorder.isEncoderSupported(AudioEncoder.opus)) {
        _encoder = AudioEncoder.opus;
      } else if (await recorder.isEncoderSupported(AudioEncoder.aacHe)) {
        _encoder = AudioEncoder.aacHe;
      }
    }
    if (kIsWeb && !await recorder.isEncoderSupported(_encoder)) {
      _encoder = AudioEncoder.opus;
    }

    String? path;
    if (kIsWeb) {
      path = 'web_voice_${DateTime.now().millisecondsSinceEpoch}';
      await recorder.start(
        MediaService.chatVoiceRecordConfig(encoder: _encoder),
        path: '',
      );
    } else {
      final dir = await getTemporaryDirectory();
      final ext = _encoder == AudioEncoder.opus ? 'opus' : 'm4a';
      path =
          '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await recorder.start(
        MediaService.chatVoiceRecordConfig(encoder: _encoder),
        path: path,
      );
    }

    _recorder = recorder;
    _path = path;
    _webBytes = null;
    return path;
  }

  /// Para gravação; se [send] false, descarta.
  /// Mobile: devolve path do ficheiro. Web: usar [takeWebRecordingBytes].
  Future<String?> stopRecording({required bool send}) async {
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

    if (!send) {
      _webBytes = null;
      final discard = outPath ?? expected;
      if (!kIsWeb && discard != null && discard.isNotEmpty) {
        await churchChatDeleteFileQuiet(discard);
      }
      return null;
    }

    if (kIsWeb) {
      final blobPath = outPath ?? expected ?? '';
      if (blobPath.isNotEmpty &&
          (blobPath.startsWith('blob:') || blobPath.startsWith('http'))) {
        try {
          final r = await http.get(Uri.parse(blobPath));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            _webBytes = Uint8List.fromList(r.bodyBytes);
          }
        } catch (_) {}
      }
      return null;
    }

    final path = outPath ?? expected;
    if (path == null || path.isEmpty) return null;
    if (!kIsWeb) {
      try {
        final f = File(path);
        if (!await f.exists() || await f.length() < 32) return null;
      } catch (_) {
        return null;
      }
    }
    return path;
  }

  /// Bytes da última gravação na web (após [stopRecording] com `send: true`).
  Uint8List? takeWebRecordingBytes() {
    final b = _webBytes;
    _webBytes = null;
    return b;
  }

  Future<void> dispose() async {
    await stopRecording(send: false);
  }
}
