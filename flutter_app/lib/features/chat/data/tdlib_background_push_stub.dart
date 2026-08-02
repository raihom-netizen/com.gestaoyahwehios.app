import 'package:firebase_messaging/firebase_messaging.dart';

/// Web / sem TDLib nativo.
@pragma('vm:entry-point')
Future<void> tdlibFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {}

abstract final class TdlibBackgroundPushStore {
  TdlibBackgroundPushStore._();

  static Future<void> saveSessionPaths({
    required String churchId,
    required String dbDir,
    required String filesDir,
  }) async {}
}
