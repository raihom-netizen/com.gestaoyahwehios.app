import 'utilitarios_local_service.dart';

/// Resolução de exportação MP4.
enum UtilitariosVideoExportResolution {
  fullHd,
  fourK,
}

extension UtilitariosVideoExportResolutionX on UtilitariosVideoExportResolution {
  String get label => switch (this) {
        UtilitariosVideoExportResolution.fullHd => 'Full HD',
        UtilitariosVideoExportResolution.fourK => '4K',
      };

  String get subtitle => switch (this) {
        UtilitariosVideoExportResolution.fullHd =>
          '1080p · ideal para WhatsApp e redes',
        UtilitariosVideoExportResolution.fourK =>
          '2160p · máxima nitidez (arquivo maior)',
      };
}

/// Formato de áudio extraído do vídeo.
enum UtilitariosAudioExtractFormat {
  m4a,
  mp3,
}

extension UtilitariosAudioExtractFormatX on UtilitariosAudioExtractFormat {
  String get label => switch (this) {
        UtilitariosAudioExtractFormat.m4a => 'M4A (AAC)',
        UtilitariosAudioExtractFormat.mp3 => 'MP3',
      };

  String get subtitle => switch (this) {
        UtilitariosAudioExtractFormat.m4a =>
          'Rápido · alta qualidade no iPhone/Android',
        UtilitariosAudioExtractFormat.mp3 =>
          'Compatível com tudo · leve',
      };

  String get extension => switch (this) {
        UtilitariosAudioExtractFormat.m4a => 'm4a',
        UtilitariosAudioExtractFormat.mp3 => 'mp3',
      };

  String get mimeType => switch (this) {
        UtilitariosAudioExtractFormat.m4a => 'audio/mp4',
        UtilitariosAudioExtractFormat.mp3 => 'audio/mpeg',
      };
}

/// Opções da conversão Vídeo → MP4.
class UtilitariosVideoConvertOptions {
  const UtilitariosVideoConvertOptions({
    required this.resolution,
    this.compressAlso = false,
    this.compressLevel = UtilitariosCompressLevel.media,
  });

  final UtilitariosVideoExportResolution resolution;
  final bool compressAlso;
  final UtilitariosCompressLevel compressLevel;
}
