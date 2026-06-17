import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/utils/firestore_web_guard.dart';

/// Bootstrap Ecofire — Firebase + Storage **sempre ligados** antes de upload.
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
          FirebaseBootstrapService.resetPublishWarmState();
          await Future<void>.delayed(
            Duration(milliseconds: 280 * (attempt + 1)),
          );
        }
        await FirebaseBootstrap.ensureInitialized();
        FirebaseBootstrapService.refreshCachedApp();
        await FirebaseBootstrapService.ensureStorageAlwaysLinked(
          refreshAuthToken: true,
        );

        var user = FirebaseBootstrapService.auth.currentUser;
        if (user == null || user.isAnonymous) {
          await FirebaseAuthTokenGuard.refreshIfStale();
          user = FirebaseBootstrapService.auth.currentUser;
        }

        if (user == null || user.isAnonymous) {
          if (strict) {
            throw StateError(
              'Sessão expirada. Toque em «Trocar de conta» e entre novamente.',
            );
          }
          return;
        }

        if (kIsWeb) {
          await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});
        }

        return;
      } catch (e) {
        last = e;
        if (attempt < 3 && isFirebaseNoAppError(e)) {
          continue;
        }
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
