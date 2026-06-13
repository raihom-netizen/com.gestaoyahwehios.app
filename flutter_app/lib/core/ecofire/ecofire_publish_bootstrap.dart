import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

import 'package:gestao_yahweh/core/firebase_auth_token_guard.dart';

import 'package:gestao_yahweh/services/app_connectivity_service.dart';

import 'package:gestao_yahweh/utils/firestore_web_guard.dart';



/// Bootstrap Ecofire — Firebase + Storage **sempre ligados** antes de upload.

///

/// Nunca confia só em [FirebaseBootstrapService.isReady] — após resume Android o

/// app [DEFAULT] pode existir no Dart mas o Storage nativo ainda não estar pronto.

abstract final class EcoFirePublishBootstrap {

  EcoFirePublishBootstrap._();



  /// Garante app [DEFAULT] + Storage bucket + Auth antes de upload/gravação.

  static Future<void> ensureHard({String logLabel = 'ecofire_publish'}) async {

    Object? last;

    for (var attempt = 0; attempt < 4; attempt++) {

      try {

        // Prova real de Storage (relink suave se core/no-app após background).

        await FirebaseBootstrapService.ensureStorageAlwaysLinked(

          refreshAuthToken: attempt == 0,

        );

        var user = FirebaseBootstrapService.auth.currentUser;

        if (user == null || user.isAnonymous) {

          await FirebaseAuthTokenGuard.refreshIfStale();

          user = FirebaseBootstrapService.auth.currentUser;

        }

        if (user == null || user.isAnonymous) {

          return;

        }

        if (kIsWeb) {

          await FirestoreWebGuard.prepareForCriticalWrite().catchError((_) {});

        }

        return;

      } catch (e) {

        last = e;

        if (attempt < 3) {

          await Future<void>.delayed(Duration(milliseconds: 280 * (attempt + 1)));

        }

      }

    }

    if (last != null) {

      final low = last.toString().toLowerCase();

      if (!AppConnectivityService.instance.isOnline ||

          low.contains('network') ||

          low.contains('unavailable') ||

          low.contains('core/no-app') ||

          low.contains('no firebase app') ||

          low.contains('indispon')) {

        return;

      }

    }

    throw last ?? StateError('Firebase indisponível ($logLabel).');

  }

}

