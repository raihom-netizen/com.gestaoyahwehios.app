import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Obtém duração do vídeo em segundos (apenas mobile/desktop; na web use o stub).
Future<int?> getVideoDurationSeconds(XFile? file) async {
  if (file == null || file.path.isEmpty) return null;
  try {
    final controller = VideoPlayerController.file(File(file.path));
    await controller.initialize();
    final sec = controller.value.duration.inSeconds;
    await controller.dispose();
    return sec;
  } catch (_) {
    return null;
  }
}
