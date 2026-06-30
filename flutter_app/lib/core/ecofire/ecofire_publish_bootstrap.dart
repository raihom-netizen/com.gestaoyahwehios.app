import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/firebase/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/app_connectivity_service.dart';

/// Bootstrap EcoFire — Firebase + Storage **sempre ligados** antes de upload.
///
/// [strict]: quando true (avisos/eventos com fotos), nunca engole `core/no-app`
/// nem sessão vazia — a UI deve mostrar erro real, não sucesso falso.
abstract final class EcoFirePublishBootstrap {
  EcoFirePublishBootstrap._();

  static bool _isRecoverableForQueue(Object error) {
    if (!AppConnectivityService.instance.isOnline) return true;
    final low = error.toString().toLowerCase();
    return low.contains('network') ||
        low.contains('unavailable') ||
        low.contains('core/no-app') ||
        low.contains('no firebase app') ||
        low.contains('indispon');
  }

  /// Garante app [DEFAULT] + Storage bucket + Auth antes de upload/gravação.
  static Future<void> ensureHard({
    String logLabel = 'ecofire_publish',
    bool strict = false,
  }) async {
    Object? last;

    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 240 * (attempt + 1)),
          );
          await FirebaseBootstrap.ensureInitialized();
        }

        await EcoFireDirectFirebase.ensureForStoragePut(requireAuth: strict);
        if (kIsWeb && strict) {
          await EcoFireDirectFirebase.ensureForFirestoreWrite(requireAuth: true);
        }
        return;
      } catch (e) {
        last = e;
        if (attempt < 3 && isFirebaseNoAppError(e)) {
          continue;
        }
        if (!strict && _isRecoverableForQueue(e)) {
          return;
        }
        break;
      }
    }

    if (last != null) {
      if (_isRecoverableForQueue(last) && !strict) {
        return;
      }
      if (last is Exception) throw last;
      throw StateError(last.toString());
    }

    throw StateError('Firebase indisponível ($logLabel).');
  }
}
