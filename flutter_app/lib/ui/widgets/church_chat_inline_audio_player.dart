import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show firebaseStorageDownloadUrlLooksTokenized, sanitizeImageUrl;
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:audio_waveforms/audio_waveforms.dart' show PlayerController;
import 'package:gestao_yahweh/ui/widgets/church_chat_audio_waveform_player.dart';
import 'package:just_audio/just_audio.dart';

/// Garante que só um áudio do chat toca de cada vez (estilo WhatsApp).
class ChurchChatAudioPlaybackCoordinator {
  ChurchChatAudioPlaybackCoordinator._();
  static final ChurchChatAudioPlaybackCoordinator instance =
      ChurchChatAudioPlaybackCoordinator._();

  AudioPlayer? _active;
  PlayerController? _activeWaveform;
  String? _activeMessageId;

  Future<void> beforePlay(AudioPlayer player, String messageId) async {
    if (_activeWaveform != null) {
      try {
        await _activeWaveform!.pausePlayer();
      } catch (_) {}
      _activeWaveform = null;
    }
    if (_active != null && !identical(_active, player)) {
      try {
        await _active!.stop();
      } catch (_) {}
    }
    _active = player;
    _activeMessageId = messageId;
  }

  Future<void> beforePlayWaveform(
    PlayerController controller,
    String messageId,
  ) async {
    if (_active != null) {
      try {
        await _active!.stop();
      } catch (_) {}
      _active = null;
    }
    if (_activeWaveform != null && !identical(_activeWaveform, controller)) {
      try {
        await _activeWaveform!.pausePlayer();
      } catch (_) {}
    }
    _activeWaveform = controller;
    _activeMessageId = messageId;
  }

  void unregister(String messageId) {
    if (_activeMessageId == messageId) {
      _active = null;
      _activeWaveform = null;
      _activeMessageId = null;
    }
  }
}

/// Áudio da conversa com play/pause e barra de progresso — sem abrir URL externa.
class ChurchChatInlineAudioPlayer extends StatefulWidget {
  final String mediaUrl;
  final String? storagePath;
  final String messageId;
  final bool mine;

  const ChurchChatInlineAudioPlayer({
    super.key,
    required this.mediaUrl,
    required this.messageId,
    this.storagePath,
    this.mine = false,
  });

  @override
  State<ChurchChatInlineAudioPlayer> createState() =>
      _ChurchChatInlineAudioPlayerState();
}

class _ChurchChatInlineAudioPlayerState extends State<ChurchChatInlineAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = true;
  String? _error;
  String? _localPath;
  bool _useWaveform = false;
  bool _disposed = false;

  static const Color _accent = Color(0xFF128C7E);

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<String?> _resolveUrl() async {
    final m = sanitizeImageUrl(widget.mediaUrl.trim());
    if (!kIsWeb && firebaseStorageDownloadUrlLooksTokenized(m)) {
      return m;
    }
    final sp = widget.storagePath?.trim() ?? '';
    for (final candidate in <String>[m, sp]) {
      if (candidate.isEmpty) continue;
      try {
        final u = await StorageMediaService.freshPlayableMediaUrl(candidate);
        if (u.trim().isNotEmpty) return u.trim();
      } catch (_) {}
      if (!kIsWeb &&
          firebaseStorageDownloadUrlLooksTokenized(
              sanitizeImageUrl(candidate))) {
        return sanitizeImageUrl(candidate);
      }
      try {
        final u = await StorageMediaService.downloadUrlFromPathOrUrl(candidate);
        if (u != null && u.trim().isNotEmpty) return u.trim();
      } catch (_) {}
    }
    return null;
  }

  Future<void> _prepare() async {
    try {
      final resolved = await _resolveUrl();
      if (_disposed) return;
      if (resolved == null || resolved.isEmpty) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Áudio indisponível';
          });
        }
        return;
      }
      if (!kIsWeb) {
        final path = await downloadChatAudioToTempFile(
          url: resolved,
          messageId: widget.messageId,
        );
        if (path != null && path.isNotEmpty) {
          _localPath = path;
          _useWaveform = true;
          if (mounted) {
            setState(() {
              _loading = false;
              _error = null;
            });
          }
          return;
        }
      }
      await _player.setUrl(resolved);
      if (_disposed) return;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _useWaveform = false;
        });
      }
    } catch (_) {
      if (_disposed) return;
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Não foi possível carregar o áudio';
        });
      }
    }
  }

  Future<void> _toggle() async {
    if (_loading || _error != null) return;
    try {
      if (_player.playing) {
        await _player.pause();
      } else {
        await ChurchChatAudioPlaybackCoordinator.instance
            .beforePlay(_player, widget.messageId);
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Erro ao reproduzir');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ChurchChatAudioPlaybackCoordinator.instance.unregister(widget.messageId);
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_useWaveform && _localPath != null && _error == null) {
      return ChurchChatAudioWaveformPlayer(
        playablePath: _localPath!,
        messageId: widget.messageId,
        mine: widget.mine,
      );
    }
    if (_loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.mine
                  ? ThemeCleanPremium.primary
                  : _accent,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'A carregar…',
            style: TextStyle(
              fontSize: 13,
              color: ThemeCleanPremium.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }
    if (_error != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 20, color: ThemeCleanPremium.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 13,
                color: ThemeCleanPremium.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300, minWidth: 220),
      child: StreamBuilder<PlayerState>(
        stream: _player.playerStateStream,
        initialData: _player.playerState,
        builder: (context, stateSnap) {
          final playing = stateSnap.data?.playing ?? false;
          final fg = widget.mine ? ThemeCleanPremium.primary : _accent;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mic_rounded, color: fg, size: 22),
              ),
              const SizedBox(width: 8),
              Material(
                color: fg.withValues(alpha: 0.12),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: fg,
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  initialData: _player.position,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = _player.duration ?? Duration.zero;
                    final totalMs = dur.inMilliseconds;
                    final v = totalMs > 0
                        ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                        : 0.0;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: totalMs > 0 ? v : null,
                            minHeight: 4,
                            backgroundColor: ThemeCleanPremium.onSurfaceVariant
                                .withValues(alpha: 0.12),
                            color: fg,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtDur(dur.inMilliseconds > 0 ? pos : Duration.zero),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ThemeCleanPremium.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _fmtDur(Duration d) {
    final s = d.inSeconds;
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
}
