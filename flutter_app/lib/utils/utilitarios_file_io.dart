import 'package:gestao_yahweh/utils/yahweh_file_picker.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:gestao_yahweh/services/relatorio_service.dart';
import 'utilitarios_web_io_stub.dart'
    if (dart.library.html) 'utilitarios_web_io_web.dart' as web_io;

/// Arquivo escolhido com bytes já carregados (conversores Utilitários).
class UtilitariosPickedFile {
  const UtilitariosPickedFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final Uint8List bytes;
}

bool _isMobileNative() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return true;
    default:
      return false;
  }
}

String _extensionOf(PlatformFile f) {
  var ext = (f.extension ?? '').toLowerCase().trim();
  if (ext == 'jpeg') ext = 'jpg';
  if (ext.isNotEmpty) return ext;
  final name = f.name.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot >= 0 && dot < name.length - 1) {
    ext = name.substring(dot + 1).toLowerCase();
    if (ext == 'jpeg') ext = 'jpg';
    return ext;
  }
  return '';
}

bool _extensionAllowed(String ext, Set<String> allowed) {
  if (ext.isEmpty) return allowed.isEmpty;
  if (allowed.contains(ext)) return true;
  if (ext == 'jpeg' && allowed.contains('jpg')) return true;
  if (ext == 'jpg' && allowed.contains('jpeg')) return true;
  return false;
}

List<PlatformFile> _filterByExtensions(
  List<PlatformFile> files,
  List<String> allowedExtensions,
) {
  if (allowedExtensions.isEmpty) return files;
  final allowed = allowedExtensions.map((e) => e.toLowerCase().trim()).toSet();
  final out = <PlatformFile>[];
  for (final f in files) {
    if (_extensionAllowed(_extensionOf(f), allowed)) out.add(f);
  }
  if (out.isEmpty && files.isNotEmpty) {
    throw StateError(
      'Tipo de arquivo não suportado. Use: ${allowedExtensions.join(', ').toUpperCase()}.',
    );
  }
  return out;
}

/// Abre o seletor de arquivos com leitura confiável no Android/iOS e na web.
///
/// No Android/iOS **não** usa [FileType.custom] (causa `unknown_path` com
/// content://). Padrão do módulo financeiro: [FileType.any] + [withData] e
/// validação de extensão no código.
Future<List<PlatformFile>> utilitariosPickPlatformFiles({
  required List<String> allowedExtensions,
  bool allowMultiple = false,
  FileType type = FileType.custom,
  bool preferBytes = false,
  bool forceStream = false,
}) async {
  try {
    final mobile = _isMobileNative();
    final useAnyPicker = mobile && type == FileType.custom;
    final pickType = useAnyPicker ? FileType.any : type;

    final onlyImages = allowedExtensions.isNotEmpty &&
        allowedExtensions.every(
          (e) => const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'}
              .contains(e.toLowerCase()),
        );

    // Vídeos/arquivos grandes: stream. Mobile arquivo único (PDF etc.): bytes.
    final useBytes = !forceStream &&
        (preferBytes ||
            kIsWeb ||
            (!allowMultiple && mobile) ||
            (allowMultiple && mobile && onlyImages));

    final r = await YahwehFilePicker.pickFiles(
      type: pickType,
      allowedExtensions:
          !useAnyPicker && pickType == FileType.custom && allowedExtensions.isNotEmpty
              ? allowedExtensions
              : null,
      allowMultiple: allowMultiple,
      withData: useBytes,
      withReadStream: !useBytes,
      readSequential: allowMultiple && kIsWeb,
    );
    if (r == null || r.files.isEmpty) return const [];
    return _filterByExtensions(r.files, allowedExtensions);
  } on PlatformException catch (e) {
    throw StateError(utilitariosFormatPickError(e));
  }
}

/// Escolhe um arquivo e devolve bytes + nome (conversores).
Future<UtilitariosPickedFile?> utilitariosPickSingleFileBytes({
  required List<String> allowedExtensions,
  FileType type = FileType.custom,
}) async {
  final files = await utilitariosPickPlatformFiles(
    allowedExtensions: allowedExtensions,
    type: type,
    preferBytes: true,
  );
  if (files.isEmpty) return null;
  final f = files.first;
  final bytes = await utilitariosReadPlatformFileBytes(f);
  if (bytes.isEmpty) {
    throw StateError('Arquivo vazio ou ilegível.');
  }
  final name = f.name.trim().isEmpty ? 'arquivo' : f.name;
  return UtilitariosPickedFile(name: name, bytes: bytes);
}

/// Vários arquivos → lista com bytes.
Future<List<UtilitariosPickedFile>> utilitariosPickMultipleFileBytes({
  required List<String> allowedExtensions,
  bool preferBytes = false,
  FileType type = FileType.custom,
}) async {
  final files = await utilitariosPickPlatformFiles(
    allowedExtensions: allowedExtensions,
    allowMultiple: true,
    type: type,
    preferBytes: preferBytes,
  );
  final out = <UtilitariosPickedFile>[];
  for (final f in files) {
    final bytes = await utilitariosReadPlatformFileBytes(f);
    if (bytes.isEmpty) continue;
    final name = f.name.trim().isEmpty ? 'arquivo_${out.length + 1}' : f.name;
    out.add(UtilitariosPickedFile(name: name, bytes: bytes));
  }
  if (out.isEmpty) {
    throw StateError('Não foi possível ler os arquivos selecionados.');
  }
  return out;
}

String? _normalizePickPath(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('file://')) {
    return Uri.parse(raw).toFilePath(windows: Platform.isWindows);
  }
  return raw;
}

Future<Uint8List> _readPlatformFileStream(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.toBytes();
}

Future<String> _copyBytesToTempFile(Uint8List bytes, String name) async {
  final tmp = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final out = File(
    '${tmp.path}/ct_pick_${DateTime.now().millisecondsSinceEpoch}_$safe',
  );
  await out.writeAsBytes(bytes, flush: true);
  return out.path;
}

/// Salva ou compartilha bytes **localmente** (sem Storage / Cloud).
Future<bool> utilitariosSaveOrShareBytes({
  required BuildContext context,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String shareText = '',
  bool preferShare = false,
}) async {
  final safe = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final ext = safe.contains('.') ? safe.split('.').last.toLowerCase() : 'bin';
  final mime = _normalizeMime(mimeType, ext);

  final isDesktop = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  if (!preferShare) {
    if (kIsWeb) {
      web_io.utilitariosWebDownloadFile(
        bytes: bytes,
        fileName: safe,
        mimeType: mime,
      );
      return true;
    }
    if (isDesktop) {
      final path = await YahwehFilePicker.saveFile(
        dialogTitle: 'Salvar arquivo',
        fileName: safe,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
      if (path == null || path.isEmpty) return false;
      final target =
          path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext';
      await File(target).writeAsBytes(bytes, flush: true);
      return true;
    }
    final baseDir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${baseDir.path}/Utilitarios_GestaoYahweh');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${outDir.path}/${stamp}_$safe';
    await File(path).writeAsBytes(bytes, flush: true);
    if (!context.mounted) return true;
    return true;
  }

  if (!context.mounted) return false;

  if (kIsWeb) {
    return web_io.utilitariosWebShareFile(
      bytes: bytes,
      fileName: safe,
      mimeType: mime,
    );
  }

  final tmp = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final path = '${tmp.path}/ct_share_${stamp}_$safe';
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  if (!await file.exists() || await file.length() == 0) {
    return false;
  }

  if (!context.mounted) return false;
  final origin = RelatorioService.shareOriginFromContext(context);
  final xfile = XFile(path, mimeType: mime, name: safe);
  try {
    final result = await Share.shareXFiles(
      [xfile],
      sharePositionOrigin: origin,
      text: shareText.isEmpty ? null : shareText,
    );
    return result.status != ShareResultStatus.unavailable;
  } catch (_) {
    try {
      await Share.shareXFiles([xfile], text: shareText.isEmpty ? null : shareText);
      return true;
    } catch (_) {
      return false;
    }
  }
}

String _normalizeMime(String mimeType, String ext) {
  final m = mimeType.trim();
  if (m.isNotEmpty && m != 'application/octet-stream') return m;
  return switch (ext) {
    'pdf' => 'application/pdf',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xls' => 'application/vnd.ms-excel',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'mp4' => 'video/mp4',
    'mov' => 'video/quicktime',
    'm4v' => 'video/x-m4v',
    'm4a' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    'zip' => 'application/zip',
    'txt' => 'text/plain',
    _ => m.isEmpty ? 'application/octet-stream' : m,
  };
}

/// Mensagem amigável para erros de leitura/seleção.
String utilitariosFormatPickError(Object e) {
  if (e is PlatformException) {
    if (e.code == 'unknown_path' ||
        (e.message ?? '').toLowerCase().contains('failed to retrieve path')) {
      return 'Não foi possível acessar o arquivo. Salve em Downloads no aparelho e tente de novo.';
    }
    final msg = e.message?.trim();
    if (msg != null && msg.isNotEmpty) return msg;
  }
  final text = e.toString();
  if (text.contains('unknown_path') ||
      text.contains('Failed to retrieve path')) {
    return 'Não foi possível acessar o arquivo. Salve em Downloads no aparelho e tente de novo.';
  }
  if (e is StateError || text.startsWith('Bad state:')) {
    return text.replaceFirst(RegExp(r'^Bad state:\s*'), '');
  }
  return text
      .replaceFirst('StateError: ', '')
      .replaceFirst('PlatformException(', '')
      .replaceFirst(RegExp(r'\)$'), '');
}

/// Lê bytes de um [PlatformFile] de forma confiável no Android/iOS/web.
///
/// **Não** usa [PlatformFile.xFile] — no Android isso dispara `unknown_path`.
Future<Uint8List> utilitariosReadPlatformFileBytes(PlatformFile f) async {
  if (f.bytes != null && f.bytes!.isNotEmpty) {
    return f.bytes!;
  }

  final stream = f.readStream;
  if (stream != null) {
    try {
      final fromStream = await _readPlatformFileStream(stream);
      if (fromStream.isNotEmpty) return fromStream;
    } catch (_) {
      // tenta path abaixo
    }
  }

  if (!kIsWeb) {
    final path = _normalizePickPath(f.path);
    if (path != null && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) return bytes;
        }
      } catch (_) {}
    }
  }

  if (kIsWeb) {
    final path = _normalizePickPath(f.path);
    if (path != null && path.isNotEmpty) {
      try {
        final raw = await XFile(path).readAsBytes();
        if (raw.isNotEmpty) {
          return Uint8List.fromList(raw);
        }
      } catch (_) {}
    }
    throw StateError(
      'Não foi possível ler o arquivo no navegador. Tente outro arquivo ou use o app no celular.',
    );
  }

  throw StateError(
    'Não foi possível ler o arquivo. Salve em Downloads no aparelho e tente de novo.',
  );
}

/// Caminho local confiável para vídeos/arquivos grandes (Android/iOS).
Future<String> utilitariosResolvePlatformFilePath(PlatformFile f) async {
  if (f.bytes != null && f.bytes!.isNotEmpty) {
    return _copyBytesToTempFile(f.bytes!, f.name);
  }

  final path = _normalizePickPath(f.path);
  if (path != null && path.isNotEmpty && !kIsWeb) {
    try {
      final file = File(path);
      if (await file.exists() && await file.length() > 0) return path;
    } catch (_) {}
  }

  final stream = f.readStream;
  if (stream != null && !kIsWeb) {
    try {
      final tmp = await getTemporaryDirectory();
      final safe = f.name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final out = File(
        '${tmp.path}/ct_pick_${DateTime.now().microsecondsSinceEpoch}_$safe',
      );
      final sink = out.openWrite();
      await stream.pipe(sink);
      await sink.flush();
      await sink.close();
      if (await out.exists() && await out.length() > 0) return out.path;
    } catch (_) {}
  }

  final bytes = await utilitariosReadPlatformFileBytes(f);
  return _copyBytesToTempFile(bytes, f.name);
}

/// Tamanho em bytes no disco (mobile/desktop).
Future<int> utilitariosFileSizeAtPath(String path) async {
  final file = File(path);
  if (!await file.exists()) return 0;
  return file.length();
}
