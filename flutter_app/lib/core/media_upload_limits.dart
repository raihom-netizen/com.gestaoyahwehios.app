import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Política única de limites para uploads de mídia (painel igreja + master).
///
/// Modo turbo (produção mobile por defeito — uploads mais rápidos em 4G/Wi‑Fi):
/// - Desative com: `--dart-define=GY_MEDIA_TURBO=false`
/// - Force ativo em debug: `--dart-define=GY_MEDIA_TURBO=true`
const int kMediaImagePreferredMaxBytes = 1024 * 1024; // 1MB (padrão)

/// Acima deste tamanho: comprimir automaticamente antes do upload (avisos, eventos, chat).
const int kAutoCompressImageThresholdBytes = 3 * 1024 * 1024;

/// Vídeo bruto acima disto: recomprimir (eventos/chat) antes do upload.
const int kAutoRecompressVideoThresholdBytes = 50 * 1024 * 1024;

/// Eventos — spec de transcodificação (720p H.264 ~2 Mbps AAC).
const int kMediaEventVideoTargetHeightPx = 720;
const int kMediaEventVideoTargetBitrateMbps = 2;

const int kMediaVideoHardMaxBytes = 120 * 1024 * 1024; // 120MB (padrão)

/// Chat Igreja — vídeo até 200 MB (spec WhatsApp-like).
const int kMediaChatVideoHardMaxBytes = 200 * 1024 * 1024;
const Duration kMediaVideoMaxDuration = Duration(seconds: 60); // legado / outros módulos

/// Chat igreja — vídeo até 90 s (estilo WhatsApp).
const Duration kMediaChatVideoMaxDuration = Duration(seconds: 90);

/// Uploads de mídia no chat em paralelo (fotos/vídeos do lote).
const int kChatMaxConcurrentMediaUploads = 4;

/// Timeout para fotos **já compactadas** (≤ ~1 MB).
/// Mínimo 3 min: redes 4G/igrejas com sinal instável não podem cancelar envio válido.
const int kStorageUploadCompressedImageMaxSeconds = 180;

/// Tamanho máximo (bytes) para aplicar timeout curto de 30 s.
const int kStorageUploadCompressedImageMaxBytes = 1024 * 1024;

/// Timeout máximo para uploads de imagem/comprovante (~2–3 MB, ainda não compactadas).
const int kStorageUploadImageMaxSeconds = 180;

/// Cancela upload se bytes não avançarem neste intervalo (imagens compactadas).
/// 3 min sem avanço real = upload travado; pausas curtas de rede devem retomar.
const int kStorageUploadCompressedImageStallSeconds = 180;

/// Cancela upload se bytes não avançarem neste intervalo (imagens maiores).
const int kStorageUploadImageStallSeconds = 180;

/// Teto alinhado às regras Storage (`storage.rules`) para fotos de feed/perfil/património.
const int kStorageRulesMaxFeedImageBytes = 10 * 1024 * 1024;

/// PDF/comprovante financeiro — regra Storage até 25 MB.
const int kStorageRulesMaxFinanceDocBytes = 25 * 1024 * 1024;

/// Chat vídeo — regra Storage até 200 MB.
const int kStorageRulesMaxChatVideoBytes = 200 * 1024 * 1024;

/// Património — até 4 fotos por bem (móvel, equipamento, veículo, etc.).
const int kMaxPatrimonioPhotosPerItem = 5;

/// Eventos (editor + galeria) — vídeo até 90 s.
const int kMediaEventVideoMaxSeconds = 90;

/// Eventos — teto de 100 MB após compressão (spec produção).
const int kMediaEventVideoHardMaxBytes = 100 * 1024 * 1024;

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
      return true;
    default:
      return false;
  }
}

/// Retrocompat — turbo ativo quando o preset mobile está ligado.
bool get kMediaTurboEnabled => kMediaTurboMobilePreset;

int get mediaImagePreferredMaxBytesEffective =>
    kMediaTurboMobilePreset ? (850 * 1024) : kMediaImagePreferredMaxBytes;

int get mediaVideoHardMaxBytesEffective =>
    kMediaTurboMobilePreset
        ? kMediaEventVideoHardMaxBytes
        : kMediaVideoHardMaxBytes;

int get mediaEventVideoHardMaxBytesEffective => kMediaEventVideoHardMaxBytes;

int get mediaChatVideoHardMaxBytesEffective => kMediaChatVideoHardMaxBytes;

Duration get mediaVideoMaxDurationEffective => kMediaChatVideoMaxDuration;

int get mediaVideoSkipTranscodeMaxBytes =>
    kMediaTurboMobilePreset ? (64 * 1024 * 1024) : (32 * 1024 * 1024);

/// Uploads em lote (avisos/eventos): paralelo limitado (turbo mobile = mais rápido em Wi‑Fi/4G).
int get mediaFeedUploadMaxConcurrent {
  if (kIsWeb) return 6;
  return kMediaTurboMobilePreset ? 4 : 3;
}

/// Lado máximo e qualidade padrão para fotos antes do Firebase Storage
/// (avisos, eventos, chat, património, membros).
const int kStandardUploadImageMaxEdge = 1024;
const int kStandardUploadImageQuality = 80;

int get mediaPickerImageQuality => kStandardUploadImageQuality;

int get mediaPickerImageMaxWidth => kStandardUploadImageMaxEdge;

int get mediaPickerImageMaxHeight => kStandardUploadImageMaxEdge;

/// Chat: mesma política 1024 px / 75% (upload rápido e estável em 4G).
int get mediaChatImageMaxWidth => kStandardUploadImageMaxEdge;

int get mediaChatImageMaxHeight => kStandardUploadImageMaxEdge;

int get mediaChatImageQuality => kStandardUploadImageQuality;

/// Chat — até 10 fotos por seleção (galeria / encaminhar lote).
const int kChatMaxImagesPerPick = 10;
const int kChatMaxVideosPerPick = 5;
const int kChatMaxDocumentsPerPick = 10;
const int kChatMaxAudioFilesPerPick = 5;

/// PDF / Word / ZIP / RAR no chat (web envia bytes; mobile usa ficheiro no disco).
const int kChatMaxDocumentBytes = 50 * 1024 * 1024;

int get mediaPickerLogoQuality =>
    kMediaTurboMobilePreset ? 68 : 70;

int get mediaPickerLogoMaxWidth =>
    kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerLogoMaxHeight =>
    kMediaTurboMobilePreset ? 720 : 800;
