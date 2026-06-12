import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Confirma existência de ficheiros no Storage via [Reference.getMetadata].
abstract final class ChurchStorageMetadataVerify {
  ChurchStorageMetadataVerify._();

  static const Duration kDefaultTimeout = Duration(seconds: 15);
  static const int kMaxAttempts = 6;

  static Future<void> assertExists(
    String storagePath, {
    Duration timeout = kDefaultTimeout,
    int maxAttempts = kMaxAttempts,
  }) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw StateError('storagePath vazio — upload não concluído.');
    }
    Object? last;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await firebaseDefaultStorage
            .ref(path)
            .getMetadata()
            .timeout(timeout);
        return;
      } catch (e) {
        last = e;
        if (attempt >= maxAttempts - 1) break;
        await Future<void>.delayed(
          Duration(milliseconds: 180 + attempt * 220),
        );
      }
    }
    throw last ?? StateError('Ficheiro não confirmado no Storage: $path');
  }

  static Future<void> assertAllExist(
    Iterable<String> storagePaths, {
    Duration timeout = kDefaultTimeout,
    int maxAttempts = kMaxAttempts,
  }) async {
    for (final p in storagePaths) {
      final t = p.trim();
      if (t.isEmpty) continue;
      await assertExists(t, timeout: timeout, maxAttempts: maxAttempts);
    }
  }
}
