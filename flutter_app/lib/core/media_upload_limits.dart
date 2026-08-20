import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Política única de limites para uploads de mídia (painel igreja + master).
///
/// Modo turbo (produção mobile por defeito — uploads mais rápidos em 4G/Wi‑Fi):
/// - Desative com: `--dart-define=GY_MEDIA_TURBO=false`
/// - Force ativo em debug: `--dart-define=GY_MEDIA_TURBO=true`
const int kMediaImagePreferredMaxBytes = 1024 * 1024; // 1MB (padrão)

/// Acima deste tamanho: comprimir automaticamente antes do upload (avisos, eventos, chat).
/// 1.5 MB — comprime menos imagens (a maioria já sai do picker < 1.5 MB após compressão).
const int kAutoCompressImageThresholdBytes = 1536 * 1024;

/// Vídeo bruto acima disto: recomprimir (eventos/chat) antes do upload.
const int kAutoRecompressVideoThresholdBytes = 50 * 1024 * 1024;

/// Eventos — spec de transcodificação (720p H.264 ~2 Mbps AAC).
const int kMediaEventVideoTargetHeightPx = 720;
const int kMediaEventVideoTargetBitrateMbps = 2;

const int kMediaVideoHardMaxBytes = 120 * 1024 * 1024; // 120MB (padrão)

/// Chat Igreja — vídeo até 200 MB (spec WhatsApp-like).
const int kMediaChatVideoHardMaxBytes = 200 * 1024 * 1024;

/// Feed da igreja (Avisos + Eventos) — vídeo até **2 minutos**.
/// Fonte única: quem precisa da duração máxima lê daqui (nunca 90 hardcoded).
const Duration kMediaFeedVideoMaxDuration = Duration(seconds: 120);

const Duration kMediaVideoMaxDuration =
    kMediaFeedVideoMaxDuration; // legado / outros módulos

/// Chat igreja — alinhado ao feed (2 min).
const Duration kMediaChatVideoMaxDuration = kMediaFeedVideoMaxDuration;

/// Uploads de mídia no chat em paralelo.
/// Dois preservam banda para o envio aberto pelo utilizador e evitam que o
/// outbox sature a ligação enquanto Avisos/Eventos também publicam.
const int kChatMaxConcurrentMediaUploads = 2;

/// Timeout para fotos **já compactadas** (≤ ~1 MB).
/// 90s: redes 4G lentas ainda cabem; evita hang eterno de 3 min.
const int kStorageUploadCompressedImageMaxSeconds = 90;

/// Tamanho máximo (bytes) para aplicar timeout curto de imagem compactada.
const int kStorageUploadCompressedImageMaxBytes = 1024 * 1024;

/// Timeout máximo para uploads de imagem/comprovante (~2–3 MB, ainda não compactadas).
const int kStorageUploadImageMaxSeconds = 120;

/// Cancela upload se bytes não avançarem neste intervalo (imagens compactadas).
/// 25s sem avanço = upload travado; falhar rápido → «Tentar de novo».
const int kStorageUploadCompressedImageStallSeconds = 25;

/// Cancela upload se bytes não avançarem neste intervalo (imagens maiores).
const int kStorageUploadImageStallSeconds = 40;

/// Teto alinhado às regras Storage (`storage.rules`) para fotos de feed/perfil/património.
const int kStorageRulesMaxFeedImageBytes = 10 * 1024 * 1024;

/// PDF/comprovante financeiro — regra Storage até 25 MB.
const int kStorageRulesMaxFinanceDocBytes = 25 * 1024 * 1024;

/// Chat vídeo — regra Storage até 200 MB.
const int kStorageRulesMaxChatVideoBytes = 200 * 1024 * 1024;

/// Património — até 4 fotos por bem (móvel, equipamento, veículo, etc.).
const int kMaxPatrimonioPhotosPerItem = 5;

/// Eventos (editor + galeria) — vídeo até 2 min.
const int kMediaEventVideoMaxSeconds = 120;

/// Eventos — teto de 100 MB após compressão (spec produção).
const int kMediaEventVideoHardMaxBytes = 100 * 1024 * 1024;

Duration get mediaEventVideoMaxDurationEffective =>
    Duration(seconds: kMediaEventVideoMaxSeconds);

/// Eventos mobile — rejeita vídeo bruto acima de 10 MB antes de transcodificar (evita timeout em 4G).
const int kMediaEventVideoMobilePickMaxBytes = 10 * 1024 * 1024;

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
    kMediaTurboMobilePreset ? (700 * 1024) : kMediaImagePreferredMaxBytes;

int get mediaVideoHardMaxBytesEffective => kMediaTurboMobilePreset
    ? kMediaEventVideoHardMaxBytes
    : kMediaVideoHardMaxBytes;

int get mediaEventVideoHardMaxBytesEffective => kMediaEventVideoHardMaxBytes;

int get mediaChatVideoHardMaxBytesEffective => kMediaChatVideoHardMaxBytes;

Duration get mediaVideoMaxDurationEffective => kMediaFeedVideoMaxDuration;

/// Bruto aceite **antes** de transcodificar (2 min de 1080p/4K pesa centenas
/// de MB). O teto de 100 MB continua a valer para o ficheiro que sai do encoder.
const int kMediaEventVideoRawMaxBytes = 400 * 1024 * 1024;

/// Teto de tempo para o encode no aparelho; ao estourar, envia o original
/// (se couber) em vez de deixar o utilizador à espera para sempre.
const Duration kMediaVideoTranscodeTimeout = Duration(minutes: 4);

/// Abaixo disto o ficheiro já é leve: enviar o original é mais rápido do que
/// transcodificar. Acima, o encode por hardware (~5–10× tempo real) custa
/// muito menos do que subir o bruto em 4G — era este limiar alto (80/40 MB)
/// que fazia «montar um evento com vídeo» demorar minutos.
int get mediaVideoSkipTranscodeMaxBytes =>
    kMediaTurboMobilePreset ? (10 * 1024 * 1024) : (16 * 1024 * 1024);

/// Uploads em lote (avisos/eventos): paralelo limitado (turbo mobile = mais rápido em Wi‑Fi/4G).
int get mediaFeedUploadMaxConcurrent {
  if (kIsWeb) return 4;
  // 3 no telemóvel: as fotos já saem do picker com ~700 KB, e o vídeo — que era
  // quem disputava a banda — agora sobe antes, enquanto se preenche o formulário.
  return 3;
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

int get mediaPickerLogoQuality => kMediaTurboMobilePreset ? 68 : 70;

int get mediaPickerLogoMaxWidth => kMediaTurboMobilePreset ? 720 : 800;

int get mediaPickerLogoMaxHeight => kMediaTurboMobilePreset ? 720 : 800;
