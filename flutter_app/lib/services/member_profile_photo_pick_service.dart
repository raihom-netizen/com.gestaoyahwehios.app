import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Escolha de foto de perfil — **mesmo pipeline** do cadastro público:
/// picker → recorte/quadrado → WebP → bytes.
abstract final class MemberProfilePhotoPickService {
  MemberProfilePhotoPickService._();

  /// Diálogo premium — câmera/galeria (mobile) ou galeria/arquivo (web).
  static Future<({Uint8List bytes, String displayName})?> pickForMemberEdit(
    BuildContext context, {
    bool requireAuth = true,
  }) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.membros,
      requireAuth: requireAuth,
    )) {
      return null;
    }
    if (kIsWeb) {
      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _sourceSheet(ctx, web: true),
      );
      if (source == null || !context.mounted) return null;
      if (source == 'file') {
        return pickFromWebFileWithCrop(context, requireAuth: requireAuth);
      }
      return pickFromGallery(context, requireAuth: requireAuth);
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _sourceSheet(ctx, web: false),
    );
    if (source == null || !context.mounted) return null;
    if (source == ImageSource.camera) {
      return pickFromCamera(context, requireAuth: requireAuth);
    }
    return pickFromGallery(context, requireAuth: requireAuth);
  }

  static Widget _sourceSheet(BuildContext ctx, {required bool web}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Foto do perfil',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(web ? 'Escolher imagem' : 'Escolher da galeria'),
              onTap: () => Navigator.pop(
                ctx,
                web ? 'gallery' : ImageSource.gallery,
              ),
            ),
            if (web)
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('Arquivo (JPG/PNG/WebP)'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
            if (!web)
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Tirar foto'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Future<({Uint8List bytes, String displayName})?> pickFromGallery(
    BuildContext context, {
    bool requireAuth = true,
  }) async {
    final file = await MediaHandlerService.instance.pickCropEncodeMemberPhotoWebp(
      source: ImageSource.gallery,
      webCropContext: context,
      requireAuth: requireAuth,
    );
    return _resultFromXFile(file);
  }

  static Future<({Uint8List bytes, String displayName})?> pickFromCamera(
    BuildContext context, {
    bool requireAuth = true,
  }) async {
    if (kIsWeb) return null;
    final file = await MediaHandlerService.instance.pickCropEncodeMemberPhotoWebp(
      source: ImageSource.camera,
      webCropContext: context,
      requireAuth: requireAuth,
    );
    return _resultFromXFile(file);
  }

  /// Web: ficheiro local → ecrã de recorte (igual cadastro público).
  static Future<({Uint8List bytes, String displayName})?> pickFromWebFileWithCrop(
    BuildContext context, {
    bool requireAuth = true,
  }) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.membros,
      requireAuth: requireAuth,
    )) {
      return null;
    }
    final result = await YahwehFilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    final raw = f.bytes;
    if (raw == null || raw.isEmpty || !context.mounted) return null;
    final name = f.name.trim().isNotEmpty ? f.name.trim() : 'foto_perfil.webp';
    final encoded = await cropEncodePickedToWebp(
      XFile.fromData(raw, name: name),
      profile: HighResCropProfile.memberSquare,
      webCropContext: context,
    );
    if (encoded == null) return null;
    final bytes = await encoded.readAsBytes();
    if (bytes.isEmpty) return null;
    final outName = encoded.name.trim().isNotEmpty ? encoded.name.trim() : name;
    return (bytes: bytes, displayName: outName);
  }

  static Future<({Uint8List bytes, String displayName})?> _resultFromXFile(
    XFile? file,
  ) async {
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;
    final name =
        file.name.trim().isNotEmpty ? file.name.trim() : 'foto_perfil.webp';
    return (bytes: bytes, displayName: name);
  }
}
