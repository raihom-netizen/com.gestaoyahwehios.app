/// TDLib / Telegram — motor nativo YAHWEH Chat em mobile, stub na Web.
///
/// O pacote `libtdjson` esta DESATIVADO (removido do pubspec.yaml — pod iOS
/// flutter_libtdjson falha ao linkar libtdjson.a no Xcode moderno).
/// Fallback automatico para Firestore chat em todas as plataformas.
///
/// Para reativar: descomentar `libtdjson: 0.3.0` no pubspec.yaml e
/// restaurar a linha de export condicional abaixo (if dart.library.io).
library;

// libtdjson DESATIVADO: exportar sempre o stub (Firestore fallback).
// Restaurar quando libtdjson for reativado no pubspec.yaml:
// export 'tdlib_service_stub.dart' if (dart.library.io) 'tdlib_service_io.dart';
export 'tdlib_service_stub.dart';