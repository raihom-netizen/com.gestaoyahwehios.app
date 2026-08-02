import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/ui/widgets/church_chat_audio_waveform_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

/// Mídia recebida pelo TDLib — thumb rápido + full no tap; áudio com ondas.
class TdlibLocalMedia extends StatefulWidget {
  const TdlibLocalMedia({
    super.key,
    required this.message,
    this.outgoing = false,
  });

  final TdlibMessageItem message;
  final bool outgoing;

  @override
  State<TdlibLocalMedia> createState() => _TdlibLocalMediaState();
}

class _TdlibLocalMediaState extends State<TdlibLocalMedia> {
  String? _path;
  String? _thumbPath;
  bool _loading = false;
  Object? _error;
  VideoPlayerController? _video;
  AudioPlayer? _audio;

  String get _kind => widget.message.mediaKind ?? '';

  @override
  void initState() {
    super.initState();
    final full = (widget.message.mediaLocalPath ?? '').trim();
    final thumb = (widget.message.mediaThumbLocalPath ?? '').trim();
    if (full.isNotEmpty) _path = full;
    if (thumb.isNotEmpty) _thumbPath = thumb;
    if (_kind == 'photo') {
      unawaited(_ensureDownloaded(preferThumb: true));
    } else if (_path != null) {
      unawaited(_preparePlayer());
    }
  }

  @override
  void didUpdateWidget(covariant TdlibLocalMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.message.mediaLocalPath ?? '').trim();
    final nextThumb = (widget.message.mediaThumbLocalPath ?? '').trim();
    if (nextThumb.isNotEmpty && nextThumb != _thumbPath) {
      _thumbPath = nextThumb;
    }
    if (next.isNotEmpty && next != _path) {
      _path = next;
      unawaited(_preparePlayer());
    }
  }

  Future<void> _ensureDownloaded({bool preferThumb = false}) async {
    if (_loading) return;
    final current = _path;
    if (current != null && await File(current).exists()) {
      await _preparePlayer();
      if (mounted) setState(() {});
      return;
    }
    if (preferThumb) {
      final thumb = _thumbPath;
      if (thumb != null && await File(thumb).exists()) {
        if (mounted) setState(() {});
        // Full em background.
        unawaited(_downloadFullQuiet());
        return;
      }
      if (widget.message.mediaThumbFileId != null) {
        if (mounted) {
          setState(() {
            _loading = true;
            _error = null;
          });
        }
        try {
          final thumbMsg = widget.message.copyWith(
            mediaFileId: widget.message.mediaThumbFileId,
            mediaLocalPath: widget.message.mediaThumbLocalPath,
          );
          final path = await TdLibService.instance.ensureMediaDownloaded(
            thumbMsg,
            priority: 10,
          );
          if (path != null && path.isNotEmpty) {
            _thumbPath = path;
          }
        } catch (_) {}
        if (mounted) setState(() => _loading = false);
        unawaited(_downloadFullQuiet());
        return;
      }
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final path = await TdLibService.instance.ensureMediaDownloaded(
        widget.message,
      );
      if (path == null || path.isEmpty) {
        throw StateError('Arquivo ainda não disponível');
      }
      _path = path;
      await _preparePlayer();
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadFullQuiet() async {
    try {
      final path = await TdLibService.instance.ensureMediaDownloaded(
        widget.message,
        priority: 6,
      );
      if (path == null || path.isEmpty) return;
      _path = path;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _preparePlayer() async {
    final path = _path;
    if (path == null || path.isEmpty) return;
    if (_kind == 'video' && _video == null) {
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      _video = controller;
    } else if ((_kind == 'voice' || _kind == 'audio') && _audio == null) {
      final player = AudioPlayer();
      await player.setFilePath(path);
      _audio = player;
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    unawaited(_audio?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _thumbPath == null && _path == null) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null && _thumbPath == null && _path == null) {
      return TextButton.icon(
        onPressed: () => _ensureDownloaded(),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Tentar mídia novamente'),
      );
    }
    final path = _path;
    final displayPhoto = path ?? _thumbPath;
    if (_kind == 'photo' && displayPhoto != null) {
      return GestureDetector(
        onTap: () async {
          await _ensureDownloaded();
          final full = _path ?? displayPhoto;
          if (!context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  title: const Text('Foto'),
                ),
                body: Center(
                  child: InteractiveViewer(
                    child: Image.file(File(full), fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(displayPhoto),
            width: 240,
            height: 180,
            fit: BoxFit.cover,
            cacheWidth: path == null ? 360 : 720,
            errorBuilder: (_, _, _) => _downloadButton(
              icon: Icons.image_not_supported_outlined,
              label: 'Recarregar foto',
            ),
          ),
        ),
      );
    }
    if (_kind == 'video' && _video?.value.isInitialized == true) {
      final controller = _video!;
      return GestureDetector(
        onTap: () {
          controller.value.isPlaying ? controller.pause() : controller.play();
          setState(() {});
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0
                ? 16 / 9
                : controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),
                if (!controller.value.isPlaying)
                  const Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if ((_kind == 'voice' || _kind == 'audio') && path != null) {
      return ChurchChatAudioWaveformPlayer(
        playablePath: path,
        messageId: 'tdlib_${widget.message.chatId}_${widget.message.id}',
        mine: widget.outgoing,
      );
    }
    if ((_kind == 'voice' || _kind == 'audio') && _audio != null) {
      return StreamBuilder<PlayerState>(
        stream: _audio!.playerStateStream,
        builder: (context, snapshot) {
          final playing = snapshot.data?.playing == true;
          return TextButton.icon(
            onPressed: () => playing ? _audio!.pause() : _audio!.play(),
            icon: Icon(
              playing ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
            ),
            label: Text(playing ? 'Pausar áudio' : 'Reproduzir áudio'),
          );
        },
      );
    }
    if (_kind == 'document' && path != null) {
      return TextButton.icon(
        onPressed: () => OpenFilex.open(path),
        icon: const Icon(Icons.description_rounded),
        label: Text(widget.message.fileName ?? 'Abrir arquivo'),
      );
    }
    return _downloadButton(
      icon: switch (_kind) {
        'video' => Icons.download_for_offline_rounded,
        'voice' || 'audio' => Icons.audio_file_rounded,
        'document' => Icons.file_download_rounded,
        _ => Icons.cloud_download_rounded,
      },
      label: switch (_kind) {
        'video' => 'Baixar vídeo',
        'voice' || 'audio' => 'Baixar áudio',
        'document' => widget.message.fileName ?? 'Baixar arquivo',
        _ => 'Baixar mídia',
      },
    );
  }

  Widget _downloadButton({required IconData icon, required String label}) {
    return TextButton.icon(
      onPressed: () => _ensureDownloaded(),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
