import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart'
    show TargetPlatform, compute, defaultTargetPlatform, kIsWeb;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'package:gestao_yahweh/services/smart_input_image_ocr_service.dart';

/// Região normalizada (0–1) para borrar ou destacar na foto.
class UtilPhotoEditRegion {
  const UtilPhotoEditRegion({
    required this.id,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
    this.label = '',
    this.kind = 'manual',
  });

  final String id;
  final double nx;
  final double ny;
  final double nw;
  final double nh;
  final String label;
  final String kind; // manual | face | plate

  UtilPhotoEditRegion copyWith({
    double? nx,
    double? ny,
    double? nw,
    double? nh,
    String? label,
  }) {
    return UtilPhotoEditRegion(
      id: id,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      nw: nw ?? this.nw,
      nh: nh ?? this.nh,
      label: label ?? this.label,
      kind: kind,
    );
  }
}

/// Célula normalizada de um layout de colagem.
class UtilPhotoCollageCell {
  const UtilPhotoCollageCell(this.x, this.y, this.w, this.h);

  final double x;
  final double y;
  final double w;
  final double h;
}

/// Modelo de colagem moderna (slots + proporção do canvas).
class UtilPhotoCollageTemplate {
  const UtilPhotoCollageTemplate({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.slots,
    required this.aspect,
    required this.cells,
  });

  final String id;
  final String label;
  final String subtitle;
  final int slots;
  final double aspect;
  final List<UtilPhotoCollageCell> cells;
}

/// Resultado da leitura de placa (OCR local).
class UtilPhotoPlateReadResult {
  const UtilPhotoPlateReadResult({
    required this.plates,
    required this.enhancedPreview,
  });

  final List<String> plates;
  final Uint8List enhancedPreview;
}

/// Estilo de borragem nas regiões marcadas.
enum UtilPhotoBlurMode {
  gaussian('Borrão', 'Desfoque suave'),
  pixelate('Quadriculado', 'Pixels visíveis');

  const UtilPhotoBlurMode(this.label, this.subtitle);
  final String label;
  final String subtitle;
}

/// Alvo de melhoria de resolução.
enum UtilPhotoEnhanceTarget {
  fullHd('Full HD', 1920),
  fourK('4K Ultra HD', 3840);

  const UtilPhotoEnhanceTarget(this.label, this.longEdge);
  final String label;
  final int longEdge;
}

abstract final class UtilitariosPhotoService {
  UtilitariosPhotoService._();

  static bool get mlKitFaceSupported {
    if (kIsWeb) return false;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return true;
      default:
        return false;
    }
  }

  static final RegExp _plateRe = RegExp(
    r'[A-Z]{3}[-\s]?\d[A-Z0-9]\d{2}',
    caseSensitive: false,
  );

  static final RegExp _plateLegacyRe = RegExp(
    r'[A-Z]{3}[-\s]?\d{4}',
    caseSensitive: false,
  );

  /// Layouts de colagem disponíveis no editor.
  static const List<UtilPhotoCollageTemplate> collageTemplates = [
    UtilPhotoCollageTemplate(
      id: 'duo_h',
      label: 'Lado a lado',
      subtitle: '2 fotos · paisagem',
      slots: 2,
      aspect: 4 / 3,
      cells: [
        UtilPhotoCollageCell(0, 0, 0.5, 1),
        UtilPhotoCollageCell(0.5, 0, 0.5, 1),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'duo_v',
      label: 'Empilhadas',
      subtitle: '2 fotos · retrato',
      slots: 2,
      aspect: 3 / 4,
      cells: [
        UtilPhotoCollageCell(0, 0, 1, 0.5),
        UtilPhotoCollageCell(0, 0.5, 1, 0.5),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'triptych',
      label: 'Tríptico',
      subtitle: '3 colunas',
      slots: 3,
      aspect: 16 / 9,
      cells: [
        UtilPhotoCollageCell(0, 0, 0.333, 1),
        UtilPhotoCollageCell(0.333, 0, 0.334, 1),
        UtilPhotoCollageCell(0.667, 0, 0.333, 1),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'grid4',
      label: 'Grid 2×2',
      subtitle: '4 fotos · quadrado',
      slots: 4,
      aspect: 1,
      cells: [
        UtilPhotoCollageCell(0, 0, 0.5, 0.5),
        UtilPhotoCollageCell(0.5, 0, 0.5, 0.5),
        UtilPhotoCollageCell(0, 0.5, 0.5, 0.5),
        UtilPhotoCollageCell(0.5, 0.5, 0.5, 0.5),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'grid6',
      label: 'Grid 2×3',
      subtitle: '6 fotos',
      slots: 6,
      aspect: 3 / 4,
      cells: [
        UtilPhotoCollageCell(0, 0, 0.5, 0.333),
        UtilPhotoCollageCell(0.5, 0, 0.5, 0.333),
        UtilPhotoCollageCell(0, 0.333, 0.5, 0.334),
        UtilPhotoCollageCell(0.5, 0.333, 0.5, 0.334),
        UtilPhotoCollageCell(0, 0.667, 0.5, 0.333),
        UtilPhotoCollageCell(0.5, 0.667, 0.5, 0.333),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'feature3',
      label: 'Destaque + 2',
      subtitle: '1 grande · 2 pequenas',
      slots: 3,
      aspect: 4 / 5,
      cells: [
        UtilPhotoCollageCell(0, 0, 1, 0.62),
        UtilPhotoCollageCell(0, 0.62, 0.5, 0.38),
        UtilPhotoCollageCell(0.5, 0.62, 0.5, 0.38),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'feature_side',
      label: 'Mosaico lateral',
      subtitle: '1 grande · 2 laterais',
      slots: 3,
      aspect: 4 / 5,
      cells: [
        UtilPhotoCollageCell(0, 0, 0.58, 1),
        UtilPhotoCollageCell(0.58, 0, 0.42, 0.5),
        UtilPhotoCollageCell(0.58, 0.5, 0.42, 0.5),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'story',
      label: 'Story 9:16',
      subtitle: '2 faixas verticais',
      slots: 2,
      aspect: 9 / 16,
      cells: [
        UtilPhotoCollageCell(0, 0, 0.49, 1),
        UtilPhotoCollageCell(0.51, 0, 0.49, 1),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'film4',
      label: 'Filme 4 faixas',
      subtitle: '4 horizontais',
      slots: 4,
      aspect: 16 / 9,
      cells: [
        UtilPhotoCollageCell(0, 0, 1, 0.25),
        UtilPhotoCollageCell(0, 0.25, 1, 0.25),
        UtilPhotoCollageCell(0, 0.5, 1, 0.25),
        UtilPhotoCollageCell(0, 0.75, 1, 0.25),
      ],
    ),
    UtilPhotoCollageTemplate(
      id: 'polaroid2',
      label: 'Polaroid dupla',
      subtitle: '2 com margem branca',
      slots: 2,
      aspect: 1,
      cells: [
        UtilPhotoCollageCell(0.06, 0.08, 0.4, 0.72),
        UtilPhotoCollageCell(0.54, 0.08, 0.4, 0.72),
      ],
    ),
  ];

  /// Melhora luz, contraste e nitidez — upscale até Full HD ou 4K.
  static Future<Uint8List> enhanceQuality(
    Uint8List raw, {
    UtilPhotoEnhanceTarget target = UtilPhotoEnhanceTarget.fullHd,
  }) {
    return compute(
      _enhanceQualityFromRawIsolate,
      _EnhanceArgs(raw: raw, targetLongEdge: target.longEdge),
    );
  }

  /// Recorta área normalizada da imagem.
  static Future<Uint8List> cropImage(
    Uint8List raw, {
    required double nx,
    required double ny,
    required double nw,
    required double nh,
  }) {
    return compute(
      _cropImageIsolate,
      _CropArgs(raw: raw, nx: nx, ny: ny, nw: nw, nh: nh),
    );
  }

  /// Gira 90° no sentido horário.
  static Future<Uint8List> rotateClockwise(Uint8List raw) {
    return compute(_rotateClockwiseIsolate, raw);
  }

  /// Espelha horizontalmente.
  static Future<Uint8List> flipHorizontal(Uint8List raw) {
    return compute(_flipHorizontalIsolate, raw);
  }

  /// Redimensiona foto grande uma vez (editor/colagem mais rápido).
  static Future<Uint8List> preparePhotoForEditor(Uint8List raw) {
    return compute(_preparePhotoForEditorIsolate, raw);
  }

  /// Aspecto largura/altura sem bloquear a UI.
  static Future<double> photoAspectRatio(Uint8List raw) {
    return compute(_photoAspectRatioIsolate, raw);
  }

  /// Monta colagem com várias fotos (alta qualidade na exportação).
  static Future<Uint8List> buildCollage({
    required List<Uint8List> photos,
    required UtilPhotoCollageTemplate template,
    int gap = 12,
    bool darkBackground = false,
  }) {
    return compute(
      _buildCollageIsolate,
      _CollageArgs(
        photos: photos,
        template: template,
        gap: gap,
        darkBackground: darkBackground,
      ),
    );
  }

  /// Aplica borragem (gaussiano ou quadriculado) nas regiões marcadas.
  static Future<Uint8List> applyBlurRegions(
    Uint8List raw,
    List<UtilPhotoEditRegion> regions, {
    int blurRadius = 14,
    UtilPhotoBlurMode mode = UtilPhotoBlurMode.gaussian,
  }) {
    return compute(
      _blurRegionsIsolate,
      _BlurRegionsArgs(
        raw: raw,
        regions: regions,
        blurRadius: blurRadius,
        modeIndex: mode.index,
      ),
    );
  }

  /// Detecta rostos (Android/iOS) para borrar.
  static Future<List<UtilPhotoEditRegion>> detectFaces(Uint8List jpeg) async {
    if (!mlKitFaceSupported) return const [];
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) return const [];

    final tmp = await _writeTempJpeg(jpeg);
    FaceDetector? detector;
    try {
      detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          minFaceSize: 0.12,
        ),
      );
      final faces = await detector.processImage(
        InputImage.fromFilePath(tmp.path),
      );
      final w = decoded.width.toDouble();
      final h = decoded.height.toDouble();
      final out = <UtilPhotoEditRegion>[];
      var i = 0;
      for (final face in faces) {
        final box = face.boundingBox;
        if (box.width <= 0 || box.height <= 0) continue;
        const pad = 0.08;
        final nx = ((box.left / w) - pad).clamp(0.0, 1.0);
        final ny = ((box.top / h) - pad).clamp(0.0, 1.0);
        final nw = ((box.width / w) + pad * 2).clamp(0.05, 1.0 - nx);
        final nh = ((box.height / h) + pad * 2).clamp(0.05, 1.0 - ny);
        out.add(
          UtilPhotoEditRegion(
            id: 'face_$i',
            nx: nx,
            ny: ny,
            nw: nw,
            nh: nh,
            label: 'Rosto',
            kind: 'face',
          ),
        );
        i++;
      }
      return out;
    } catch (_) {
      return const [];
    } finally {
      try {
        await detector?.close();
      } catch (_) {}
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// Detecta placas de veículo via OCR (linhas com padrão BR).
  static Future<List<UtilPhotoEditRegion>> detectPlates(Uint8List jpeg) async {
    if (kIsWeb || !SmartInputImageOcrService.mlKitTextRecognitionSupported) {
      return const [];
    }
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) return const [];

    final hits = await _ocrPlateHitsMultiPass(jpeg);
    if (hits.isEmpty) return const [];

    final w = decoded.width.toDouble();
    final h = decoded.height.toDouble();
    final out = <UtilPhotoEditRegion>[];
    var i = 0;
    for (final hit in hits) {
      final box = hit.box;
      if (box.width <= 0 || box.height <= 0) continue;
      const padX = 0.06;
      const padY = 0.10;
      final nx = ((box.left / w) - padX).clamp(0.0, 1.0);
      final ny = ((box.top / h) - padY).clamp(0.0, 1.0);
      final nw = ((box.width / w) + padX * 2).clamp(0.10, 1.0 - nx);
      final nh = ((box.height / h) + padY * 2).clamp(0.06, 1.0 - ny);
      out.add(
        UtilPhotoEditRegion(
          id: 'plate_$i',
          nx: nx,
          ny: ny,
          nw: nw,
          nh: nh,
          label: hit.plate,
          kind: 'plate',
        ),
      );
      i++;
    }
    return out;
  }

  /// Melhora a foto e tenta ler placas (mesmo em imagem ruim).
  static Future<UtilPhotoPlateReadResult> enhanceAndReadPlates(
    Uint8List raw,
  ) async {
    final enhanced = await enhanceQuality(
      raw,
      target: UtilPhotoEnhanceTarget.fourK,
    );
    final plates = <String>{};
    if (!kIsWeb && SmartInputImageOcrService.mlKitTextRecognitionSupported) {
      final fromRaw = await _ocrPlatesFromBytes(raw);
      final fromEnhanced = await _ocrPlatesFromBytes(enhanced);
      plates.addAll(fromRaw);
      plates.addAll(fromEnhanced);
    }
    return UtilPhotoPlateReadResult(
      plates: plates.toList(),
      enhancedPreview: enhanced,
    );
  }

  static String? _normalizePlateCandidate(String raw) {
    final compact = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (compact.length < 7) return null;
    for (var i = 0; i <= compact.length - 7; i++) {
      final slice = compact.substring(i, i + 7);
      if (_plateRe.hasMatch(slice) || _plateLegacyRe.hasMatch(slice)) {
        return _formatPlate(slice);
      }
    }
    final m = _plateRe.firstMatch(compact) ?? _plateLegacyRe.firstMatch(compact);
    return m == null ? null : _formatPlate(m.group(0)!);
  }

  static String _formatPlate(String raw) {
    final t = raw.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    if (t.length != 7) return t;
    return '${t.substring(0, 3)}-${t.substring(3)}';
  }

  static Future<Set<String>> _ocrPlatesFromBytes(Uint8List jpeg) async {
    final hits = await _ocrPlateHitsMultiPass(jpeg);
    return hits.map((h) => h.plate).toSet();
  }

  static Future<List<({String plate, Rect box})>> _ocrPlateHitsMultiPass(
    Uint8List jpeg,
  ) async {
    final passes = <Uint8List>[
      jpeg,
      await compute(_plateOcrPrepContrast, jpeg),
      await compute(_plateOcrPrepUpscale, jpeg),
    ];
    final found = <String, Rect>{};
    for (final pass in passes) {
      final tmp = await _writeTempJpeg(pass);
      TextRecognizer? rec;
      try {
        rec = TextRecognizer(script: TextRecognitionScript.latin);
        final recognized = await rec.processImage(
          InputImage.fromFilePath(tmp.path),
        );
        for (final block in recognized.blocks) {
          for (final line in block.lines) {
            final plate = _normalizePlateCandidate(line.text);
            if (plate == null) continue;
            final box = line.boundingBox;
            if (box.width <= 0 || box.height <= 0) continue;
            found.putIfAbsent(plate, () => box);
          }
          for (final element in block.lines.expand((l) => l.elements)) {
            final plate = _normalizePlateCandidate(element.text);
            if (plate == null) continue;
            final box = element.boundingBox;
            if (box.width <= 0 || box.height <= 0) continue;
            found.putIfAbsent(plate, () => box);
          }
        }
      } catch (_) {
      } finally {
        try {
          await rec?.close();
        } catch (_) {}
        try {
          if (await tmp.exists()) await tmp.delete();
        } catch (_) {}
      }
    }
    return found.entries.map((e) => (plate: e.key, box: e.value)).toList();
  }

  static Future<File> _writeTempJpeg(Uint8List jpeg) async {
    final dir = await getTemporaryDirectory();
    final f = File(
      '${dir.path}/ct_photo_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await f.writeAsBytes(jpeg, flush: true);
    return f;
  }
}

class _EnhanceArgs {
  const _EnhanceArgs({required this.raw, required this.targetLongEdge});
  final Uint8List raw;
  final int targetLongEdge;
}

class _CropArgs {
  const _CropArgs({
    required this.raw,
    required this.nx,
    required this.ny,
    required this.nw,
    required this.nh,
  });
  final Uint8List raw;
  final double nx;
  final double ny;
  final double nw;
  final double nh;
}

class _CollageArgs {
  const _CollageArgs({
    required this.photos,
    required this.template,
    required this.gap,
    required this.darkBackground,
  });
  final List<Uint8List> photos;
  final UtilPhotoCollageTemplate template;
  final int gap;
  final bool darkBackground;
}

class _BlurRegionsArgs {
  const _BlurRegionsArgs({
    required this.raw,
    required this.regions,
    required this.blurRadius,
    required this.modeIndex,
  });
  final Uint8List raw;
  final List<UtilPhotoEditRegion> regions;
  final int blurRadius;
  final int modeIndex;
}

Uint8List _cropImageIsolate(_CropArgs a) {
  final decoded = img.decodeImage(a.raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  final x = (a.nx * decoded.width).round().clamp(0, decoded.width - 1);
  final y = (a.ny * decoded.height).round().clamp(0, decoded.height - 1);
  final w = (a.nw * decoded.width).round().clamp(1, decoded.width - x);
  final h = (a.nh * decoded.height).round().clamp(1, decoded.height - y);
  final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 92));
}

Uint8List _rotateClockwiseIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  final rotated = img.copyRotate(decoded, angle: 90);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
}

Uint8List _flipHorizontalIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  final flipped = img.flipHorizontal(decoded);
  return Uint8List.fromList(img.encodeJpg(flipped, quality: 92));
}

Uint8List _buildCollageIsolate(_CollageArgs a) {
  if (a.photos.isEmpty) throw StateError('Adicione fotos à colagem.');
  final decoded = <img.Image>[];
  for (final p in a.photos) {
    final d = img.decodeImage(p);
    if (d == null) throw StateError('Uma das fotos é inválida.');
    decoded.add(d);
  }
  final count = math.min(decoded.length, a.template.cells.length);
  const canvasW = 1600;
  final canvasH = (canvasW / a.template.aspect).round().clamp(480, 3200);
  final bg = a.darkBackground
      ? img.ColorRgb8(18, 18, 22)
      : img.ColorRgb8(255, 255, 255);
  final canvas = img.Image(width: canvasW, height: canvasH);
  img.fill(canvas, color: bg);

  final gap = a.gap.clamp(0, 48);
  final halfGap = gap / 2.0;

  for (var i = 0; i < count; i++) {
    final cell = a.template.cells[i];
    final left = cell.x * canvasW + halfGap;
    final top = cell.y * canvasH + halfGap;
    final right = (cell.x + cell.w) * canvasW - halfGap;
    final bottom = (cell.y + cell.h) * canvasH - halfGap;
    final dstW = (right - left).round().clamp(8, canvasW);
    final dstH = (bottom - top).round().clamp(8, canvasH);
    final dstX = left.round().clamp(0, canvasW - dstW);
    final dstY = top.round().clamp(0, canvasH - dstH);
    _pasteCover(canvas, decoded[i], dstX, dstY, dstW, dstH);
  }

  if (a.template.id == 'polaroid2') {
    _drawPolaroidFrames(canvas);
  }

  return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
}

double _photoAspectRatioIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return 1.0;
  return decoded.width / math.max(1, decoded.height);
}

Uint8List _preparePhotoForEditorIsolate(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  var work = decoded;
  if (work.numChannels == 4) {
    final flat = img.Image(width: work.width, height: work.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, work);
    work = flat;
  }
  const maxDim = 1920;
  final md = math.max(work.width, work.height);
  if (md > maxDim) {
    final scale = maxDim / md;
    work = img.copyResize(
      work,
      width: (work.width * scale).round(),
      height: (work.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(img.encodeJpg(work, quality: 86));
}

void _pasteCover(
  img.Image canvas,
  img.Image photo,
  int dstX,
  int dstY,
  int dstW,
  int dstH,
) {
  final scale = math.max(dstW / photo.width, dstH / photo.height);
  final sw = (photo.width * scale).round().clamp(dstW, 8000);
  final sh = (photo.height * scale).round().clamp(dstH, 8000);
  final resized = img.copyResize(
    photo,
    width: sw,
    height: sh,
    interpolation: img.Interpolation.linear,
  );
  final cx = ((sw - dstW) / 2).round().clamp(0, sw - dstW);
  final cy = ((sh - dstH) / 2).round().clamp(0, sh - dstH);
  final cropped = img.copyCrop(
    resized,
    x: cx,
    y: cy,
    width: dstW,
    height: dstH,
  );
  img.compositeImage(canvas, cropped, dstX: dstX, dstY: dstY);
}

void _drawPolaroidFrames(img.Image canvas) {
  final w = canvas.width;
  final h = canvas.height;
  final frameColor = img.ColorRgb8(245, 245, 245);
  final shadow = img.ColorRgba8(0, 0, 0, 28);
  for (final rect in [
    (x: (0.04 * w).round(), y: (0.04 * h).round(), fw: (0.42 * w).round(), fh: (0.88 * h).round()),
    (x: (0.52 * w).round(), y: (0.04 * h).round(), fw: (0.42 * w).round(), fh: (0.88 * h).round()),
  ]) {
    for (var dy = -2; dy <= rect.fh + 2; dy++) {
      for (var dx = -2; dx <= rect.fw + 2; dx++) {
        final px = rect.x + dx;
        final py = rect.y + dy;
        if (px < 0 || py < 0 || px >= w || py >= h) continue;
        if (dx < 0 || dy < 0 || dx > rect.fw || dy > rect.fh) {
          canvas.setPixel(px, py, shadow);
        }
      }
    }
    for (var dy = 0; dy < rect.fh; dy++) {
      for (var dx = 0; dx < rect.fw; dx++) {
        final px = rect.x + dx;
        final py = rect.y + dy;
        if (px < 0 || py < 0 || px >= w || py >= h) continue;
        if (dy > (rect.fh * 0.78).round()) {
          canvas.setPixel(px, py, frameColor);
        }
      }
    }
  }
}

Uint8List _enhanceQualityFromRawIsolate(_EnhanceArgs args) {
  final raw = args.raw;
  final targetLongEdge = args.targetLongEdge;
  final decoded = img.decodeImage(raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  var work = decoded;
  if (work.numChannels == 4) {
    final flat = img.Image(width: work.width, height: work.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, work);
    work = flat;
  }

  final stats = _photoAnalyzeStats(work);
  final maxDim = work.width > work.height ? work.width : work.height;

  // Upscale até Full HD (1920) ou 4K (3840) conforme alvo.
  if (maxDim < targetLongEdge) {
    final scale = (targetLongEdge / maxDim).clamp(1.0, 4.0);
    if (scale > 1.02) {
      work = img.copyResize(
        work,
        width: (work.width * scale).round(),
        height: (work.height * scale).round(),
        interpolation: img.Interpolation.cubic,
      );
    }
  }

  // Leve auto-níveis (estica histograma sem estourar brancos/pretos).
  work = _photoAutoLevelsMild(work);

  // Correção adaptativa de luz e cor — uma passagem suave.
  final brightness = stats.avgLuminance < 92
      ? 1.0 + ((92 - stats.avgLuminance) / 255 * 0.18).clamp(0.0, 0.10)
      : stats.avgLuminance > 198
          ? 1.0 - ((stats.avgLuminance - 198) / 255 * 0.12).clamp(0.0, 0.08)
          : 1.0;
  final contrast = stats.luminanceSpread < 42
      ? 1.0 + ((42 - stats.luminanceSpread) / 42 * 0.06).clamp(0.0, 0.06)
      : 1.02;
  final saturation = stats.avgSaturation < 28
      ? 1.04
      : stats.avgSaturation > 72
          ? 0.98
          : 1.02;
  final gamma = stats.avgLuminance < 105 ? 0.97 : 1.0;

  work = img.adjustColor(
    work,
    contrast: contrast,
    saturation: saturation,
    brightness: brightness,
    gamma: gamma,
  );

  // Ruído leve antes da nitidez (prints comprimidos / CFTV).
  work = _photoDenoiseMild(work, mix: 0.14);

  // Nitidez tipo «clareza» profissional — bem mais suave que antes.
  final sharpenDim = math.max(work.width, work.height);
  final sharpen = sharpenDim > 1600 ? 0.14 : 0.20;
  work = _photoSharpen(work, strength: sharpen);

  if (stats.avgSaturation < 40 && stats.avgLuminance > 70) {
    work = _photoVibranceMild(work, boost: 1.03);
  }

  return Uint8List.fromList(img.encodeJpg(work, quality: 94));
}

class _PhotoImageStats {
  const _PhotoImageStats({
    required this.avgLuminance,
    required this.avgSaturation,
    required this.luminanceSpread,
  });

  final double avgLuminance;
  final double avgSaturation;
  final double luminanceSpread;
}

_PhotoImageStats _photoAnalyzeStats(img.Image src) {
  final step = math.max(
    1,
    (src.width * src.height / 140000).round(),
  );
  var sumL = 0.0;
  var sumL2 = 0.0;
  var sumSat = 0.0;
  var n = 0;
  for (var y = 0; y < src.height; y += step) {
    for (var x = 0; x < src.width; x += step) {
      final p = src.getPixel(x, y);
      final l = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      sumL += l;
      sumL2 += l * l;
      final maxC = math.max(p.r, math.max(p.g, p.b)).toDouble();
      final minC = math.min(p.r, math.min(p.g, p.b)).toDouble();
      sumSat += maxC - minC;
      n++;
    }
  }
  if (n == 0) {
    return const _PhotoImageStats(
      avgLuminance: 128,
      avgSaturation: 40,
      luminanceSpread: 50,
    );
  }
  final avgL = sumL / n;
  final variance = (sumL2 / n) - (avgL * avgL);
  return _PhotoImageStats(
    avgLuminance: avgL,
    avgSaturation: sumSat / n,
    luminanceSpread: math.sqrt(variance.clamp(0.0, double.infinity)),
  );
}

img.Image _photoAutoLevelsMild(img.Image src) {
  final hist = List<int>.filled(256, 0);
  final step = math.max(1, (src.width * src.height / 160000).round());
  var samples = 0;
  for (var y = 0; y < src.height; y += step) {
    for (var x = 0; x < src.width; x += step) {
      final p = src.getPixel(x, y);
      final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      hist[l]++;
      samples++;
    }
  }
  if (samples < 32) return src;

  final clip = (samples * 0.018).round().clamp(8, samples ~/ 8);
  var low = 0;
  var acc = 0;
  while (low < 255 && acc < clip) {
    acc += hist[low];
    low++;
  }
  var high = 255;
  acc = 0;
  while (high > low && acc < clip) {
    acc += hist[high];
    high--;
  }
  if (high - low < 48) return src;

  final scale = 235.0 / (high - low);
  final out = img.Image.from(src);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      p.r = ((p.r - low) * scale).round().clamp(0, 255);
      p.g = ((p.g - low) * scale).round().clamp(0, 255);
      p.b = ((p.b - low) * scale).round().clamp(0, 255);
      out.setPixel(x, y, p);
    }
  }
  return out;
}

Uint8List _blurRegionsIsolate(_BlurRegionsArgs a) {
  final decoded = img.decodeImage(a.raw);
  if (decoded == null) throw StateError('Imagem inválida.');
  var work = img.Image.from(decoded);
  final radius = a.blurRadius.clamp(4, 40);
  final pixelate = a.modeIndex == UtilPhotoBlurMode.pixelate.index;
  for (final r in a.regions) {
    final x = (r.nx * work.width).round().clamp(0, work.width - 1);
    final y = (r.ny * work.height).round().clamp(0, work.height - 1);
    final w = (r.nw * work.width).round().clamp(4, work.width - x);
    final h = (r.nh * work.height).round().clamp(4, work.height - y);
    final crop = img.copyCrop(work, x: x, y: y, width: w, height: h);
    final processed = pixelate
        ? _pixelateRegion(crop, blockSize: (radius ~/ 2).clamp(6, 48))
        : img.gaussianBlur(crop, radius: radius);
    img.compositeImage(work, processed, dstX: x, dstY: y);
  }
  return Uint8List.fromList(img.encodeJpg(work, quality: 90));
}

img.Image _pixelateRegion(img.Image src, {required int blockSize}) {
  final block = blockSize.clamp(4, 64);
  final out = img.Image.from(src);
  for (var y = 0; y < src.height; y += block) {
    for (var x = 0; x < src.width; x += block) {
      var rSum = 0, gSum = 0, bSum = 0, n = 0;
      final yEnd = math.min(y + block, src.height);
      final xEnd = math.min(x + block, src.width);
      for (var py = y; py < yEnd; py++) {
        for (var px = x; px < xEnd; px++) {
          final p = src.getPixel(px, py);
          rSum += p.r.toInt();
          gSum += p.g.toInt();
          bSum += p.b.toInt();
          n++;
        }
      }
      if (n == 0) continue;
      final color = img.ColorRgb8(
        (rSum / n).round(),
        (gSum / n).round(),
        (bSum / n).round(),
      );
      for (var py = y; py < yEnd; py++) {
        for (var px = x; px < xEnd; px++) {
          out.setPixel(px, py, color);
        }
      }
    }
  }
  return out;
}

Uint8List _plateOcrPrepContrast(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  var work = img.grayscale(decoded);
  work = img.adjustColor(work, contrast: 1.35, brightness: 1.08, gamma: 0.92);
  work = _photoSharpen(work, strength: 0.28);
  return Uint8List.fromList(img.encodeJpg(work, quality: 92));
}

Uint8List _plateOcrPrepUpscale(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  final maxDim = math.max(decoded.width, decoded.height);
  if (maxDim >= 1600) return raw;
  final scale = (2000 / maxDim).clamp(1.0, 3.0);
  final work = img.copyResize(
    decoded,
    width: (decoded.width * scale).round(),
    height: (decoded.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
  return Uint8List.fromList(img.encodeJpg(work, quality: 92));
}

img.Image _photoSharpen(img.Image src, {double strength = 0.4}) {
  final s = strength.clamp(0.0, 1.0);
  if (s <= 0.01) return src;
  final k = 0.5 * s;
  final c = 1.0 + (2.0 * s);
  return img.convolution(
    src,
    filter: [
      0, -k, 0,
      -k, c, -k,
      0, -k, 0,
    ],
  );
}

img.Image _photoDenoiseMild(img.Image src, {double mix = 0.22}) {
  final blurred = img.gaussianBlur(src, radius: 1);
  final out = img.Image.from(src);
  final m = mix.clamp(0.0, 0.5);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final o = src.getPixel(x, y);
      final b = blurred.getPixel(x, y);
      final l = 0.299 * o.r + 0.587 * o.g + 0.114 * o.b;
      if (l > 40 && l < 220) {
        o.r = (o.r * (1 - m) + b.r * m).round().clamp(0, 255);
        o.g = (o.g * (1 - m) + b.g * m).round().clamp(0, 255);
        o.b = (o.b * (1 - m) + b.b * m).round().clamp(0, 255);
        out.setPixel(x, y, o);
      }
    }
  }
  return out;
}

img.Image _photoVibranceMild(img.Image src, {double boost = 1.06}) {
  final out = img.Image.from(src);
  final b = boost.clamp(1.0, 1.12);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final maxC = math.max(p.r, math.max(p.g, p.b));
      final minC = math.min(p.r, math.min(p.g, p.b));
      final sat = maxC - minC;
      if (sat < 18) continue;
      final avg = (p.r + p.g + p.b) / 3.0;
      p.r = (avg + (p.r - avg) * b).round().clamp(0, 255);
      p.g = (avg + (p.g - avg) * b).round().clamp(0, 255);
      p.b = (avg + (p.b - avg) * b).round().clamp(0, 255);
      out.setPixel(x, y, p);
    }
  }
  return out;
}
