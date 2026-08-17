import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class UtilitariosVideoEditorPage extends StatefulWidget {
  const UtilitariosVideoEditorPage({super.key});

  @override
  State<UtilitariosVideoEditorPage> createState() =>
      _UtilitariosVideoEditorPageState();
}

class _UtilitariosVideoEditorPageState
    extends State<UtilitariosVideoEditorPage> {
  VideoPlayerController? _player;
  String? _path;
  bool _busy = false;
  String? _status;

  bool get _ready => _player?.value.isInitialized == true;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final pick = await FilePicker.pickFiles(type: FileType.video);
      final path = pick?.files.single.path;
      if (path == null || path.isEmpty) return;
      final next = VideoPlayerController.file(File(path));
      await next.initialize();
      final old = _player;
      _player = next;
      _path = path;
      await old?.dispose();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Não foi possível abrir o vídeo: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlay() async {
    final player = _player;
    if (player == null) return;
    if (player.value.isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      appBar: AppBar(title: const Text('Editor de vídeo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _open,
            icon: const Icon(Icons.video_library_rounded),
            label: Text(_busy ? 'Abrindo vídeo…' : 'Selecionar vídeo'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_ready && player != null) ...[
            const SizedBox(height: 20),
            AspectRatio(
              aspectRatio: player.value.aspectRatio == 0
                  ? 16 / 9
                  : player.value.aspectRatio,
              child: VideoPlayer(player),
            ),
            const SizedBox(height: 12),
            VideoProgressIndicator(player, allowScrubbing: true),
            const SizedBox(height: 12),
            Center(
              child: IconButton.filled(
                onPressed: _togglePlay,
                icon: Icon(
                  player.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                tooltip: player.value.isPlaying ? 'Pausar' : 'Reproduzir',
              ),
            ),
            if (_path != null)
              Text(_path!, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}
