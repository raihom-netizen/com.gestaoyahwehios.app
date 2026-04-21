import 'dart:typed_data';

import 'package:image/image.dart' as img;

int _clamp255(num v) => v.round().clamp(0, 255);

const String kSignatureEnhanceModeUltra = 'ultra';
const String kSignatureEnhanceModeNormal = 'normal';

String normalizeSignatureEnhanceMode(String raw) {
  final v = raw.trim().toLowerCase();
  return v == kSignatureEnhanceModeNormal
      ? kSignatureEnhanceModeNormal
      : kSignatureEnhanceModeUltra;
}

/// Realça traços da assinatura para o PDF. Só trata como “papel branco” pixéis quase
/// perfeitos (≥253), para não apagar traços a lápis/canetas claras (antes: >246 apagava cinzas).
/// Papel/branco do scan vira transparente para a assinatura «flutuar» no cartão/PDF.
img.Image _knockoutPaperToTransparent(img.Image work) {
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final p = work.getPixel(x, y);
      final a = p.a.toInt();
      if (a < 8) continue;
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      if (lum >= 251 && r >= 246 && g >= 246 && b >= 246) {
        p.set(img.ColorUint8.rgba(255, 255, 255, 0));
      }
    }
  }
  return work;
}

img.Image _enhanceSignatureRgba(img.Image work) {
  return _enhanceSignatureRgbaWithMode(work, kSignatureEnhanceModeUltra);
}

img.Image _enhanceSignatureRgbaWithMode(img.Image work, String modeRaw) {
  final mode = normalizeSignatureEnhanceMode(modeRaw);
  final ultra = mode == kSignatureEnhanceModeUltra;
  final mult = ultra ? 2.08 : 1.90;
  final bias = ultra ? -86.0 : -70.0;
  /// Só papel “puro”; traços claros (lum 220–252) passam a ser escurecidos.
  final paperLumMin = ultra ? 252.0 : 253.0;
  for (var y = 0; y < work.height; y++) {
    for (var x = 0; x < work.width; x++) {
      final p = work.getPixel(x, y);
      final a = p.a.toInt();
      if (a < 10) continue;
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      if (lum >= paperLumMin && a > 240) {
        p.set(img.ColorUint8.rgba(255, 255, 255, a));
        continue;
      }
      // Traços muito claros: curva um pouco mais forte
      final m = lum < (ultra ? 224 : 230) ? mult : (mult * (ultra ? 1.12 : 1.06));
      final bAdj = lum < (ultra ? 224 : 230) ? bias : (bias - (ultra ? 12.0 : 6.0));
      p.set(
        img.ColorUint8.rgba(
          _clamp255(r * m + bAdj),
          _clamp255(g * m + bAdj),
          _clamp255(b * m + bAdj),
          a,
        ),
      );
      // Para tintas muito claras, aumenta um pouco a opacidade do traço.
      if (ultra && lum > 214 && a < 230) {
        final na = _clamp255(a + 16);
        p.set(img.ColorUint8.rgba(p.r.toInt(), p.g.toInt(), p.b.toInt(), na));
      }
    }
  }
  return work;
}

/// Pipeline completo para assinatura no PDF: **bytes originais** (PNG/JPEG) — sem JPEG
/// intermédio a 68% que desfaz traços finos; redimensiona, realça, saída **PNG** (alpha).
Uint8List? carteirinhaPdfSignaturePipelineSync(
  Uint8List raw, {
  String mode = kSignatureEnhanceModeUltra,
}) {
  if (raw.length < 33) return null;
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    var work = decoded.convert(numChannels: 4);
    // Mais definição no PDF (traços finos): mantém assinatura até 1024px no maior lado.
    const maxSide = 1024;
    if (work.width > maxSide || work.height > maxSide) {
      final scale = work.width >= work.height
          ? maxSide / work.width
          : maxSide / work.height;
      final rw = (work.width * scale).round().clamp(1, maxSide);
      final rh = (work.height * scale).round().clamp(1, maxSide);
      work = img.copyResize(
        work,
        width: rw,
        height: rh,
        interpolation: img.Interpolation.cubic,
      );
    }
    var enhanced = _enhanceSignatureRgbaWithMode(work, mode);
    enhanced = _knockoutPaperToTransparent(enhanced);
    return Uint8List.fromList(img.encodePng(enhanced, level: 6));
  } catch (_) {
    return null;
  }
}

/// Entrada/saída não-nula para [compute] (o pacote exige tipo concreto).
Uint8List carteirinhaPdfSignaturePipelineForCompute(Uint8List raw) {
  return carteirinhaPdfSignaturePipelineSync(raw) ?? raw;
}

/// Variante "normal" (mais suave), para escolher via painel sem editar código.
Uint8List carteirinhaPdfSignaturePipelineNormalForCompute(Uint8List raw) {
  return carteirinhaPdfSignaturePipelineSync(
        raw,
        mode: kSignatureEnhanceModeNormal,
      ) ??
      raw;
}

/// Escurece traços claros da assinatura (equivalente ao contraste da app).
/// Destinado a bytes **já** processados (legado); preferir [carteirinhaPdfSignaturePipelineSync].
///
/// Top-level para uso com [compute] fora da UI.
Uint8List? carteirinhaPdfEnhanceSignatureBytesSync(Uint8List bytes) {
  if (bytes.length < 33) return null;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var work = _enhanceSignatureRgba(decoded.convert(numChannels: 4));
    work = _knockoutPaperToTransparent(work);
    if (work.hasAlpha) {
      return Uint8List.fromList(img.encodePng(work, level: 6));
    }
    return Uint8List.fromList(img.encodeJpg(work, quality: 88));
  } catch (_) {
    return null;
  }
}

/// Entrada/saída não-nula para [compute] (o pacote exige tipo concreto).
Uint8List carteirinhaPdfEnhanceSignatureForCompute(Uint8List bytes) {
  return carteirinhaPdfEnhanceSignatureBytesSync(bytes) ?? bytes;
}
