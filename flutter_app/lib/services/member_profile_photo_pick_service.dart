import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/media/safe_image_bytes.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Escolha de foto de perfil — pipeline único (crop + bytes) para Android/iOS/Web.
abstract final class MemberProfilePhotoPickService {
  MemberProfilePhotoPickService._();

  /// Diálogo premium — câmera/galeria (mobile) ou arquivo (web).
  static Future<({Uint8List bytes, String displayName})?> pickForMemberEdit(
    BuildContext context,
  ) async {
    if (kIsWeb) {
      return pickFromGallery(context);
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Tirar foto'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Escolher da galeria'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (source == null || !context.mounted) return null;
    if (source == ImageSource.camera) {
      return pickFromCamera(context);
    }
    return pickFromGallery(context);
  }

  static Future<({Uint8List bytes, String displayName})?> pickFromGallery(
    BuildContext context,
  ) async {
    if (kIsWeb) {
      return _pickWebFile();
    }
    final file = await MediaHandlerService.instance.pickCropEncodeMemberPhotoWebp(
      source: ImageSource.gallery,
      webCropContext: context,
    );
    if (file == null) return null;
    final bytes = await _bytesFromXFile(file);
    if (bytes == null || bytes.isEmpty) return null;
    final name = file.name.trim().isNotEmpty ? file.name.trim() : 'foto_perfil.webp';
    return (bytes: bytes, displayName: name);
  }

  static Future<({Uint8List bytes, String displayName})?> pickFromCamera(
    BuildContext context,
  ) async {
    if (kIsWeb) return null;
    final file = await MediaHandlerService.instance.pickCropEncodeMemberPhotoWebp(
      source: ImageSource.camera,
      webCropContext: context,
    );
    if (file == null) return null;
    final bytes = await _bytesFromXFile(file);
    if (bytes == null || bytes.isEmpty) return null;
    final name = file.name.trim().isNotEmpty ? file.name.trim() : 'foto_perfil.webp';
    return (bytes: bytes, displayName: name);
  }

  static Future<({Uint8List bytes, String displayName})?> _pickWebFile() async {
    final result = await YahwehFilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    final raw = f.bytes;
    if (raw == null || raw.isEmpty) return null;
    final bytes = await SafeImageBytes.fromPickerFile(
      XFile.fromData(raw, name: f.name.isNotEmpty ? f.name : 'foto.jpg'),
      maxEdge: 1280,
      quality: 88,
    );
    if (bytes.isEmpty) return null;
    return (
      bytes: bytes,
      displayName: f.name.trim().isNotEmpty ? f.name.trim() : 'foto_perfil.jpg',
    );
  }

  static Future<Uint8List?> _bytesFromXFile(XFile file) async {
    try {
      final compressed = await SafeImageBytes.memberProfileFromPicker(file);
      if (compressed.isNotEmpty) return compressed;
    } catch (_) {}
    try {
      final raw = await file.readAsBytes();
      if (raw.isNotEmpty) return raw;
    } catch (_) {}
    return null;
  }
}
