import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';

/// Valida Firebase (Auth + Firestore + Storage) antes de publicar aviso/evento/chat/mídia.
Future<void> ensureFirebaseReadyToPublish({String? logLabel}) async {
  await FirebaseBootstrapService.ensureReadyForMediaUpload(force: false);
  final health = await FirebaseBootstrapService.healthCheck(
    requireAuthSession: true,
    logLabel: logLabel,
  );
  if (!health.canPublishMedia) {
    throw StateError(health.summaryForUser);
  }
}
