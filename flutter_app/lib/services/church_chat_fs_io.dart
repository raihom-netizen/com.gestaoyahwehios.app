import 'dart:io' show File;

Future<List<int>> churchChatReadFileBytes(String path) =>
    File(path).readAsBytes();

Future<void> churchChatDeleteFileQuiet(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}
