import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/chat_audio_web_blob.dart';
import 'package:gestao_yahweh/services/church_chat_fs.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:record/record.dart';

class ChatMicrophonePermissionException implements Exception {
  const ChatMicrophonePermissionException({required this.permanentlyDenied});

  final bool permanentlyDenied;

  @override
  String toString() => permanentlyDenied
      ? 'Permissão de microfone bloqueada nos Ajustes.'
      : 'Permissão de microfone negada.';
}

/// Gravação de voz estilo WhatsApp para o Chat Igreja (AAC/M4A mobile; web via blob).
class ChatAudioService {
  AudioRecorder? _recorder;
  String? _path;
  AudioEncoder _encoder = AudioEncoder.aacLc;
  Uint8List? _webBytes;
  static AudioEncoder? _cachedEncoder;

  bool get isRecording => _recorder != null;
  String? get currentPath => _path;

  Future<AudioEncoder> _resolveEncoder(AudioRecorder recorder) async {
    final cached = _cachedEncoder;
    if (cached != null) {
      try {
        if (await recorder.isEncoderSupported(cached)) return cached;
      } catch (_) {}
    }
    var encoder = AudioEncoder.aacLc;
    if (!await recorder.isEncoderSupported(AudioEncoder.aacLc)) {
      if (await recorder.isEncoderSupported(AudioEncoder.opus)) {
        encoder = AudioEncoder.opus;
      } else if (await recorder.isEncoderSupported(AudioEncoder.aacHe)) {
        encoder = AudioEncoder.aacHe;
      }
    }
    if (kIsWeb && !await recorder.isEncoderSupported(encoder)) {
      encoder = AudioEncoder.opus;
    }
    _cachedEncoder = encoder;
    return encoder;
  }

  Future<void> _ensureMicrophonePermission() async {
    if (kIsWeb) return;
    final status = await ph.Permission.microphone.status;
    if (status.isGranted || status.isLimited) return;
    if (status.isPermanentlyDenied || status.isRestricted) {
      throw const ChatMicrophonePermissionException(permanentlyDenied: true);
    }
    final requested = await ph.Permission.microphone.request();
    if (requested.isGranted || requested.isLimited) return;
    throw ChatMicrophonePermissionException(
      permanentlyDenied:
          requested.isPermanentlyDenied || requested.isRestricted,
    );
  }

  static Future<bool> openAppMicrophoneSettings() async {
    if (kIsWeb) return false;
    try {
      return ph.openAppSettings();
    } catch (_) {
      return false;
    }
  }

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
    // iOS: pedir autorização nativa primeiro. Consultar o plugin `record`
    // simultaneamente cria uma corrida e pode devolver "negado" durante o popup.
    await _ensureMicrophonePermission();
    final recorder = AudioRecorder();
    var permitted = await recorder.hasPermission();
    if (!permitted) {
      try {
        permitted = await recorder.hasPermission();
      } catch (_) {}
    }
    if (!permitted) {
      await recorder.dispose();
      throw const ChatMicrophonePermissionException(permanentlyDenied: true);
    }

    _encoder = await _resolveEncoder(recorder);

    String? path;
    if (kIsWeb) {
      path = 'web_voice_${DateTime.now().millisecondsSinceEpoch}';
      await recorder.start(
        MediaService.chatVoiceRecordConfig(encoder: _encoder),
        path: '',
      );
      if (!await recorder.isRecording()) {
        await recorder.dispose();
        return null;
      }
    } else {
      final dir = await getTemporaryDirectory();
      final ext = _encoder == AudioEncoder.opus ? 'opus' : 'm4a';
      path =
          '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await recorder.start(
        MediaService.chatVoiceRecordConfig(encoder: _encoder),
        path: path,
      );
      if (!await recorder.isRecording()) {
        await recorder.dispose();
        return null;
      }
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
      if (blobPath.isNotEmpty) {
        for (var attempt = 0; attempt < 6; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(Duration(milliseconds: 80 * attempt));
          }
          _webBytes = await readRecordingBlob(blobPath);
          if (_webBytes != null && _webBytes!.isNotEmpty) break;
        }
        if ((_webBytes == null || _webBytes!.isEmpty) &&
            (blobPath.startsWith('blob:') || blobPath.startsWith('http'))) {
          try {
            final r = await http.get(Uri.parse(blobPath));
            if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
              _webBytes = Uint8List.fromList(r.bodyBytes);
            }
          } catch (_) {}
        }
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
