import 'package:flutter/foundation.dart';

/// Gate iOS TDLib — produção segura com tentativa automática.
///
/// - Android/macOS: sempre permitido no IO.
/// - iOS: habilitado por defeito; se o linker/plugin falhar no `init`,
///   o motor emite `unsupported` e a UI usa Telegram embutido (paridade).
/// - CI Codemagic pode forçar off com `--dart-define=YAHWEH_TDLIB_IOS_ENABLED=0`
///   (fallback de linker); com `=1` tenta binário estático.
abstract final class TdlibIosGate {
  TdlibIosGate._();

  /// `true` = tentar TDLib nativo no iOS (defeito produção local).
  static const bool iosNativeEnabled = bool.fromEnvironment(
    'YAHWEH_TDLIB_IOS_ENABLED',
    defaultValue: true,
  );

  static bool get shouldAttemptNativeOnIos {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;
    return iosNativeEnabled;
  }
}
