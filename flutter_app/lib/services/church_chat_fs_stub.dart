import 'package:cross_file/cross_file.dart';

/// Web: lê bytes via [XFile] (blob/path do picker).
Future<List<int>> churchChatReadFileBytes(String path) async {
  final p = path.trim();
  if (p.isEmpty) return <int>[];
  try {
    return await XFile(p).readAsBytes();
  } catch (_) {
    return <int>[];
  }
}

Future<void> churchChatDeleteFileQuiet(String path) async {}
