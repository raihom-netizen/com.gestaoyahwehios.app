import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';

/// Valida Firebase (sessão + núcleo) antes de publicar aviso/evento/mídia.
Future<void> ensureFirebaseReadyToPublish({String? logLabel}) async {
  await FirebaseBootstrapService.ensureReadyForPublishUpload();
}
