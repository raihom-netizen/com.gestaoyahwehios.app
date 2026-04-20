import 'package:flutter/foundation.dart';

/// Política única de limites para uploads de mídia (painel igreja + master).
///
/// Modo turbo (opcional):
/// - Ative com: `--dart-define=GY_MEDIA_TURBO=true`
/// - Produção mobile usa preset mais agressivo quando ativo.
const int kMediaImagePreferredMaxBytes = 1024 * 1024; // 1MB (padrão)
const int kMediaVideoHardMaxBytes = 120 * 1024 * 1024; // 120MB (padrão)
const Duration kMediaVideoMaxDuration = Duration(seconds: 60); // padrão

bool get kMediaTurboEnabled =>
    const bool.fromEnvironment('GY_MEDIA_TURBO', defaultValue: false);

bool get kMediaTurboMobilePreset {
  if (!kMediaTurboEnabled) return false;
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return kReleaseMode;
    default:
      return false;
  }
}

int get mediaImagePreferredMaxBytesEffective =>
    kMediaTurboMobilePreset ? (850 * 1024) : kMediaImagePreferredMaxBytes;

int get mediaVideoHardMaxBytesEffective =>
    kMediaTurboMobilePreset ? (100 * 1024 * 1024) : kMediaVideoHardMaxBytes;

Duration get mediaVideoMaxDurationEffective =>
    kMediaTurboMobilePreset ? const Duration(seconds: 50) : kMediaVideoMaxDuration;

int get mediaVideoSkipTranscodeMaxBytes =>
    kMediaTurboMobilePreset ? (20 * 1024 * 1024) : (26 * 1024 * 1024);

int get mediaPickerImageQuality =>
    kMediaTurboMobilePreset ? 62 : 70;

int get mediaPickerImageMaxWidth =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerImageMaxHeight =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerLogoQuality =>
    kMediaTurboMobilePreset ? 68 : 70;

int get mediaPickerLogoMaxWidth =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerLogoMaxHeight =>
    kMediaTurboMobilePreset ? 720 : 800;
