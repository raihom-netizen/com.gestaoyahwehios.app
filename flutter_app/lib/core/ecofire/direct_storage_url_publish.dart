import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_storage_upload.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart'
    show isFirebaseNoAppError;
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Upload direto Storage → URL https — padrão Wisdom / Controle Total / EcoFire.
///
/// 1. `putData` no bucket (`igrejas/{churchId}/…`)
/// 2. `getDownloadURL` após upload
/// 3. Gravar URL no Firestore (painel, chat, site público)
abstract final class DirectStorageUrlPublish {
  DirectStorageUrlPublish._();

  /// Firebase + Auth + Storage prontos — **sem** reset destrutivo (anti core/no-app).
  static Future<void> ensureReady({
    bool requireAuth = true,
    int maxAttempts = 5,
  }) async {
    Object? last;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(
            Duration(milliseconds: 100 + 100 * attempt),
          );
          await EcoFireDirectFirebase.ensureDefaultApp();
        }
        await EcoFireDirectFirebase.ensureForStoragePut(
          requireAuth: requireAuth,
        );
        return;
      } catch (e) {
        last = e;
        if (attempt < maxAttempts - 1 && isFirebaseNoAppError(e)) {
          continue;
        }
        rethrow;
      }
    }
    if (last != null) {
      if (last is Exception) throw last;
      throw StateError(last.toString());
    }
    throw StateError('Firebase Storage indisponível.');
  }

  /// Envia bytes e devolve URL https pronta para Firestore/UI.
  static Future<String> uploadBytes({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
    bool requireAuth = true,
    void Function(UploadTask task)? onUploadTaskCreated,
  }) async {
    await ensureReady(requireAuth: requireAuth);
    return EcoFireStorageUpload.putData(
      storagePath: storagePath,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
      onUploadTaskCreated: onUploadTaskCreated,
    );
  }

  /// Resolve URL de objeto já existente no Storage (retry curto).
  static Future<String> resolveUrl(String storagePath) async {
    final path = storagePath.trim();
    if (path.isEmpty) {
      throw ArgumentError('storagePath vazio.');
    }
    final ref = firebaseDefaultStorage.ref(path);
    return storageDownloadUrlWithRetry(ref);
  }
}
