import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/entity_publish_status.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/finance_comprovante_publish_service.dart';
import 'package:gestao_yahweh/services/image_helper.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/utils/pdf_actions_helper.dart';
import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';
import 'package:image_picker/image_picker.dart';

/// Comprovante financeiro — seleção e visualização (padrão Controle Total).
class FinanceComprovanteAttachment {
  const FinanceComprovanteAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  bool get isPdf => mimeType.contains('pdf');
  bool get isImage => mimeType.startsWith('image/');
}

abstract final class FinanceComprovanteAttachService {
  FinanceComprovanteAttachService._();

  static const int maxBytes = 5 * 1024 * 1024;
  static const List<String> allowedExtensions = ['jpg', 'jpeg', 'png', 'pdf'];

  static bool hasComprovanteInDoc(Map<String, dynamic> data) {
    if (data['hasComprovante'] == true) return true;
    final url = (data['comprovanteUrl'] ?? '').toString().trim();
    final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
    if (url.isNotEmpty || path.isNotEmpty) return true;
    final state = (data['comprovanteUploadState'] ?? '').toString();
    return state == EntityPublishStatus.published;
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

  static String _mimeFromExtension(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  static bool _isAllowedExtension(String ext) {
    final e = ext.toLowerCase().replaceAll('jpeg', 'jpg');
    return e == 'jpg' || e == 'png' || e == 'pdf';
  }

  static void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Galeria / arquivo — JPEG, PNG ou PDF (até 5 MB).
  static Future<FinanceComprovanteAttachment?> pickFromFiles(
    BuildContext context,
  ) async {
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
          'Arquivo inválido. Use apenas JPEG, PNG ou PDF.',
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

      final mime = _mimeFromExtension(ext.replaceAll('jpeg', 'jpg'));
      return FinanceComprovanteAttachment(
        bytes: bytes,
        fileName: f.name,
        mimeType: mime,
      );
    } catch (e) {
      _showSnack(
        context,
        'Erro ao selecionar arquivo: ${e.toString().split('\n').first}',
      );
      return null;
    }
  }

  /// Câmera — foto JPEG.
  static Future<FinanceComprovanteAttachment?> pickFromCamera(
    BuildContext context,
  ) async {
    if (kIsWeb) return null;
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (xfile == null) return null;
      if (!context.mounted) return null;
      final bytes = await xfile.readAsBytes();
      if (bytes.isEmpty) {
        _showSnack(context, 'Não foi possível ler a foto da câmera.');
        return null;
      }
      if (bytes.lengthInBytes > maxBytes) {
        _showSnack(context, 'Foto grande demais. Limite: 5 MB.');
        return null;
      }
      return FinanceComprovanteAttachment(
        bytes: bytes,
        fileName: xfile.name,
        mimeType: 'image/jpeg',
      );
    } catch (e) {
      _showSnack(
        context,
        'Erro na câmera: ${e.toString().split('\n').first}',
      );
      return null;
    }
  }

  /// Folha: câmera (mobile) ou arquivo.
  static Future<FinanceComprovanteAttachment?> showPickSheet(
    BuildContext context, {
    bool allowCamera = true,
    String title = 'Anexar comprovante',
  }) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusLg),
        ),
        title: Text(title),
        children: [
          if (allowCamera && !kIsWeb)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'camera'),
              child: const Row(
                children: [
                  Icon(Icons.camera_alt_rounded),
                  SizedBox(width: 12),
                  Text('Câmera'),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'file'),
            child: const Row(
              children: [
                Icon(Icons.attach_file_rounded),
                SizedBox(width: 12),
                Text('Arquivo (JPEG, PNG ou PDF)'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'gallery'),
            child: const Row(
              children: [
                Icon(Icons.photo_library_rounded),
                SizedBox(width: 12),
                Text('Galeria de fotos'),
              ],
            ),
          ),
        ],
      ),
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
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (xfile == null) return null;
      if (!context.mounted) return null;
      final bytes = await xfile.readAsBytes();
      if (bytes.isEmpty) {
        _showSnack(context, 'Não foi possível ler a imagem.');
        return null;
      }
      if (bytes.lengthInBytes > maxBytes) {
        _showSnack(context, 'Imagem grande demais. Limite: 5 MB.');
        return null;
      }
      final lower = xfile.name.toLowerCase();
      final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
      return FinanceComprovanteAttachment(
        bytes: bytes,
        fileName: xfile.name,
        mimeType: mime,
      );
    } catch (e) {
      _showSnack(
        context,
        'Erro na galeria: ${e.toString().split('\n').first}',
      );
      return null;
    }
  }

  /// Comprime imagens; PDF passa direto.
  static Future<({Uint8List bytes, String mimeType})> prepareUploadBytes(
    FinanceComprovanteAttachment attachment,
  ) async {
    if (attachment.isPdf) {
      return (bytes: attachment.bytes, mimeType: attachment.mimeType);
    }
    final compressed = await ImageHelper.compressImage(
      attachment.bytes,
      minWidth: 1200,
      minHeight: 900,
      quality: 82,
    );
    final mime = attachment.mimeType.contains('png')
        ? 'image/png'
        : 'image/jpeg';
    return (bytes: compressed, mimeType: mime);
  }

  static String extensionForMime(String mimeType) =>
      EcoFireImageProcess.extensionFromMime(mimeType);

  /// Abre comprovante já gravado (imagem ou PDF).
  static Future<void> viewFromDoc(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    if (!hasComprovanteInDoc(data)) {
      _showSnack(context, 'Este lançamento não tem comprovante.');
      return;
    }
    final mime = mimeFromDoc(data);
    final fileName = displayNameFromDoc(data);

    if (mime.contains('pdf')) {
      await _viewPdf(context, data, fileName);
      return;
    }

    final url =
        await FinanceComprovantePublishService.resolveComprovanteUrl(data);
    if (!context.mounted) return;
    if (url.isEmpty) {
      _showSnack(context, 'Não foi possível abrir o comprovante.');
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(fileName),
            backgroundColor: ThemeCleanPremium.primary,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              child: SafeNetworkImage(
                imageUrl: url,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _viewPdf(
    BuildContext context,
    Map<String, dynamic> data,
    String fileName,
  ) async {
    try {
      await ensureFirebaseCore(requireAuth: false);
      final path = (data['comprovanteStoragePath'] ?? '').toString().trim();
      Uint8List? bytes;
      if (path.isNotEmpty) {
        bytes = await firebaseDefaultStorage.ref(path).getData(maxBytes);
      }
      if ((bytes == null || bytes.isEmpty) &&
          (data['comprovanteUrl'] ?? '').toString().trim().isNotEmpty) {
        final url =
            await FinanceComprovantePublishService.resolveComprovanteUrl(data);
        if (url.isNotEmpty) {
          bytes = await firebaseDefaultStorage.refFromURL(url).getData(maxBytes);
        }
      }
      if (!context.mounted) return;
      if (bytes == null || bytes.isEmpty) {
        _showSnack(context, 'Não foi possível carregar o PDF.');
        return;
      }
      await showPdfActions(context, bytes: bytes, filename: fileName);
    } catch (e) {
      if (context.mounted) {
        _showSnack(
          context,
          'Erro ao abrir PDF: ${e.toString().split('\n').first}',
        );
      }
    }
  }
}
