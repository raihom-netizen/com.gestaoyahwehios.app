import 'package:gestao_yahweh/core/app_finalize_bootstrap.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart'
    show FirebaseBootstrapException, FirebaseBootstrapService;
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';

/// Bootstrap Storage antes de anexar (avisos, eventos, património, perfil).
abstract final class ImmediateStorageUploadGuard {
  ImmediateStorageUploadGuard._();

  static Future<void> ensureReady({String debugLabel = 'immediate_attach'}) async {
    await AppFinalizeBootstrap.ensureSessionForPublish(
      logLabel: debugLabel,
    );
    await ensureFirebaseReadyForMediaUpload();
    await EcoFirePublishBootstrap.ensureHard(logLabel: debugLabel);
  }

  static Never rethrowAsUserError(Object e, StackTrace st) {
    if (e is FirebaseBootstrapException) {
      Error.throwWithStackTrace(e, st);
    }
    throw FirebaseBootstrapException.from(
      StateError(formatFirebaseErrorForUser(e)),
      st,
    );
  }
}
