import 'dart:async' show unawaited;

import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show BuildContext, ScaffoldMessenger, SnackBar, Text;
import 'package:gestao_yahweh/core/evento_aviso_media_policy.dart';
import 'package:gestao_yahweh/core/media_upload_limits.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:file_picker/file_picker.dart' show FileType;
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

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

  void _showPermissionError(BuildContext? context, String message) {
    if (context == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Windows/Linux **não registam** o `image_picker`
  /// (ver `windows/flutter/generated_plugins.cmake`): qualquer `pickImage`
  /// rebentava com MissingPluginException e nenhum módulo conseguia anexar
  /// (Financeiro, Fornecedores, Patrimônio, Membros…). No desktop a galeria
  /// abre pelo seletor de ficheiros nativo (`file_selector_windows`).
  static bool get isDesktopWithoutImagePicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static const List<String> _imageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'gif',
    'heic',
  ];

  static const List<String> _videoExtensions = [
    'mp4',
    'mov',
    'm4v',
    'webm',
    'avi',
    'mkv',
  ];

  Future<List<XFile>> _pickFromDesktopFileDialog({
    required String dialogTitle,
    required List<String> extensions,
    bool allowMultiple = false,
    int maxCount = 1,
  }) async {
    final result = await YahwehFilePicker.pickFiles(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: extensions,
      allowMultiple: allowMultiple,
      // Caminho real no disco: o pipeline io lê por path e não gasta RAM.
      withData: false,
    );
    if (result == null || result.files.isEmpty) return const [];
    final out = <XFile>[];
    for (final f in result.files.take(allowMultiple ? maxCount : 1)) {
      final path = (f.path ?? '').trim();
      if (path.isEmpty) continue;
      out.add(XFile(path, name: f.name));
    }
    return out;
  }

  Future<bool> _ensureCameraPermission() async {
    if (kIsWeb) return true;
    try {
      final status = await ph.Permission.camera.status;
      if (status.isGranted || status.isLimited) return true;
      final requested = await ph.Permission.camera.request();
      return requested.isGranted || requested.isLimited;
    } catch (_) {
      return false;
    }
  }

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
    YahwehMediaModule? module,
    BuildContext? context,
  }) async {
    if (source == ImageSource.camera && !await _ensureCameraPermission()) {
      _showPermissionError(
        context,
        'Permissão de câmera negada. Ative nas configurações do aparelho.',
      );
      return null;
    }
    // Telegram: no chat, não bloquear o picker (Firebase aquece em BG).
    if (module != YahwehMediaModule.chat) {
      if (!await YahwehModuleMediaGate.ensureReadyForPick(
        context: context,
        module: module,
      )) {
        return null;
      }
    } else {
      unawaited(
        YahwehModuleMediaGate.ensureReadyForPick(
          context: null,
          module: module,
        ).catchError((_) => false),
      );
    }
    if (!kIsWeb) {
      BiometricService.markBiometricVerifiedForNextPainelEntry();
    }
    XFile? picked;
    if (isDesktopWithoutImagePicker) {
      if (source == ImageSource.camera) {
        _showPermissionError(
          context,
          'Câmera não disponível no app de Windows. '
          'Use «Arquivo» para escolher a imagem do computador.',
        );
        return null;
      }
      final files = await _pickFromDesktopFileDialog(
        dialogTitle: 'Escolher imagem',
        extensions: _imageExtensions,
      );
      picked = files.isEmpty ? null : files.first;
    } else {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: kIsWeb ? (imageQuality ?? quality) : 100,
        maxWidth: kIsWeb ? (minWidth ?? maxWidth).toDouble() : null,
        maxHeight: kIsWeb ? (minHeight ?? maxHeight).toDouble() : null,
      );
    }
    if (picked == null) return null;
    return impl.processPickedImage(
      picked,
      quality: imageQuality ?? quality,
      minWidth: minWidth ?? maxWidth,
      minHeight: minHeight ?? maxHeight,
    );
  }

  /// Apenas galeria, processado para Full HD (conveniente para membros/eventos).
  Future<XFile?> pickAndProcessFromGallery({
    YahwehMediaModule? module,
    BuildContext? context,
  }) =>
      pickAndProcessImage(
        source: ImageSource.gallery,
        module: module,
        context: context,
      );

  /// Câmera, processado para Full HD.
  Future<XFile?> pickAndProcessFromCamera({
    YahwehMediaModule? module,
    BuildContext? context,
  }) =>
      pickAndProcessImage(
        source: ImageSource.camera,
        module: module,
        context: context,
      );

  /// Múltiplas imagens da galeria (ex.: chat/eventos), processadas para Full HD.
  Future<List<XFile>> pickAndProcessMultipleImages({
    YahwehMediaModule? module,
    BuildContext? context,
    int maxCount = kChatMaxImagesPerPick,
  }) async {
    if (module != YahwehMediaModule.chat) {
      if (!await YahwehModuleMediaGate.ensureReadyForPick(
        context: context,
        module: module,
      )) {
        return [];
      }
    } else {
      unawaited(
        YahwehModuleMediaGate.ensureReadyForPick(
          context: null,
          module: module,
        ).catchError((_) => false),
      );
    }
    if (!kIsWeb) {
      BiometricService.markBiometricVerifiedForNextPainelEntry();
    }
    final list = isDesktopWithoutImagePicker
        ? await _pickFromDesktopFileDialog(
            dialogTitle: 'Escolher imagens',
            extensions: _imageExtensions,
            allowMultiple: true,
            maxCount: maxCount,
          )
        : await _picker.pickMultiImage(
            limit: maxCount,
            imageQuality: kIsWeb ? quality : 100,
            maxWidth: kIsWeb ? maxWidth.toDouble() : null,
            maxHeight: kIsWeb ? maxHeight.toDouble() : null,
          );
    if (list.isEmpty) return [];
    const batch = 4;
    final out = <XFile>[];
    final capped = list.take(maxCount).toList();
    for (var start = 0; start < capped.length; start += batch) {
      final chunk = capped.skip(start).take(batch).toList();
      final processed = await Future.wait(
        chunk.map(
          (x) => impl.processPickedImage(
            x,
            quality: quality,
            minWidth: maxWidth,
            minHeight: maxHeight,
          ),
        ),
      );
      out.addAll(processed);
    }
    return out;
  }

  /// Captura/seleciona imagem de logo e processa para 4K (qualidade alta).
  /// Retorna um [XFile] pronto para upload (bytes/XFile.path).
  Future<XFile?> pickAndProcessLogoImage({
    ImageSource source = ImageSource.gallery,
    BuildContext? context,
  }) async {
    return pickAndProcessImage(
      source: source,
      imageQuality: logoQuality,
      minWidth: logoMaxWidth,
      minHeight: logoMaxHeight,
      module: YahwehMediaModule.cadastro,
      context: context,
    );
  }

  Future<XFile?> pickAndProcessLogoFromGallery({BuildContext? context}) =>
      pickAndProcessLogoImage(source: ImageSource.gallery, context: context);

  Future<XFile?> pickAndProcessLogoFromCamera({BuildContext? context}) =>
      pickAndProcessLogoImage(source: ImageSource.camera, context: context);

  /// Mural / avisos / eventos: web = encode automático; mobile = recorte/confirmar conforme plataforma.
  /// [webpOutputQuality]: use [kPremiumMuralFeedWebpQuality] (ou [kHighResWebpQuality]).
  Future<XFile?> pickCropEncodeFeedImageWebp({
    required ImageSource source,
    BuildContext? webCropContext,
    int webpOutputQuality = kPremiumMuralFeedWebpQuality,
    YahwehMediaModule? module,
  }) async {
    if (source == ImageSource.camera && !await _ensureCameraPermission()) {
      _showPermissionError(
        webCropContext,
        'Permissão de câmera negada. Ative nas configurações do aparelho.',
      );
      return null;
    }
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: webCropContext,
      module: module,
    )) {
      return null;
    }
    return pickCropEncodeWebp(
      source: source,
      profile: HighResCropProfile.feedFree,
      webCropContext: webCropContext,
      webpOutputQuality: webpOutputQuality,
    );
  }

  /// Foto de membro: quadrado 1:1 + WebP (nativo).
  Future<XFile?> pickCropEncodeMemberPhotoWebp({
    required ImageSource source,
    BuildContext? webCropContext,
    bool requireAuth = true,
  }) async {
    if (source == ImageSource.camera && !await _ensureCameraPermission()) {
      _showPermissionError(
        webCropContext,
        'Permissão de câmera negada. Ative nas configurações do aparelho.',
      );
      return null;
    }
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: webCropContext,
      module: YahwehMediaModule.membros,
      requireAuth: requireAuth,
    )) {
      return null;
    }
    return pickCropEncodeWebp(
      source: source,
      profile: HighResCropProfile.memberSquare,
      webCropContext: webCropContext,
    );
  }

  /// Várias imagens da galeria (mural) — recorte por foto + WebP (sequencial no mobile).
  Future<List<XFile>> pickMultiCropEncodeFeedWebpFromGallery(
    BuildContext? webCropContext, {
    int? maxPickCount,
    int webpOutputQuality = kPremiumMuralFeedWebpQuality,
    YahwehMediaModule? module,
    void Function(List<XFile> picked)? onGalleryPicked,
    void Function(XFile picked, int index, int total)? onPickedBeforeEncode,
    void Function(XFile encoded, int index, int total)? onEachReady,
    void Function(int index, int total)? onEncodeSkipped,
  }) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: webCropContext,
      module: module,
    )) {
      return [];
    }
    if (!kIsWeb) {
      BiometricService.markBiometricVerifiedForNextPainelEntry();
    }
    final edge = kEffectiveFeedEncodeMaxEdgePx.toDouble();
    final list = isDesktopWithoutImagePicker
        ? await _pickFromDesktopFileDialog(
            dialogTitle: 'Escolher imagens',
            extensions: _imageExtensions,
            allowMultiple: true,
            maxCount: maxPickCount ?? kChatMaxImagesPerPick,
          )
        : await _picker.pickMultiImage(
            limit: maxPickCount,
            imageQuality: kIsWeb
                ? kEventoAvisoFeedWebpQuality
                : kEffectiveMuralFeedWebpQuality,
            maxWidth: edge,
            maxHeight: edge,
          );
    if (list.isEmpty) return [];
    onGalleryPicked?.call(list);
    // Foto inteira automática (sem ecrã de recorte por foto) — pedido do usuário:
    // recortar só se quiser (câmara mantém o ecrã «Ajustar enquadramento» opcional).
    if (kIsWeb) {
      return pickMultiEncodeFeedWebAuto(
        list,
        webpOutputQuality: webpOutputQuality,
        onPickedBeforeEncode: onPickedBeforeEncode,
        onEachReady: onEachReady,
        onEncodeSkipped: onEncodeSkipped,
      );
    }
    return pickMultiEncodeFeedTurboFast(
      list,
      onPickedBeforeEncode: onPickedBeforeEncode,
      onEachReady: onEachReady,
      onEncodeSkipped: onEncodeSkipped,
    );
  }

  // ==========================================================================
  // VIDEO PICKING — Chat / Módulos
  // ==========================================================================

  /// Pick vídeo da galeria (mobile + web).
  /// Retorna [XFile] pronto para upload.
  /// Compressão opcional via [MediaService.prepareVideoForUpload].
  Future<XFile?> pickVideoFromGallery({
    Duration? maxDuration,
    int? maxSizeMb,
    YahwehMediaModule? module,
    BuildContext? context,
  }) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: module,
    )) {
      return null;
    }
    if (!kIsWeb) {
      BiometricService.markBiometricVerifiedForNextPainelEntry();
    }
    XFile? picked;
    if (isDesktopWithoutImagePicker) {
      final files = await _pickFromDesktopFileDialog(
        dialogTitle: 'Escolher vídeo',
        extensions: _videoExtensions,
      );
      picked = files.isEmpty ? null : files.first;
    } else {
      picked = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: maxDuration,
      );
    }
    if (picked == null) return null;
    // Validação de tamanho (mobile).
    if (!kIsWeb && maxSizeMb != null) {
      final size = await picked.length();
      final maxBytes = maxSizeMb * 1024 * 1024;
      if (size > maxBytes) {
        _showPermissionError(
          context,
          'Vídeo muito grande (${(size / (1024 * 1024)).toStringAsFixed(1)}MB). Máximo: ${maxSizeMb}MB.',
        );
        return null;
      }
    }
    return picked;
  }

  /// Pick vídeo da câmera (mobile + web).
  Future<XFile?> pickVideoFromCamera({
    Duration? maxDuration,
    int? maxSizeMb,
    YahwehMediaModule? module,
    BuildContext? context,
  }) async {
    if (!await _ensureCameraPermission()) {
      _showPermissionError(
        context,
        'Permissão de câmera negada. Ative nas configurações do aparelho.',
      );
      return null;
    }
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: module,
    )) {
      return null;
    }
    if (!kIsWeb) {
      BiometricService.markBiometricVerifiedForNextPainelEntry();
    }
    if (isDesktopWithoutImagePicker) {
      _showPermissionError(
        context,
        'Câmera não disponível no app de Windows. '
        'Use «Arquivo» para escolher o vídeo do computador.',
      );
      return null;
    }
    final XFile? picked = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: maxDuration,
    );
    if (picked == null) return null;
    if (!kIsWeb && maxSizeMb != null) {
      final size = await picked.length();
      final maxBytes = maxSizeMb * 1024 * 1024;
      if (size > maxBytes) {
        _showPermissionError(
          context,
          'Vídeo muito grande (${(size / (1024 * 1024)).toStringAsFixed(1)}MB). Máximo: ${maxSizeMb}MB.',
        );
        return null;
      }
    }
    return picked;
  }
}
