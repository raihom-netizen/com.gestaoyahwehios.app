import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/ui/widgets/premium_feed_image_crop_screen.dart';
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

/// Limite na codificação WebP final — padrão **Full HD** no maior lado (retrato/paisagem).
/// Usado em avisos e eventos do mural após o recorte.
const int kPremiumFeedFullHdMaxWidth = 1920;
const int kPremiumFeedFullHdMaxHeight = 1920;

/// Foto de membro (1:1): não usar teto Full HD do feed.
const int kMemberCropWebpMaxEdgePx = 768;

/// Qualidade na saída do recorte nativo (sem perda antes do WebP).
const int kCropperCompressQuality = 100;

/// WebP do feed — equilíbrio nitidez/velocidade de upload (avisos + eventos).
const int kPremiumMuralFeedWebpQuality = 80;

/// Qualidade WebP em release mobile (turbo — ficheiros menores, upload mais rápido).
const int kPremiumMuralFeedWebpQualityTurbo = 74;

int get kEffectiveMuralFeedWebpQuality =>
    kMediaTurboMobilePreset
        ? kPremiumMuralFeedWebpQualityTurbo
        : kPremiumMuralFeedWebpQuality;

int get kEffectiveFeedEncodeMaxEdgePx =>
    kMediaTurboMobilePreset ? 1280 : kPremiumFeedFullHdMaxWidth;

/// Máximo de fotos novas no editor de avisos (evita lotes enormes em 4G).
const int kMaxAvisoFeedPhotosPerPost = 15;

/// WebP final — retrocompat (igual ao premium mural).
const int kHighResWebpQuality = kPremiumMuralFeedWebpQuality;

/// WebP avisos — retrocompat (unificado com eventos para nitidez consistente).
const int kAvisoFeedWebpQuality = kPremiumMuralFeedWebpQuality;

/// Seleciona imagem → recorte nativo ([image_cropper]) → WebP.
///
/// **Feed (eventos/avisos):** com [webCropContext] montado, usa recorte Flutter
/// premium (iOS-like, mobile + web). Sem contexto na web: só WebP sem recorte.
/// **Foto membro:** mantém [image_cropper] nativo / Cropper.js na web.
Future<XFile?> pickCropEncodeWebp({
  required ImageSource source,
  required HighResCropProfile profile,
  BuildContext? webCropContext,
  int webpOutputQuality = kHighResWebpQuality,
}) async {
  final picker = ImagePicker();
  final ctx = webCropContext;
  final picked = await picker.pickImage(
    source: source,
    imageQuality: 100,
    maxWidth: kIsWeb ? kHighResCropMaxWidth.toDouble() : null,
    maxHeight: kIsWeb ? kHighResCropMaxHeight.toDouble() : null,
  );
  if (picked == null) return null;
  if (ctx != null && !ctx.mounted) return null;
  return cropEncodePickedToWebp(
    picked,
    profile: profile,
    webCropContext: ctx,
    webpOutputQuality: webpOutputQuality,
  );
}

/// Várias fotos da galeria — recorte + WebP (até [parallel] em paralelo).
Future<List<XFile>> pickMultiCropEncodeFeedWebp(
  List<XFile> picked, {
  BuildContext? webCropContext,
  int webpOutputQuality = kPremiumMuralFeedWebpQuality,
  int parallel = 5,
}) async {
  if (picked.isEmpty) return const [];
  final out = <XFile>[];
  final batch = parallel.clamp(1, 6);
  for (var start = 0; start < picked.length; start += batch) {
    final chunk = picked.skip(start).take(batch).toList();
    final encoded = await Future.wait(
      chunk.map(
        (x) => cropEncodePickedToWebp(
          x,
          profile: HighResCropProfile.feedFree,
          webCropContext: webCropContext,
          webpOutputQuality: webpOutputQuality,
        ),
      ),
    );
    for (final y in encoded) {
      if (y != null) out.add(y);
    }
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

  /// Mural feed: um único fluxo Flutter (Confirmar/Cancelar na base, iOS-like).
  if (profile == HighResCropProfile.feedFree && webCropContext != null) {
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return null;
    // ignore: use_build_context_synchronously
    if (!webCropContext.mounted) return null;
    // ignore: use_build_context_synchronously
    final croppedBytes = await Navigator.of(webCropContext, rootNavigator: true)
        .push<Uint8List?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PremiumFeedImageCropScreen(imageBytes: bytes),
      ),
    );
    if (croppedBytes == null || croppedBytes.isEmpty) return null;
    final edge = kEffectiveFeedEncodeMaxEdgePx;
    return _bytesToWebpXFile(
      croppedBytes,
      quality: webpOutputQuality,
      encodeMaxWidth: edge,
      encodeMaxHeight: edge,
    );
  }

  CroppedFile? cropped;

  if (kIsWeb) {
    if (webCropContext != null && square) {
      final ctx = webCropContext;
      final mq = MediaQuery.sizeOf(ctx);
      final reserved = kToolbarHeight + 120;
      final cropH = (mq.height - reserved).clamp(200.0, 620.0).round();
      final cropW = (mq.width - 24).clamp(280.0, 560.0).round();

      cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        maxWidth: kHighResCropMaxWidth,
        maxHeight: kHighResCropMaxHeight,
        compressQuality: kCropperCompressQuality,
        compressFormat: ImageCompressFormat.jpg,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          WebUiSettings(
            context: ctx,
            presentStyle: WebPresentStyle.page,
            size: CropperSize(width: cropW, height: cropH),
            translations: const WebTranslations(
              title: 'Ajustar enquadramento',
              rotateLeftTooltip: 'Girar 90° à esquerda',
              rotateRightTooltip: 'Girar 90° à direita',
              cancelButton: 'Cancelar',
              cropButton: 'Confirmar',
            ),
            themeData: const WebThemeData(
              backIcon: Icons.close_rounded,
              doneIcon: Icons.check_rounded,
            ),
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
          toolbarColor: const Color(0xFF1E40AF),
          toolbarWidgetColor: Colors.white,
          statusBarLight: false,
          navBarLight: false,
          backgroundColor: const Color(0xFF0F172A),
          activeControlsWidgetColor: const Color(0xFFF59E0B),
          dimmedLayerColor: const Color(0xB3000000),
          cropFrameColor: Colors.white,
          cropGridColor: Colors.white70,
          cropFrameStrokeWidth: 2,
          cropGridRowCount: 3,
          cropGridColumnCount: 3,
          cropGridStrokeWidth: 1,
          showCropGrid: true,
          hideBottomControls: false,
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
          doneButtonTitle: 'Confirmar',
          cancelButtonTitle: 'Cancelar',
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
  final feed = profile == HighResCropProfile.feedFree;
  final feedEdge = kEffectiveFeedEncodeMaxEdgePx;
  return _bytesToWebpXFile(
    rawBytes,
    quality: webpOutputQuality,
    encodeMaxWidth: feed ? feedEdge : kMemberCropWebpMaxEdgePx,
    encodeMaxHeight: feed ? feedEdge : kMemberCropWebpMaxEdgePx,
  );
}

Future<XFile?> _bytesToWebpXFile(
  Uint8List rawBytes, {
  required int quality,
  required int encodeMaxWidth,
  required int encodeMaxHeight,
}) async {
  if (rawBytes.isEmpty) return null;
  try {
    final out = await FlutterImageCompress.compressWithList(
      rawBytes,
      minWidth: encodeMaxWidth,
      minHeight: encodeMaxHeight,
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
