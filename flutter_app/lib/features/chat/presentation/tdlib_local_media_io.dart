import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:video_player/video_player.dart';

/// Mídia recebida pelo TDLib. O próprio Telegram baixa e mantém o ficheiro no
/// cache local; foto carrega sob demanda visual e ficheiros grandes só no tap.
class TdlibLocalMedia extends StatefulWidget {
  const TdlibLocalMedia({super.key, required this.message});

  final TdlibMessageItem message;

  @override
  State<TdlibLocalMedia> createState() => _TdlibLocalMediaState();
}

class _TdlibLocalMediaState extends State<TdlibLocalMedia> {
  String? _path;
  bool _loading = false;
  Object? _error;
  VideoPlayerController? _video;
  AudioPlayer? _audio;

  String get _kind => widget.message.mediaKind ?? '';

  @override
  void initState() {
    super.initState();
    final local = (widget.message.mediaLocalPath ?? '').trim();
    if (local.isNotEmpty) _path = local;
    if (_kind == 'photo') {
      unawaited(_ensureDownloaded());
    } else if (_path != null) {
      unawaited(_preparePlayer());
    }
  }

  @override
  void didUpdateWidget(covariant TdlibLocalMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = (widget.message.mediaLocalPath ?? '').trim();
    if (next.isNotEmpty && next != _path) {
      _path = next;
      unawaited(_preparePlayer());
    }
  }

  Future<void> _ensureDownloaded() async {
    if (_loading) return;
    final current = _path;
    if (current != null && await File(current).exists()) {
      await _preparePlayer();
      if (mounted) setState(() {});
      return;
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
    if (_loading) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (_error != null) {
      return TextButton.icon(
        onPressed: _ensureDownloaded,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Tentar mídia novamente'),
      );
    }
    final path = _path;
    if (_kind == 'photo' && path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(path),
          width: 240,
          height: 180,
          fit: BoxFit.cover,
          cacheWidth: 720,
          errorBuilder: (_, _, _) => _downloadButton(
            icon: Icons.image_not_supported_outlined,
            label: 'Recarregar foto',
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
      onPressed: _ensureDownloaded,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
