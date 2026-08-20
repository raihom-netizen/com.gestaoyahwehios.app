import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Logo institucional já pronta para o Storage.
class ChurchLogoEncoded {
  const ChurchLogoEncoded({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  bool get isPng => mimeType == 'image/png';
}

/// Argumento único para [compute] (encode fora da isolate principal).
class ChurchLogoPngEncodeArgs {
  final Uint8List raw;
  final int maxSide;
  const ChurchLogoPngEncodeArgs(this.raw, this.maxSide);
}

/// `true` quando algum pixel não é totalmente opaco.
///
/// Decide o formato: PNG só faz sentido quando há transparência a preservar.
/// Para uma logo achatada em fundo branco (a maioria), o PNG é várias vezes
/// maior e muito mais lento de codificar do que um JPEG de alta qualidade.
bool _temTransparencia(img.Image im) {
  if (im.numChannels < 4) return false;
  for (final p in im) {
    if (p.a < 250) return true;
  }
  return false;
}

/// Prepara a logo para upload num **único** passe: decode → resize → encode.
///
/// Antes o fluxo do cadastro fazia três: comprimia para JPEG, voltava a
/// comprimir para caber em 800 KB e só depois recodificava em PNG. Ou seja,
/// três decodes e três encodes, a transparência perdida logo no primeiro passo
/// e um PNG final maior do que o JPEG que lhe deu origem — lento e com pior
/// qualidade ao mesmo tempo.
///
/// [maxSide] é o maior lado do resultado (1920 = Full HD).
ChurchLogoEncoded encodeChurchLogoSync(Uint8List raw, {int maxSide = 1920}) {
  if (raw.isEmpty) {
    return ChurchLogoEncoded(
      bytes: raw,
      mimeType: 'image/png',
      width: 0,
      height: 0,
    );
  }
  try {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      return ChurchLogoEncoded(
        bytes: raw,
        mimeType: 'image/png',
        width: 0,
        height: 0,
      );
    }
    final w = decoded.width;
    final h = decoded.height;
    if (w <= 0 || h <= 0) {
      return ChurchLogoEncoded(
        bytes: raw,
        mimeType: 'image/png',
        width: 0,
        height: 0,
      );
    }

    img.Image out = decoded;
    if (w > maxSide || h > maxSide) {
      final scale = maxSide / (w > h ? w : h);
      out = img.copyResize(
        decoded,
        width: (w * scale).round().clamp(1, maxSide),
        height: (h * scale).round().clamp(1, maxSide),
        interpolation: img.Interpolation.average,
      );
    }

    if (_temTransparencia(out)) {
      // `level: 4` em vez do 6 por defeito: o encode fica sensivelmente mais
      // rápido e o ficheiro cresce pouco — numa logo o que pesa é a área lisa,
      // que comprime bem em qualquer nível.
      return ChurchLogoEncoded(
        bytes: Uint8List.fromList(img.encodePng(out, level: 4)),
        mimeType: 'image/png',
        width: out.width,
        height: out.height,
      );
    }
    return ChurchLogoEncoded(
      bytes: Uint8List.fromList(img.encodeJpg(out, quality: 92)),
      mimeType: 'image/jpeg',
      width: out.width,
      height: out.height,
    );
  } catch (e) {
    debugPrint('encodeChurchLogoSync: $e');
    return ChurchLogoEncoded(
      bytes: raw,
      mimeType: 'image/png',
      width: 0,
      height: 0,
    );
  }
}

ChurchLogoEncoded _encodeChurchLogoIsolate(ChurchLogoPngEncodeArgs args) {
  return encodeChurchLogoSync(args.raw, maxSide: args.maxSide);
}

/// Decode/resize/encode em **outra isolate** — evita "0%" eterno enquanto a UI
/// está bloqueada.
Future<ChurchLogoEncoded> encodeChurchLogoInIsolate(
  Uint8List raw, {
  int maxSide = 1920,
}) {
  return compute(
    _encodeChurchLogoIsolate,
    ChurchLogoPngEncodeArgs(raw, maxSide),
  );
}

/// Compatível com chamadas antigas que só querem os bytes em PNG.
@Deprecated('Use encodeChurchLogoInIsolate — devolve também o mimeType.')
Future<Uint8List> encodeChurchLogoAsPngInIsolate(
  Uint8List raw, {
  int maxSide = 1920,
}) async {
  final r = await encodeChurchLogoInIsolate(raw, maxSide: maxSide);
  return r.bytes;
}
