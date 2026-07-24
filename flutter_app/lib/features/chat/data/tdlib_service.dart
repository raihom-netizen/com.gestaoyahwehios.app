/// TDLib / Telegram — stub em todas as plataformas no build de produção.
///
/// Motivo: o pacote `libtdjson` puxa `flutter_libtdjson` no iOS e o binário
/// `libtdjson.a` não está no git (gitignore). Sem download no CI o archive
/// falha. O chat do app é o Yahweh Chat nativo (Firestore).
///
/// Para reativar FFI localmente:
///   1) pubspec: libtdjson: 0.3.0
///   2) dart run tool/setup_tdlib.dart
///   3) export 'tdlib_service_stub.dart' if (dart.library.io) 'tdlib_service_io.dart';
export 'tdlib_service_stub.dart';
