import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Compacta PDFs em memória para download/compartilhamento único.
class CarteirinhaZipExport {
  CarteirinhaZipExport._();

  /// [entries]: nome do arquivo dentro do ZIP (ex: `carteirinha_abc123.pdf`) → bytes.
  static Uint8List buildZip(Map<String, Uint8List> entries) {
    final archive = Archive();
    for (final e in entries.entries) {
      if (e.key.isEmpty || e.value.isEmpty) continue;
      archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }
}
