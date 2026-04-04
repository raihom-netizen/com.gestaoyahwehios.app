// Gera ícone 512x512 (RGBA, fundo transparente) e recurso gráfico 1024x500 na Play Store.
// Executar na pasta flutter_app: dart run tool/generate_play_store_graphics.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const _outDir = r'D:\temporarios';
const _srcRelative = 'assets/icon/app_icon.png';

void main() {
  final root = Directory.current.path;
  final srcPath = '$root${Platform.pathSeparator}$_srcRelative';
  final srcFile = File(srcPath);
  if (!srcFile.existsSync()) {
    stderr.writeln('Ficheiro não encontrado: $srcPath');
    stderr.writeln('Execute a partir de flutter_app (ex.: cd flutter_app && dart run tool/generate_play_store_graphics.dart)');
    exitCode = 1;
    return;
  }

  Directory(_outDir).createSync(recursive: true);

  final raw = srcFile.readAsBytesSync();
  final source = img.decodeImage(raw);
  if (source == null) {
    stderr.writeln('Falha ao decodificar PNG.');
    exitCode = 1;
    return;
  }

  _writePlayIcon512(source);
  _writeFeatureGraphic1024x500(source);

  stdout.writeln('Ficheiros gerados em $_outDir :');
  stdout.writeln('  gestao_yahweh_play_icon_512_sem_fundo.png');
  stdout.writeln('  gestao_yahweh_feature_graphic_1024x500.png');
}

void _writePlayIcon512(img.Image source) {
  const s = 512;
  final scale = math.min(s / source.width, s / source.height);
  final nw = math.max(1, (source.width * scale).round());
  final nh = math.max(1, (source.height * scale).round());
  final resized = img.copyResize(source, width: nw, height: nh, interpolation: img.Interpolation.linear);

  final canvas = img.Image(width: s, height: s, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final ox = (s - nw) ~/ 2;
  final oy = (s - nh) ~/ 2;
  img.compositeImage(canvas, resized, dstX: ox, dstY: oy);

  final out = File('$_outDir${Platform.pathSeparator}gestao_yahweh_play_icon_512_sem_fundo.png');
  out.writeAsBytesSync(img.encodePng(canvas, level: 6));
}

void _writeFeatureGraphic1024x500(img.Image source) {
  const w = 1024;
  const h = 500;
  final fg = img.Image(width: w, height: h, numChannels: 4);
  for (var y = 0; y < h; y++) {
    final t = y / (h - 1);
    final r = (12 + (224 - 12) * t).round().clamp(0, 255);
    final g = (59 + (242 - 59) * t).round().clamp(0, 255);
    final b = (138 + (254 - 138) * t).round().clamp(0, 255);
    for (var x = 0; x < w; x++) {
      fg.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  final maxH = (h * 0.72).round();
  final scale = maxH / source.height;
  final lw = math.max(1, (source.width * scale).round());
  final lh = math.max(1, (source.height * scale).round());
  final logo = img.copyResize(source, width: lw, height: lh, interpolation: img.Interpolation.linear);
  final lx = (w - lw) ~/ 2;
  final ly = (h - lh) ~/ 2;
  img.compositeImage(fg, logo, dstX: lx, dstY: ly);

  final out = File('$_outDir${Platform.pathSeparator}gestao_yahweh_feature_graphic_1024x500.png');
  out.writeAsBytesSync(img.encodePng(fg, level: 6));
}
