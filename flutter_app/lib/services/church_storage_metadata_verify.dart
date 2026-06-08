import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Confirma existência de ficheiros no Storage via [Reference.getMetadata].
abstract final class ChurchStorageMetadataVerify {
  ChurchStorageMetadataVerify._();

  static const Duration kDefaultTimeout = Duration(seconds: 15);

  static Future<void> assertExists(
    String storagePath, {
    Duration timeout = kDefaultTimeout,
  }) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw StateError('storagePath vazio — upload não concluído.');
    }
    await firebaseDefaultStorage.ref(path).getMetadata().timeout(timeout);
  }

  static Future<void> assertAllExist(
    Iterable<String> storagePaths, {
    Duration timeout = kDefaultTimeout,
  }) async {
    for (final p in storagePaths) {
      final t = p.trim();
      if (t.isEmpty) continue;
      await assertExists(t, timeout: timeout);
    }
  }
}
