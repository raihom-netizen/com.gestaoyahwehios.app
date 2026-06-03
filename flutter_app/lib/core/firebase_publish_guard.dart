import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Valida Firebase (sessão + núcleo) antes de publicar aviso/evento/mídia.
Future<void> ensureFirebaseReadyToPublish({String? logLabel}) async {
  await ensureFirebaseCore(requireAuth: true);
}
