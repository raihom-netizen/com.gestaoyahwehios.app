import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/church_ct_module_upload.dart';
import 'package:gestao_yahweh/services/high_res_image_pipeline.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:image_picker/image_picker.dart';

/// Modo de enquadramento da foto de perfil.
enum MemberPhotoCropMode {
  /// Centro 1:1 automático — sem editor (mais rápido).
  auto,

  /// Editor «Ajustar foto de perfil» (manual).
  manual,
}

/// Escolha de foto de perfil — painel + cadastro público.
///
/// Fluxo moderno: origem → **Usar automaticamente** ou **Ajustar manualmente** → WebP.
abstract final class MemberProfilePhotoPickService {
  MemberProfilePhotoPickService._();

  /// Diálogo premium — câmera/galeria + modo auto/manual.
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

    final choice = await showModalBottomSheet<_PickChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _MemberPhotoPickSheet(web: kIsWeb),
    );
    if (choice == null || !context.mounted) return null;

    return _pickAndEncode(
      context,
      sourceKey: choice.source,
      cropMode: choice.cropMode,
      requireAuth: requireAuth,
    );
  }

  static Future<({Uint8List bytes, String displayName})?> pickFromGallery(
    BuildContext context, {
    bool requireAuth = true,
    MemberPhotoCropMode cropMode = MemberPhotoCropMode.manual,
  }) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.membros,
      requireAuth: requireAuth,
    )) {
      return null;
    }
    return _pickAndEncode(
      context,
      sourceKey: 'gallery',
      cropMode: cropMode,
      requireAuth: requireAuth,
    );
  }

  static Future<({Uint8List bytes, String displayName})?> pickFromCamera(
    BuildContext context, {
    bool requireAuth = true,
    MemberPhotoCropMode cropMode = MemberPhotoCropMode.manual,
  }) async {
    if (kIsWeb) return null;
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.membros,
      requireAuth: requireAuth,
    )) {
      return null;
    }
    return _pickAndEncode(
      context,
      sourceKey: 'camera',
      cropMode: cropMode,
      requireAuth: requireAuth,
    );
  }

  /// Web: ficheiro local → auto ou crop.
  static Future<({Uint8List bytes, String displayName})?> pickFromWebFileWithCrop(
    BuildContext context, {
    bool requireAuth = true,
    MemberPhotoCropMode cropMode = MemberPhotoCropMode.manual,
  }) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.membros,
      requireAuth: requireAuth,
    )) {
      return null;
    }
    return _pickAndEncode(
      context,
      sourceKey: 'file',
      cropMode: cropMode,
      requireAuth: requireAuth,
    );
  }

  static Future<({Uint8List bytes, String displayName})?> _pickAndEncode(
    BuildContext context, {
    required String sourceKey,
    required MemberPhotoCropMode cropMode,
    required bool requireAuth,
  }) async {
    XFile? picked;
    if (sourceKey == 'file') {
      final ct = await ChurchCtModuleUpload.pickReceiptOrDocument(
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        maxBytes: ChurchCtModuleUpload.kMaxImageBytes,
      );
      if (ct == null) return null;
      final name =
          ct.fileName.trim().isNotEmpty ? ct.fileName.trim() : 'foto_perfil.webp';
      picked = XFile.fromData(ct.bytes, name: name);
    } else {
      final ct = await ChurchCtModuleUpload.pickImage(
        source: sourceKey == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1920,
      );
      if (ct == null) return null;
      final name =
          ct.fileName.trim().isNotEmpty ? ct.fileName.trim() : 'foto_perfil.jpg';
      picked = XFile.fromData(ct.bytes, name: name);
    }
    if (!context.mounted) return null;

    final XFile? encoded;
    if (cropMode == MemberPhotoCropMode.auto) {
      encoded = await encodeMemberPhotoAutoCenterWebp(picked);
    } else {
      encoded = await cropEncodePickedToWebp(
        picked,
        profile: HighResCropProfile.memberSquare,
        webCropContext: context,
      );
    }
    return _resultFromXFile(encoded);
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

class _PickChoice {
  const _PickChoice({required this.source, required this.cropMode});
  final String source;
  final MemberPhotoCropMode cropMode;
}

class _MemberPhotoPickSheet extends StatelessWidget {
  const _MemberPhotoPickSheet({required this.web});

  final bool web;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Foto do perfil',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Escolha a origem e o enquadramento. Uma foto por membro — '
                    'ao guardar, a anterior é substituída no Storage.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              _sectionLabel('Usar automaticamente (centro 1:1)'),
              if (web) ...[
                _tile(
                  context,
                  icon: Icons.bolt_rounded,
                  title: 'Galeria — automático',
                  subtitle: 'Sem abrir o editor de corte',
                  choice: const _PickChoice(
                    source: 'gallery',
                    cropMode: MemberPhotoCropMode.auto,
                  ),
                ),
                _tile(
                  context,
                  icon: Icons.folder_open_rounded,
                  title: 'Arquivo — automático',
                  subtitle: 'JPG, PNG ou WebP',
                  choice: const _PickChoice(
                    source: 'file',
                    cropMode: MemberPhotoCropMode.auto,
                  ),
                ),
              ] else ...[
                _tile(
                  context,
                  icon: Icons.bolt_rounded,
                  title: 'Galeria — automático',
                  subtitle: 'Sem abrir o editor de corte',
                  choice: const _PickChoice(
                    source: 'gallery',
                    cropMode: MemberPhotoCropMode.auto,
                  ),
                ),
                _tile(
                  context,
                  icon: Icons.photo_camera_rounded,
                  title: 'Câmera — automático',
                  subtitle: 'Selfie com corte central',
                  choice: const _PickChoice(
                    source: 'camera',
                    cropMode: MemberPhotoCropMode.auto,
                  ),
                ),
              ],
              _sectionLabel('Ajustar manualmente'),
              if (web) ...[
                _tile(
                  context,
                  icon: Icons.crop_rounded,
                  title: 'Galeria — recortar',
                  subtitle: 'Abrir «Ajustar foto de perfil»',
                  choice: const _PickChoice(
                    source: 'gallery',
                    cropMode: MemberPhotoCropMode.manual,
                  ),
                ),
                _tile(
                  context,
                  icon: Icons.crop_free_rounded,
                  title: 'Arquivo — recortar',
                  subtitle: 'Escolher e ajustar a área',
                  choice: const _PickChoice(
                    source: 'file',
                    cropMode: MemberPhotoCropMode.manual,
                  ),
                ),
              ] else ...[
                _tile(
                  context,
                  icon: Icons.crop_rounded,
                  title: 'Galeria — recortar',
                  subtitle: 'Abrir editor de enquadramento',
                  choice: const _PickChoice(
                    source: 'gallery',
                    cropMode: MemberPhotoCropMode.manual,
                  ),
                ),
                _tile(
                  context,
                  icon: Icons.camera_alt_rounded,
                  title: 'Câmera — recortar',
                  subtitle: 'Tirar foto e ajustar',
                  choice: const _PickChoice(
                    source: 'camera',
                    cropMode: MemberPhotoCropMode.manual,
                  ),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required _PickChoice choice,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFEEF2FF),
        child: Icon(icon, color: ThemeCleanPremium.primary, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      onTap: () => Navigator.pop(context, choice),
    );
  }
}
