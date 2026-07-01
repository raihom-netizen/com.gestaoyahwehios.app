import 'package:firebase_core/firebase_core.dart';

import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/firebase/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;

/// Bootstrap EcoFire — Firebase + Storage **sempre ligados** antes de upload.
///
/// [strict]: true (default) — nunca engole `core/no-app` nem sessão vazia;
/// a UI mostra erro real em vez de continuar sem Firebase pronto.
abstract final class EcoFirePublishBootstrap {
  EcoFirePublishBootstrap._();

  /// Garante app [DEFAULT] + Storage bucket + Auth antes de upload/gravação.
  static Future<void> ensureHard({
    String logLabel = 'ecofire_publish',
    bool strict = true,
  }) async {
    Object? last;

    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 200 + 240 * attempt),
          );
          if (Firebase.apps.isEmpty) {
            FirebaseBootstrap.reset();
            await FirebaseBootstrap.ensureInitialized();
          } else {
            await EcoFireDirectFirebase.ensureDefaultApp();
          }
        }

        await EcoFireDirectFirebase.ensureForStoragePut(requireAuth: strict);
        if (strict) {
          await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
        }
        return;
      } catch (e) {
        last = e;
        if (attempt < 4 && isFirebaseNoAppError(e)) {
          continue;
        }
        break;
      }
    }

    if (last != null) {
      if (last is Exception) throw last;
      throw StateError(last.toString());
    }

    throw StateError('Firebase indisponível ($logLabel).');
  }
}
