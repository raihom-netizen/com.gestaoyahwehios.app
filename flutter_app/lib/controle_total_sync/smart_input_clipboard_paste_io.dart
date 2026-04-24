import 'dart:async';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';

/// Lê a primeira imagem suportada na área de transferência (Android, iOS, desktop).
Future<Uint8List?> smartInputReadClipboardImageBytesForPaste() async {
  try {
    final clip = SystemClipboard.instance;
    if (clip == null) return null;
    final reader = await clip.read();
    for (final fmt in <FileFormat>[
      Formats.png,
      Formats.jpeg,
      Formats.webp,
      Formats.gif,
      Formats.tiff,
      Formats.heic,
      Formats.bmp,
    ]) {
      final bytes = await _readClipboardImage(reader, fmt);
      if (bytes != null && bytes.isNotEmpty) return bytes;
    }
  } catch (_) {}
  return null;
}

Future<Uint8List?> _readClipboardImage(ClipboardReader reader, FileFormat format) async {
  if (!reader.canProvide(format)) return null;
  final done = Completer<Uint8List?>();
  final progress = reader.getFile(format, (file) async {
    try {
      final b = await file.readAll();
      if (!done.isCompleted) done.complete(b.isEmpty ? null : b);
    } catch (_) {
      if (!done.isCompleted) done.complete(null);
    }
  });
  if (progress == null) return null;
  return done.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      if (!done.isCompleted) done.complete(null);
      return null;
    },
  );
}

/// Colagem por teclado / atalhos é tratada na web; em mobile use [ContentInsertionConfiguration] + botão Colar.
Object? smartInputRegisterWebPasteImageListener(void Function(Uint8List bytes) onImage) => null;

void smartInputUnregisterWebPasteImageListener(Object? handle) {}
