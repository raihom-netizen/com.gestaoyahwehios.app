import 'package:flutter/foundation.dart';

/// Política única de limites para uploads de mídia (painel igreja + master).
///
/// Modo turbo (produção mobile por defeito — uploads mais rápidos em 4G/Wi‑Fi):
/// - Desative com: `--dart-define=GY_MEDIA_TURBO=false`
/// - Force ativo em debug: `--dart-define=GY_MEDIA_TURBO=true`
const int kMediaImagePreferredMaxBytes = 1024 * 1024; // 1MB (padrão)
const int kMediaVideoHardMaxBytes = 120 * 1024 * 1024; // 120MB (padrão)
const Duration kMediaVideoMaxDuration = Duration(seconds: 60); // padrão

bool get kMediaTurboMobilePreset {
  if (kIsWeb) return false;
  if (!const bool.fromEnvironment('GY_MEDIA_TURBO', defaultValue: true)) {
    return false;
  }
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return kReleaseMode;
    default:
      return false;
  }
}

/// Retrocompat — turbo ativo quando o preset mobile está ligado.
bool get kMediaTurboEnabled => kMediaTurboMobilePreset;

int get mediaImagePreferredMaxBytesEffective =>
    kMediaTurboMobilePreset ? (850 * 1024) : kMediaImagePreferredMaxBytes;

int get mediaVideoHardMaxBytesEffective =>
    kMediaTurboMobilePreset ? (100 * 1024 * 1024) : kMediaVideoHardMaxBytes;

Duration get mediaVideoMaxDurationEffective =>
    kMediaTurboMobilePreset ? const Duration(seconds: 50) : kMediaVideoMaxDuration;

int get mediaVideoSkipTranscodeMaxBytes =>
    kMediaTurboMobilePreset ? (42 * 1024 * 1024) : (32 * 1024 * 1024);

/// Uploads em lote (avisos/eventos): no máximo N ficheiros em paralelo (evita saturar 4G).
int get mediaFeedUploadMaxConcurrent =>
    kMediaTurboMobilePreset ? 3 : 4;

int get mediaPickerImageQuality =>
    kMediaTurboMobilePreset ? 62 : 70;

int get mediaPickerImageMaxWidth =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerImageMaxHeight =>
    kMediaTurboMobilePreset ? 720 : 800;

/// Chat: fotos até 1280px (WhatsApp-style, boa qualidade sem payload enorme).
int get mediaChatImageMaxWidth => 1280;

int get mediaChatImageMaxHeight => 1280;

int get mediaChatImageQuality => kMediaTurboMobilePreset ? 72 : 76;

int get mediaPickerLogoQuality =>
    kMediaTurboMobilePreset ? 68 : 70;

int get mediaPickerLogoMaxWidth =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerLogoMaxHeight =>
    kMediaTurboMobilePreset ? 720 : 800;
