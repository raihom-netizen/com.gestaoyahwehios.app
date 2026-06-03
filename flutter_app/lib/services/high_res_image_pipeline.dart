import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/services/media_service.dart';
import 'package:gestao_yahweh/ui/widgets/ios_feed_photo_confirm_screen.dart';
import 'package:gestao_yahweh/ui/widgets/premium_feed_image_crop_screen.dart';
import 'package:path_provider/path_provider.dart';
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

int get kEffectiveMuralFeedWebpQuality => kEventoAvisoFeedWebpQuality;

int get kEffectiveFeedEncodeMaxEdgePx => eventoAvisoFeedEncodeMaxEdgePx();

/// Máximo de fotos novas no editor de avisos (evita lotes enormes em 4G).
/// Máximo de fotos por aviso (publicação instantânea + upload em background).
const int kMaxAvisoFeedPhotosPerPost = 5;

/// Eventos no mural — até 10 fotos compactadas.
const int kMaxEventFeedPhotosPerPost = 10;

/// WebP final — retrocompat (igual ao premium mural).
const int kHighResWebpQuality = kPremiumMuralFeedWebpQuality;

/// WebP avisos — retrocompat (unificado com eventos para nitidez consistente).
const int kAvisoFeedWebpQuality = kPremiumMuralFeedWebpQuality;

/// Seleciona imagem → recorte nativo ([image_cropper]) → WebP.
///
/// **Feed (eventos/avisos):** web = foto inteira + WebP automático (Controle Total);
/// Android = [PremiumFeedImageCropScreen]; iOS = [IosFeedPhotoConfirmScreen].
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
    imageQuality: kIsWeb ? 100 : kEventoAvisoFeedWebpQuality,
    maxWidth: kIsWeb ? kHighResCropMaxWidth.toDouble() : kEffectiveFeedEncodeMaxEdgePx.toDouble(),
    maxHeight: kIsWeb ? kHighResCropMaxHeight.toDouble() : kEffectiveFeedEncodeMaxEdgePx.toDouble(),
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

/// Web: 5 em paralelo. Mobile turbo: 4 (galeria aviso/evento). Legado: 1.
int get kEffectiveFeedCropParallel =>
    kIsWeb ? 5 : (kMediaTurboMobilePreset ? 4 : 1);

/// Teto do recorte nativo no telemóvel (evita OOM no iPhone com fotos 12MP+).
int get _mobileCropMaxDimension =>
    kIsWeb ? kHighResCropMaxWidth : kEffectiveFeedEncodeMaxEdgePx;

bool get _feedIosUsesStableJpeg =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get _isIosNative => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get _isAndroidNative =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Android mural: recorte Flutter com **Confirmar em baixo** (não uCrop nativo no topo).
Future<XFile?> _androidFeedCropAndEncode(
  XFile working,
  BuildContext? webCropContext,
  int webpOutputQuality,
) async {
  if (webCropContext == null || !webCropContext.mounted) {
    return _encodeFeedImageFile(working.path);
  }
  try {
    final rawBytes = await File(working.path).readAsBytes();
    if (rawBytes.isEmpty) return null;
    final previewBytes = await _downscaleBytesForFeedCropUi(rawBytes);
    // ignore: use_build_context_synchronously
    if (!webCropContext.mounted) return null;
    // ignore: use_build_context_synchronously
    final croppedBytes = await Navigator.of(webCropContext, rootNavigator: true)
        .push<Uint8List?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PremiumFeedImageCropScreen(imageBytes: previewBytes),
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
  } catch (e) {
    if (kDebugMode) debugPrint('androidFeedCrop: $e');
    return _encodeFeedImageFile(working.path);
  }
}

/// iOS mural: confirmação Flutter (sem TOCropViewController — crash em TestFlight).
Future<XFile?> _iosFeedConfirmAndEncode(
  XFile working,
  BuildContext? webCropContext,
) async {
  final prepared = await _encodeFeedImageFile(working.path);
  if (prepared == null) return null;
  final path = prepared.path;
  if (path.isEmpty) return prepared;
  if (webCropContext == null || !webCropContext.mounted) {
    return prepared;
  }
  // ignore: use_build_context_synchronously
  final confirmed = await Navigator.of(webCropContext, rootNavigator: true)
      .push<String?>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => IosFeedPhotoConfirmScreen(imagePath: path),
    ),
  );
  if (confirmed == null || confirmed.isEmpty) return null;
  if (confirmed == path) return prepared;
  return _encodeFeedImageFile(confirmed);
}

/// No mobile, reduz no disco antes do recorte (HEIC/12MP → JPEG leve ~1080px).
Future<XFile> _mobilePreparePickedForCrop(XFile picked) async {
  if (kIsWeb) return picked;
  try {
    final f = File(picked.path);
    if (!f.existsSync()) return picked;
    final pre = await MediaService.compressImage(
      f,
      profile: MediaImageProfile.feed,
    );
    if (pre != null && pre.existsSync()) {
      return XFile(pre.path);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('mobile pre-crop compress: $e');
  }
  return picked;
}

/// Reduz bytes brutos da câmara antes do ecrã «Confirmar» (evita OOM e acelera o recorte).
Future<Uint8List> _downscaleBytesForFeedCropUi(Uint8List raw) async {
  if (raw.isEmpty) return raw;
  try {
    final lite = await MediaService.compressImageBytes(
      raw,
      profile: MediaImageProfile.feed,
    );
    if (lite.isNotEmpty) return lite;
  } catch (e) {
    if (kDebugMode) debugPrint('downscaleBytesForFeedCropUi: $e');
  }
  return raw;
}

/// Codifica mural no disco (sem carregar 10MB+ em RAM no iPhone).
Future<XFile?> _encodeFeedImageFile(String pathIn) async {
  final f = File(pathIn);
  if (!f.existsSync()) return null;
  try {
    final out = await MediaService.compressImage(
      f,
      profile: MediaImageProfile.feed,
    );
    if (out == null || !out.existsSync()) return null;
    final lower = out.path.toLowerCase();
    final mime = lower.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    final name = out.path.split(Platform.pathSeparator).last;
    return XFile(out.path, mimeType: mime, name: name);
  } catch (e) {
    if (kDebugMode) debugPrint('encodeFeedImageFile: $e');
    return null;
  }
}

/// Web: galeria mural — WebP automático (foto inteira, sem modal de recorte).
Future<List<XFile>> pickMultiEncodeFeedWebAuto(
  List<XFile> picked, {
  int webpOutputQuality = kPremiumMuralFeedWebpQuality,
  void Function(XFile picked, int index, int total)? onPickedBeforeEncode,
  void Function(XFile encoded, int index, int total)? onEachReady,
  void Function(int index, int total)? onEncodeSkipped,
}) async {
  if (picked.isEmpty) return const [];
  final out = <XFile>[];
  final batch = kEffectiveFeedCropParallel.clamp(1, 6);
  for (var start = 0; start < picked.length; start += batch) {
    final chunk = picked.skip(start).take(batch).toList();
    final encoded = await Future.wait(
      chunk.asMap().entries.map((entry) async {
        final globalIndex = start + entry.key;
        onPickedBeforeEncode?.call(entry.value, globalIndex, picked.length);
        return encodeFeedPickedWebAuto(
          entry.value,
          webpOutputQuality: webpOutputQuality,
        );
      }),
    );
    for (var j = 0; j < encoded.length; j++) {
      final file = encoded[j];
      final globalIndex = start + j;
      if (file != null) {
        out.add(file);
        onEachReady?.call(file, globalIndex, picked.length);
      } else {
        onEncodeSkipped?.call(globalIndex, picked.length);
      }
    }
  }
  return out;
}

/// Uma foto do feed na web — proporção original, compressão WebP.
Future<XFile?> encodeFeedPickedWebAuto(
  XFile picked, {
  int webpOutputQuality = kPremiumMuralFeedWebpQuality,
}) async {
  try {
    final rawBytes = await picked.readAsBytes();
    if (rawBytes.isEmpty) return null;
    final edge = kEffectiveFeedEncodeMaxEdgePx;
    return _bytesToWebpXFile(
      rawBytes,
      quality: webpOutputQuality,
      encodeMaxWidth: edge,
      encodeMaxHeight: edge,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('encodeFeedPickedWebAuto: $e');
    return null;
  }
}

/// Galeria mural (turbo mobile): WebP em paralelo **sem** ecrã de recorte por foto — alinhado à PWA.
Future<List<XFile>> pickMultiEncodeFeedTurboFast(
  List<XFile> picked, {
  void Function(XFile picked, int index, int total)? onPickedBeforeEncode,
  void Function(XFile encoded, int index, int total)? onEachReady,
  void Function(int index, int total)? onEncodeSkipped,
}) async {
  if (picked.isEmpty) return const [];
  final out = <XFile>[];
  final batch = kEffectiveFeedCropParallel.clamp(1, 6);
  for (var start = 0; start < picked.length; start += batch) {
    final chunk = picked.skip(start).take(batch).toList();
    final encoded = await Future.wait(
      chunk.asMap().entries.map((entry) async {
        final globalIndex = start + entry.key;
        onPickedBeforeEncode?.call(entry.value, globalIndex, picked.length);
        return _encodeFeedImageFile(entry.value.path);
      }),
    );
    for (var j = 0; j < encoded.length; j++) {
      final file = encoded[j];
      final globalIndex = start + j;
      if (file != null) {
        out.add(file);
        onEachReady?.call(file, globalIndex, picked.length);
      } else {
        onEncodeSkipped?.call(globalIndex, picked.length);
      }
    }
  }
  return out;
}

/// Galeria mural — recorte + WebP **um a um** (evita OOM no iPhone).
Future<List<XFile>> pickMultiCropEncodeFeedWebpSequential(
  List<XFile> picked, {
  BuildContext? webCropContext,
  int webpOutputQuality = kPremiumMuralFeedWebpQuality,
  void Function(XFile picked, int index, int total)? onPickedBeforeEncode,
  void Function(XFile encoded, int index, int total)? onEachReady,
  void Function(int index, int total)? onEncodeSkipped,
}) async {
  if (picked.isEmpty) return const [];
  final out = <XFile>[];
  for (var i = 0; i < picked.length; i++) {
    onPickedBeforeEncode?.call(picked[i], i, picked.length);
    final encoded = await cropEncodePickedToWebp(
      picked[i],
      profile: HighResCropProfile.feedFree,
      webCropContext: webCropContext,
      webpOutputQuality: webpOutputQuality,
    );
    if (encoded != null) {
      out.add(encoded);
      onEachReady?.call(encoded, i, picked.length);
    } else {
      onEncodeSkipped?.call(i, picked.length);
    }
  }
  return out;
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
  final batch = (parallel > 0 ? parallel : kEffectiveFeedCropParallel).clamp(1, 6);
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
  var working = picked;
  if (profile == HighResCropProfile.feedFree && !kIsWeb) {
    working = await _mobilePreparePickedForCrop(picked);
  }
  final square = profile == HighResCropProfile.memberSquare;

  /// Web + feed: foto inteira automática (sem ecrã «Ajustar enquadramento»).
  if (profile == HighResCropProfile.feedFree && kIsWeb) {
    return encodeFeedPickedWebAuto(
      working,
      webpOutputQuality: webpOutputQuality,
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
    final feed = profile == HighResCropProfile.feedFree;
    if (feed && _isIosNative) {
      return _iosFeedConfirmAndEncode(working, webCropContext);
    }
    if (feed && _isAndroidNative) {
      return _androidFeedCropAndEncode(
        working,
        webCropContext,
        webpOutputQuality,
      );
    }

    final cropMax = _mobileCropMaxDimension;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: working.path,
        maxWidth: cropMax,
        maxHeight: cropMax,
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
    } catch (e) {
      if (kDebugMode) debugPrint('ImageCropper: $e');
      cropped = null;
    }
  }

  final pathIn = cropped?.path ?? working.path;
  final feedEncoded = profile == HighResCropProfile.feedFree;

  if (!kIsWeb && feedEncoded) {
    return _encodeFeedImageFile(pathIn);
  }

  final rawBytes = await XFile(pathIn).readAsBytes();
  final feedEdge = kEffectiveFeedEncodeMaxEdgePx;
  return _bytesToWebpXFile(
    rawBytes,
    quality: webpOutputQuality,
    encodeMaxWidth: feedEncoded ? feedEdge : kMemberCropWebpMaxEdgePx,
    encodeMaxHeight: feedEncoded ? feedEdge : kMemberCropWebpMaxEdgePx,
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
    final out = await MediaService.compressImageBytes(
      rawBytes,
      profile: MediaImageProfile.feed,
    );
    if (out.isEmpty) return null;
    final ext = _feedIosUsesStableJpeg ? 'jpg' : 'webp';
    final mime = ext == 'webp' ? 'image/webp' : 'image/jpeg';
    final name = 'gy_${DateTime.now().millisecondsSinceEpoch}.$ext';
    // Importante: mobile precisa de `path` válido (para o editor carregar e
    // re-lê bytes no `_copyNewImagesForPublish`). Bytes-only (`fromData`)
    // deixam o `path` vazio e quebram o publish síncrono.
    if (kIsWeb) {
      return XFile.fromData(out, mimeType: mime, name: name);
    }
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$name';
    final f = File(filePath);
    await f.writeAsBytes(out, flush: true);
    return XFile(f.path, mimeType: mime, name: name);
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
