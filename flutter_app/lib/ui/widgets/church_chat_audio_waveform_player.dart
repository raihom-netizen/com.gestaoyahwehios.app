import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_inline_audio_player.dart'
    show ChurchChatAudioPlaybackCoordinator;

/// Reprodução de áudio do chat com forma de onda (mobile/desktop nativo).
class ChurchChatAudioWaveformPlayer extends StatefulWidget {
  const ChurchChatAudioWaveformPlayer({
    super.key,
    required this.playablePath,
    required this.messageId,
    this.mine = false,
  });

  final String playablePath;
  final String messageId;
  final bool mine;

  @override
  State<ChurchChatAudioWaveformPlayer> createState() =>
      _ChurchChatAudioWaveformPlayerState();
}

class _ChurchChatAudioWaveformPlayerState
    extends State<ChurchChatAudioWaveformPlayer> {
  final PlayerController _controller = PlayerController();
  bool _ready = false;
  String? _error;
  bool _disposed = false;

  static const Color _accent = Color(0xFF128C7E);

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      await _controller.preparePlayer(
        path: widget.playablePath,
        shouldExtractWaveform: true,
        noOfSamples: 80,
      );
      if (_disposed) return;
      if (mounted) {
        setState(() {
          _ready = true;
          _error = null;
        });
      }
    } catch (e) {
      if (_disposed) return;
      if (mounted) {
        setState(() {
          _ready = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _toggle() async {
    if (!_ready || _error != null) return;
    try {
      if (_controller.playerState == PlayerState.playing) {
        await _controller.pausePlayer();
      } else {
        await ChurchChatAudioPlaybackCoordinator.instance
            .beforePlayWaveform(_controller, widget.messageId);
        await _controller.startPlayer();
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = 'Erro ao reproduzir');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ChurchChatAudioPlaybackCoordinator.instance.unregister(widget.messageId);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Text(
        'Áudio indisponível',
        style: TextStyle(
          fontSize: 13,
          color: ThemeCleanPremium.onSurfaceVariant,
        ),
      );
    }
    if (!_ready) {
      return const SizedBox(
        width: 220,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final fg = widget.mine ? ThemeCleanPremium.primary : _accent;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
      child: Row(
        children: [
          IconButton.filledTonal(
            onPressed: _toggle,
            style: IconButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(8),
              backgroundColor: fg.withValues(alpha: 0.15),
              foregroundColor: fg,
            ),
            icon: Icon(
              _controller.playerState == PlayerState.playing
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 26,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: AudioFileWaveforms(
              size: const Size(double.infinity, 44),
              playerController: _controller,
              enableSeekGesture: true,
              waveformType: WaveformType.fitWidth,
              playerWaveStyle: PlayerWaveStyle(
                fixedWaveColor: ThemeCleanPremium.onSurfaceVariant
                    .withValues(alpha: 0.25),
                liveWaveColor: fg,
                spacing: 3,
                showSeekLine: true,
                seekLineColor: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Descarrega URL de áudio para ficheiro temporário (waveform nativo).
Future<String?> downloadChatAudioToTempFile({
  required String url,
  required String messageId,
}) async {
  if (kIsWeb) return null;
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final dir = await getTemporaryDirectory();
    final safeId = messageId.replaceAll(RegExp(r'[^\w]'), '_');
    final file = File('${dir.path}/chat_audio_$safeId.m4a');
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
