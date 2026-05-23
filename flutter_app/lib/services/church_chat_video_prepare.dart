import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/services/media_service.dart';

/// Comprime vídeo da galeria/câmara antes do upload no Chat Igreja (mobile).
class ChurchChatVideoPrepare {
  ChurchChatVideoPrepare._();

  static Future<String> preparePathForUpload(String inputPath) async {
    if (kIsWeb) return inputPath;
    final result = await MediaService.prepareVideoForUpload(inputPath);
    return result?.outputPath ?? inputPath;
  }
}
