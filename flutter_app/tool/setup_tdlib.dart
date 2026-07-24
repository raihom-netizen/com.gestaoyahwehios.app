// ignore_for_file: avoid_print
/// Setup TDLib multiplataforma (Android + iOS estático).
///
/// Uso (em flutter_app/):
///   dart run tool/setup_tdlib.dart
///   dart run tool/setup_tdlib.dart --android-only
///   dart run tool/setup_tdlib.dart --ios-only
///
/// Na raiz do repo:
///   .\scripts\setup_tdlib.ps1
import 'download_tdlib.dart' as download;

Future<void> main(List<String> args) async {
  print('=== Gestão YAHWEH — setup TDLib (iOS estático + Android) ===');
  print('Detectado: ${DateTime.now().toIso8601String()}');
  await download.main(args);
}
