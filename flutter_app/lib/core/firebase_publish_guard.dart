import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';

/// Valida Firebase (sessão + núcleo + Storage ligado) antes de publicar aviso/evento/mídia.
Future<void> ensureFirebaseReadyToPublish({String? logLabel}) async {
  await FirebaseBootstrapService.ensureStorageAlwaysLinked(
    refreshAuthToken: true,
    maxAttempts: 5,
  );
}
