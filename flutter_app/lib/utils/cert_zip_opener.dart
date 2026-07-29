import 'dart:typed_data';

import 'cert_zip_opener_stub.dart'
    if (dart.library.io) 'cert_zip_opener_io.dart' as opener;

/// Android/iOS/desktop: grava, abre com [OpenFilex] e retorna path. Web: null.
Future<String?> writeCertZipAndOpen(Uint8List bytes, String filename) =>
    opener.writeCertZipAndOpen(bytes, filename);
