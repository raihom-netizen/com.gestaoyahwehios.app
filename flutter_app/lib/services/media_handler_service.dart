import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show BuildContext;
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:image_picker/image_picker.dart';

// Condicional: mobile usa compressão nativa; web só usa image_picker com qualidade.
import 'media_handler_service_io.dart'
    if (dart.library.html) 'media_handler_service_web.dart' as impl;
import 'high_res_image_pipeline.dart';

/// Serviço de mídia para captura e processamento de imagens.
/// Padrão de performance: comprime antes do upload para reduzir latência.
/// Upload no projeto é feito via Firebase Storage (ref.putFile/putData) após obter o XFile.
class MediaHandlerService {
  MediaHandlerService._();
  static final MediaHandlerService instance = MediaHandlerService._();

  final ImagePicker _picker = ImagePicker();

  /// Padrão "feed social": arquivo leve com qualidade visual boa.
  /// Objetivo: uploads mais rápidos (especialmente em rede móvel).
  static int get quality => mediaPickerImageQuality;
  static int get maxWidth => mediaPickerImageMaxWidth;
  static int get maxHeight => mediaPickerImageMaxHeight;

  /// Padrão rígido para logos no app/site:
  /// - max 800px e qualidade 70 para evitar payload pesado.
  static int get logoQuality => mediaPickerLogoQuality;
  static int get logoMaxWidth => mediaPickerLogoMaxWidth;
  static int get logoMaxHeight => mediaPickerLogoMaxHeight;

  /// Captura imagem (galeria ou câmera) e processa antes do upload.
  /// No mobile: comprime com [flutter_image_compress] (quality 70, largura ~1024).
  /// Na web: usa [ImagePicker] com limitação de tamanho e qualidade.
  /// Retorna [XFile] para usar com Firebase Storage: putData(await xfile.readAsBytes()) ou putFile(File(xfile.path)).
  Future<XFile?> pickAndProcessImage({
    ImageSource source = ImageSource.gallery,
    int? imageQuality,
    int? minWidth,
    int? minHeight,
  }) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: kIsWeb ? (imageQuality ?? quality) : 100,
      maxWidth: kIsWeb ? (minWidth ?? maxWidth).toDouble() : null,
      maxHeight: kIsWeb ? (minHeight ?? maxHeight).toDouble() : null,
    );
    if (picked == null) return null;
    return impl.processPickedImage(
      picked,
      quality: imageQuality ?? quality,
      minWidth: minWidth ?? maxWidth,
      minHeight: minHeight ?? maxHeight,
    );
  }

  /// Apenas galeria, processado para Full HD (conveniente para membros/eventos).
  Future<XFile?> pickAndProcessFromGallery() =>
      pickAndProcessImage(source: ImageSource.gallery);

  /// Câmera, processado para Full HD.
  Future<XFile?> pickAndProcessFromCamera() =>
      pickAndProcessImage(source: ImageSource.camera);

  /// Múltiplas imagens da galeria (ex.: eventos), processadas para Full HD.
  Future<List<XFile>> pickAndProcessMultipleImages() async {
    final list = await _picker.pickMultiImage(
      imageQuality: kIsWeb ? quality : 100,
      maxWidth: kIsWeb ? maxWidth.toDouble() : null,
      maxHeight: kIsWeb ? maxHeight.toDouble() : null,
    );
    if (list.isEmpty) return [];
    final out = <XFile>[];
    for (final x in list) {
      final processed = await impl.processPickedImage(x,
          quality: quality, minWidth: maxWidth, minHeight: maxHeight);
      out.add(processed);
    }
    return out;
  }

  /// Captura/seleciona imagem de logo e processa para 4K (qualidade alta).
  /// Retorna um [XFile] pronto para upload (bytes/XFile.path).
  Future<XFile?> pickAndProcessLogoImage({
    ImageSource source = ImageSource.gallery,
  }) async {
    return pickAndProcessImage(
      source: source,
      imageQuality: logoQuality,
      minWidth: logoMaxWidth,
      minHeight: logoMaxHeight,
    );
  }

  Future<XFile?> pickAndProcessLogoFromGallery() =>
      pickAndProcessLogoImage(source: ImageSource.gallery);

  Future<XFile?> pickAndProcessLogoFromCamera() =>
      pickAndProcessLogoImage(source: ImageSource.camera);

  /// Mural / avisos / eventos: recorte livre + WebP 4K (nativo); na web use [webCropContext].
  /// [webpOutputQuality]: use [kAvisoFeedWebpQuality] para avisos (arte + texto, ficheiro menor).
  Future<XFile?> pickCropEncodeFeedImageWebp({
    required ImageSource source,
    BuildContext? webCropContext,
    int webpOutputQuality = kHighResWebpQuality,
  }) =>
      pickCropEncodeWebp(
        source: source,
        profile: HighResCropProfile.feedFree,
        webCropContext: webCropContext,
        webpOutputQuality: webpOutputQuality,
      );

  /// Foto de membro: quadrado 1:1 + WebP (nativo).
  Future<XFile?> pickCropEncodeMemberPhotoWebp({
    required ImageSource source,
    BuildContext? webCropContext,
  }) =>
      pickCropEncodeWebp(
        source: source,
        profile: HighResCropProfile.memberSquare,
        webCropContext: webCropContext,
      );

  /// Várias imagens da galeria (mural) — recorte por foto + WebP.
  Future<List<XFile>> pickMultiCropEncodeFeedWebpFromGallery(
    BuildContext? webCropContext, {
    int webpOutputQuality = kHighResWebpQuality,
  }) async {
    final list = await _picker.pickMultiImage(
      imageQuality: 100,
      maxWidth: kIsWeb ? kHighResCropMaxWidth.toDouble() : null,
      maxHeight: kIsWeb ? kHighResCropMaxHeight.toDouble() : null,
    );
    if (list.isEmpty) return [];
    // ignore: use_build_context_synchronously
    return pickMultiCropEncodeFeedWebp(
      list,
      webCropContext: webCropContext,
      webpOutputQuality: webpOutputQuality,
    );
  }
}
