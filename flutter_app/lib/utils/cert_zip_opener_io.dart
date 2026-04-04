import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// Grava o ZIP em disco, abre com o app padrão e devolve o caminho para [Share].
Future<String?> writeCertZipAndOpen(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$filename';
  final f = File(path);
  await f.writeAsBytes(bytes);
  await OpenFilex.open(path);
  return path;
}
