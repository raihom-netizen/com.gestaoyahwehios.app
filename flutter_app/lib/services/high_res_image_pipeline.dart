import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// Perfil de recorte antes do upload (Yahweh Geral em alta definição).
enum HighResCropProfile {
  /// Foto de membro — quadrado 1:1 (perfil).
  memberSquare,

  /// Mural: avisos / eventos — proporção livre (presets no editor nativo).
  feedFree,
}

/// Teto 4K para o resultado do recorte (antes do WebP).
const int kHighResCropMaxWidth = 3840;
const int kHighResCropMaxHeight = 2160;

/// Qualidade na saída do recorte nativo (sem perda antes do WebP).
const int kCropperCompressQuality = 100;

/// WebP final — bom equilíbrio tamanho/nitidez para 4K (eventos / mural geral).
const int kHighResWebpQuality = 95;

/// WebP para **avisos** (artes com texto): ficheiro menor, texto legível em 3G.
const int kAvisoFeedWebpQuality = 90;

/// Seleciona imagem → recorte nativo ([image_cropper]) → WebP.
///
/// **Web:** requer [webCropContext] para abrir o Cropper.js; se for null, só
/// comprime para WebP sem recorte (degradação documentada).
Future<XFile?> pickCropEncodeWebp({
  required ImageSource source,
  required HighResCropProfile profile,
  BuildContext? webCropContext,
  int webpOutputQuality = kHighResWebpQuality,
}) async {
  final picker = ImagePicker();
  final picked = await picker.pickImage(
    source: source,
    imageQuality: 100,
    maxWidth: kIsWeb ? kHighResCropMaxWidth.toDouble() : null,
    maxHeight: kIsWeb ? kHighResCropMaxHeight.toDouble() : null,
  );
  if (picked == null) return null;
  // Context só para Cropper.js na web; chamador deve garantir widget ainda montado.
  // ignore: use_build_context_synchronously
  return cropEncodePickedToWebp(
    picked,
    profile: profile,
    webCropContext: webCropContext,
    webpOutputQuality: webpOutputQuality,
  );
}

/// Várias fotos da galeria — recorte + WebP para cada uma.
Future<List<XFile>> pickMultiCropEncodeFeedWebp(
  List<XFile> picked, {
  BuildContext? webCropContext,
  int webpOutputQuality = kHighResWebpQuality,
}) async {
  final out = <XFile>[];
  for (final x in picked) {
    final y = await cropEncodePickedToWebp(
      x,
      profile: HighResCropProfile.feedFree,
      webCropContext: webCropContext,
      webpOutputQuality: webpOutputQuality,
    );
    if (y != null) out.add(y);
  }
  return out;
}

/// Já existe [XFile] (ex. galeria multi) → recorte → WebP.
Future<XFile?> cropEncodePickedToWebp(
  XFile picked, {
  required HighResCropProfile profile,
  BuildContext? webCropContext,
  int webpOutputQuality = kHighResWebpQuality,
}) async {
  final square = profile == HighResCropProfile.memberSquare;
  CroppedFile? cropped;

  if (kIsWeb) {
    if (webCropContext != null) {
      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        maxWidth: kHighResCropMaxWidth,
        maxHeight: kHighResCropMaxHeight,
        compressQuality: kCropperCompressQuality,
        compressFormat: ImageCompressFormat.jpg,
        aspectRatio: square ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
        uiSettings: [
          WebUiSettings(
            context: webCropContext,
            presentStyle: WebPresentStyle.dialog,
            size: const CropperSize(width: 520, height: 620),
          ),
        ],
      );
    }
  } else {
    cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      maxWidth: kHighResCropMaxWidth,
      maxHeight: kHighResCropMaxHeight,
      compressQuality: kCropperCompressQuality,
      compressFormat: ImageCompressFormat.jpg,
      aspectRatio: square ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Ajustar enquadramento',
          toolbarColor: const Color(0xFF2563EB),
          toolbarWidgetColor: Colors.white,
          initAspectRatio: square
              ? CropAspectRatioPreset.square
              : CropAspectRatioPreset.original,
          lockAspectRatio: square,
          aspectRatioPresets: square
              ? [CropAspectRatioPreset.square]
              : [
                  CropAspectRatioPreset.original,
                  CropAspectRatioPreset.ratio16x9,
                  CropAspectRatioPreset.ratio4x3,
                  CropAspectRatioPreset.ratio3x2,
                  CropAspectRatioPreset.square,
                ],
        ),
        IOSUiSettings(
          title: 'Ajustar enquadramento',
          aspectRatioLockEnabled: square,
          aspectRatioPresets: square
              ? [CropAspectRatioPreset.square]
              : [
                  CropAspectRatioPreset.original,
                  CropAspectRatioPreset.square,
                  CropAspectRatioPreset.ratio16x9,
                  CropAspectRatioPreset.ratio4x3,
                ],
        ),
      ],
    );
  }

  final pathIn = cropped?.path ?? picked.path;
  final rawBytes = await XFile(pathIn).readAsBytes();
  return _bytesToWebpXFile(rawBytes, quality: webpOutputQuality);
}

Future<XFile?> _bytesToWebpXFile(Uint8List rawBytes, {required int quality}) async {
  if (rawBytes.isEmpty) return null;
  try {
    final out = await FlutterImageCompress.compressWithList(
      rawBytes,
      quality: quality,
      format: CompressFormat.webp,
    );
    if (out.isEmpty) return null;
    final name = 'gy_${DateTime.now().millisecondsSinceEpoch}.webp';
    return XFile.fromData(
      Uint8List.fromList(out),
      mimeType: 'image/webp',
      name: name,
    );
  } catch (_) {
    return null;
  }
}

bool bytesLookLikeWebp(Uint8List list) {
  return list.length >= 12 &&
      list[0] == 0x52 &&
      list[1] == 0x49 &&
      list[2] == 0x46 &&
      list[3] == 0x46 &&
      list[8] == 0x57 &&
      list[9] == 0x45 &&
      list[10] == 0x42 &&
      list[11] == 0x50;
}
