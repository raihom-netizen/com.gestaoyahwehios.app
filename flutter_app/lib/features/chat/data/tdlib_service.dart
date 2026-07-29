/// TDLib / Telegram — motor nativo YAHWEH Chat em mobile, stub na Web.
///
/// O pacote `libtdjson` depende de binários nativos gerados por
/// `dart run tool/setup_tdlib.dart` (Android + iOS). No CI iOS rode
/// `--ios-only` antes do `pod install`. Na Web mantém stub.
library;

export 'tdlib_service_stub.dart' if (dart.library.io) 'tdlib_service_io.dart';
