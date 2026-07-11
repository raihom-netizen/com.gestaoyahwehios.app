import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/church_canonical_media_contract.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show formatFirebaseErrorForUser;
import 'package:gestao_yahweh/core/media/media_optimization_service.dart';
import 'package:gestao_yahweh/core/yahweh_module_media_gate.dart';
import 'package:gestao_yahweh/services/media_handler_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/finance_comprovante_viewer_sheet.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';

/// Comprovante financeiro — JPEG/PNG/PDF (sem vídeo), padrão Controle Total.
class FinanceComprovanteAttachment {
  const FinanceComprovanteAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.alreadyOptimized = false,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  /// true quando o picker já passou por optimização no pick.
  final bool alreadyOptimized;

  bool get isPdf => mimeType.contains('pdf');
  bool get isImage => mimeType.startsWith('image/');
  bool get isPng => mimeType.contains('png');
}

abstract final class FinanceComprovanteAttachService {
  FinanceComprovanteAttachService._();

  static const int maxBytes = 5 * 1024 * 1024;
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

  static bool hasComprovanteInDoc(Map<String, dynamic> data) =>
      hasComprovanteReady(data);

  static bool hasComprovanteReady(Map<String, dynamic> data) =>
      ChurchCanonicalMediaContract.hasViewableFinanceComprovante(data);

  static bool isComprovanteUploading(Map<String, dynamic> data) {
    final state = (data['comprovanteUploadState'] ?? '').toString().trim();
    return state == EntityPublishStatus.uploading;
  }

  static String displayNameFromDoc(Map<String, dynamic> data) {
    final name = (data['comprovanteFileName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
    if (path.contains('/')) {
      return path.split('/').last;
    }
    return 'Comprovante';
  }

  static String mimeFromDoc(Map<String, dynamic> data) {
    final mime = (data['comprovanteMimeType'] ?? '').toString().trim();
    if (mime.isNotEmpty) return mime;
    final name = displayNameFromDoc(data).toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  static String extensionForMime(String mimeType) {
    final m = mimeType.toLowerCase();
    if (m.contains('pdf')) return 'pdf';
    if (m.contains('png')) return 'png';
    return 'jpg';
  }

  static String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase().replaceAll('jpeg', 'jpg')) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }

  static bool _isAllowedExtension(String ext) {
    final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
    return e == 'jpg' || e == 'png' || e == 'pdf';
  }

  static bool _isPngBytes(Uint8List bytes) {
    return bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
  }

  static String _ensureExtension(String fileName, String ext) {
    final base = fileName.trim().isEmpty ? 'comprovante' : fileName.trim();
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    return '$stem.$ext';
  }

  static void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// Uma compressão só (CT): JPEG optimizado; PNG pequeno mantém formato.
  static Future<FinanceComprovanteAttachment?> _finalizeImageAttachment({
    required Uint8List raw,
    required String fileName,
    String? hintExt,
  }) async {
    if (raw.isEmpty) return null;
    final ext = (hintExt ?? '').toLowerCase().replaceAll('jpeg', 'jpg');
    final keepPng = ext == 'png' || _isPngBytes(raw);

    if (keepPng && raw.lengthInBytes <= maxBytes) {
      return FinanceComprovanteAttachment(
        bytes: raw,
        fileName: _ensureExtension(fileName, 'png'),
        mimeType: 'image/png',
        alreadyOptimized: true,
      );
    }

    final optimized = await MediaOptimizationService.optimizeForReceipt(raw);
    if (optimized.lengthInBytes > maxBytes) {
      return null;
    }
    return FinanceComprovanteAttachment(
      bytes: optimized,
      fileName: _ensureExtension(fileName, 'jpg'),
      mimeType: 'image/jpeg',
      alreadyOptimized: true,
    );
  }

  static Future<FinanceComprovanteAttachment?> pickFromFiles(
    BuildContext context,
  ) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.financeiro,
    )) {
      return null;
    }
    try {
      final result = await YahwehFilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      if (!context.mounted) return null;

      final f = result.files.single;
      final ext = (f.extension ?? '').toLowerCase();
      if (!_isAllowedExtension(ext)) {
        _showSnack(
          context,
          'Arquivo inválido. Use apenas JPEG, PNG ou PDF (sem vídeo).',
        );
        return null;
      }

      final bytes = f.bytes;
      if (bytes == null || bytes.isEmpty) {
        _showSnack(
          context,
          'Não foi possível ler o arquivo. Tente outro ou um tamanho menor.',
        );
        return null;
      }
      if (bytes.lengthInBytes > maxBytes) {
        _showSnack(context, 'Arquivo grande demais. Limite: 5 MB.');
        return null;
      }

      final mime = _mimeFromExtension(ext);
      if (mime.contains('pdf')) {
        return FinanceComprovanteAttachment(
          bytes: bytes,
          fileName: f.name,
          mimeType: 'application/pdf',
          alreadyOptimized: true,
        );
      }

      final attachment = await _finalizeImageAttachment(
        raw: bytes,
        fileName: f.name,
        hintExt: ext,
      );
      if (attachment == null) {
        _showSnack(context, 'Imagem grande demais. Limite: 5 MB.');
      }
      return attachment;
    } catch (e) {
      _showSnack(
        context,
        'Erro ao selecionar arquivo: ${formatFirebaseErrorForUser(e)}',
      );
      return null;
    }
  }

  static Future<FinanceComprovanteAttachment?> pickFromCamera(
    BuildContext context,
  ) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.financeiro,
    )) {
      return null;
    }
    try {
      final xfile = await MediaHandlerService.instance.pickAndProcessFromCamera(
        module: YahwehMediaModule.financeiro,
        context: context,
      );
      if (xfile == null) return null;
      if (!context.mounted) return null;
      final raw = await xfile.readAsBytes();
      if (raw.isEmpty) {
        _showSnack(context, 'Não foi possível ler a foto da câmera.');
        return null;
      }
      final attachment = await _finalizeImageAttachment(
        raw: raw,
        fileName: xfile.name.isNotEmpty ? xfile.name : 'camera.jpg',
      );
      if (attachment == null) {
        _showSnack(context, 'Foto grande demais. Limite: 5 MB.');
      }
      return attachment;
    } catch (e) {
      _showSnack(
        context,
        'Erro na câmera: ${formatFirebaseErrorForUser(e)}',
      );
      return null;
    }
  }

  static Future<FinanceComprovanteAttachment?> pickFromGallery(
    BuildContext context,
  ) =>
      _pickFromGallery(context);

  /// Folha inferior — Galeria / Câmera / Arquivo (padrão Controle Total).
  static Future<FinanceComprovanteAttachment?> showPickSheet(
    BuildContext context, {
    bool allowCamera = true,
    String title = 'Anexar comprovante',
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottom = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
            boxShadow: ThemeCleanPremium.softUiCardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'JPEG, PNG ou PDF — até 5 MB',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              if (allowCamera)
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Câmera'),
                  subtitle: kIsWeb
                      ? const Text('Tirar foto agora')
                      : const Text('Capturar comprovante'),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeria'),
                subtitle: const Text('Escolher foto JPEG ou PNG'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Arquivo'),
                subtitle: const Text('PDF, JPEG ou PNG no dispositivo'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || choice == null) return null;

    switch (choice) {
      case 'camera':
        return pickFromCamera(context);
      case 'gallery':
        return _pickFromGallery(context);
      case 'file':
      default:
        return pickFromFiles(context);
    }
  }

  static Future<FinanceComprovanteAttachment?> _pickFromGallery(
    BuildContext context,
  ) async {
    if (!await YahwehModuleMediaGate.ensureReadyForPick(
      context: context,
      module: YahwehMediaModule.financeiro,
    )) {
      return null;
    }
    try {
      final xfile = await MediaHandlerService.instance.pickAndProcessFromGallery(
        module: YahwehMediaModule.financeiro,
        context: context,
      );
      if (xfile == null) return null;
      if (!context.mounted) return null;
      final raw = await xfile.readAsBytes();
      if (raw.isEmpty) {
        _showSnack(context, 'Não foi possível ler a imagem.');
        return null;
      }
      final hintExt = xfile.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final attachment = await _finalizeImageAttachment(
        raw: raw,
        fileName: xfile.name.isNotEmpty ? xfile.name : 'galeria.jpg',
        hintExt: hintExt,
      );
      if (attachment == null) {
        _showSnack(context, 'Imagem grande demais. Limite: 5 MB.');
      }
      return attachment;
    } catch (e) {
      _showSnack(
        context,
        'Erro na galeria: ${formatFirebaseErrorForUser(e)}',
      );
      return null;
    }
  }

  static Future<void> viewFromDoc(
    BuildContext context,
    Map<String, dynamic> data,
  ) =>
      FinanceComprovanteViewerSheet.showFromDoc(context, data);
}
