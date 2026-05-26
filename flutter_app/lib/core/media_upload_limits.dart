import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;

/// Política única de limites para uploads de mídia (painel igreja + master).
///
/// Modo turbo (produção mobile por defeito — uploads mais rápidos em 4G/Wi‑Fi):
/// - Desative com: `--dart-define=GY_MEDIA_TURBO=false`
/// - Force ativo em debug: `--dart-define=GY_MEDIA_TURBO=true`
const int kMediaImagePreferredMaxBytes = 1024 * 1024; // 1MB (padrão)
const int kMediaVideoHardMaxBytes = 120 * 1024 * 1024; // 120MB (padrão)
const Duration kMediaVideoMaxDuration = Duration(seconds: 60); // legado / outros módulos

/// Chat igreja — vídeo até 90 s (estilo WhatsApp).
const Duration kMediaChatVideoMaxDuration = Duration(seconds: 90);

/// Eventos (editor + galeria) — vídeo até 90 s.
const int kMediaEventVideoMaxSeconds = 90;

Duration get mediaEventVideoMaxDurationEffective =>
    Duration(seconds: kMediaEventVideoMaxSeconds);

/// Eventos mobile — rejeita vídeo bruto acima deste tamanho antes de transcodificar (evita timeout em 4G).
/// Equivalente ao `limiteMaximoMB = 15` do fluxo web.
const int kMediaEventVideoMobilePickMaxBytes = 15 * 1024 * 1024;

int get mediaEventVideoMobilePickMaxBytesEffective =>
    kMediaEventVideoMobilePickMaxBytes;

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

Duration get mediaVideoMaxDurationEffective => kMediaChatVideoMaxDuration;

int get mediaVideoSkipTranscodeMaxBytes =>
    kMediaTurboMobilePreset ? (42 * 1024 * 1024) : (32 * 1024 * 1024);

/// Uploads em lote (avisos/eventos): iOS = 1 por vez (evita OOM); Android até 3–4.
int get mediaFeedUploadMaxConcurrent {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return 1;
  }
  return kMediaTurboMobilePreset ? 3 : 4;
}

int get mediaPickerImageQuality =>
    kMediaTurboMobilePreset ? 62 : 70;

int get mediaPickerImageMaxWidth =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerImageMaxHeight =>
    kMediaTurboMobilePreset ? 720 : 800;

/// Chat: fotos até 1280px (WhatsApp-style, boa qualidade sem payload enorme).
int get mediaChatImageMaxWidth => 1280;

int get mediaChatImageMaxHeight => 1280;

int get mediaChatImageQuality => 70;

int get mediaPickerLogoQuality =>
    kMediaTurboMobilePreset ? 68 : 70;

int get mediaPickerLogoMaxWidth =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerLogoMaxHeight =>
    kMediaTurboMobilePreset ? 720 : 800;
