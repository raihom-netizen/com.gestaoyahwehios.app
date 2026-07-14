import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_image_process.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_direct_firebase.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_publish_bootstrap.dart';
import 'package:gestao_yahweh/core/storage_upload_metadata.dart';
import 'package:gestao_yahweh/core/tenant/legacy_path_guard.dart';
import 'package:gestao_yahweh/services/upload_storage_task.dart';

/// Upload directo Storage → URL — port 1:1 do EcoFire `StorageUploadService`,
/// com paths canónicos `igrejas/{churchId}/…` do Gestão YAHWEH.
abstract final class EcoFireStorageUpload {
  EcoFireStorageUpload._();

  static const int _maxAttempts = 3;

  static Future<String> putData({
    required String storagePath,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
    void Function(UploadTask task)? onUploadTaskCreated,
  }) async {
    LegacyPathGuard.assertCanonicalStoragePath(
      storagePath,
      context: 'EcoFireStorageUpload.putData',
    );
    EcoFireFlow.log('STORAGE putData $storagePath');
    await EcoFireDirectFirebase.ensureForStoragePut();

    Object? lastError;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(seconds: attempt));
          await EcoFireDirectFirebase.ensureForStoragePut();
        }
        final ref = await EcoFireDirectFirebase.storageRef(storagePath);
        final ct = StorageUploadMetadata.contentTypeForPut(
          contentType: mimeType,
          storagePath: storagePath,
        );
        final task = ref.putData(
          bytes,
          SettableMetadata(
            contentType: ct,
            cacheControl: StorageUploadMetadata.cacheControl,
          ),
        );
        onUploadTaskCreated?.call(task);
        final snap = await awaitStorageUploadTask(
          task,
          payloadBytes: bytes.length,
          onProgress: onProgress,
        );
        final url = await storageDownloadUrlWithRetry(snap.ref);
        EcoFireFlow.log('STORAGE OK $storagePath');
        return url;
      } catch (e) {
        lastError = e;
        EcoFireFlow.log('STORAGE retry $attempt: $e');
        if (attempt < _maxAttempts - 1) {
          try {
            await EcoFireDirectFirebase.ensureDefaultApp();
          } catch (_) {}
        }
      }
    }
    throw lastError ?? StateError('storage_upload_failed:$storagePath');
  }

  /// Logo igreja — sobrescreve `configuracoes/logo_igreja.png`.
  static Future<({String url, String storagePath})> uploadChurchLogo({
    required String churchId,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final path = ChurchStorageLayout.churchIdentityLogoPath(churchId);
    final url = await putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return (url: url, storagePath: path);
  }

  /// Foto perfil membro — único ficheiro `membros/{id}/foto_perfil.jpg`.
  static Future<({String url, String storagePath, String? thumbUrl})>
      uploadMemberProfile({
    required String churchId,
    required String memberId,
    required Uint8List fullBytes,
    required String mimeType,
    Uint8List? thumbBytes,
    void Function(double progress)? onProgress,
  }) async {
    final path = ChurchStorageLayout.memberProfilePhotoPath(churchId, memberId);
    final url = await putData(
      storagePath: path,
      bytes: fullBytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return (url: url, storagePath: path, thumbUrl: url);
  }

  static Future<({String url, String storagePath})> uploadAvisoPhoto({
    required String churchId,
    required String postId,
    required int slotIndex,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final path =
        ChurchStorageLayout.avisoPostPhotoPath(churchId, postId, slotIndex);
    final url = await putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return (url: url, storagePath: path);
  }

  static Future<({String url, String storagePath})> uploadEventoPhoto({
    required String churchId,
    required String postId,
    required int slotIndex,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final path =
        ChurchStorageLayout.eventPostPhotoPath(churchId, postId, slotIndex);
    final url = await putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return (url: url, storagePath: path);
  }

  static Future<({String url, String storagePath})> uploadPatrimonioPhoto({
    required String churchId,
    required String itemId,
    required int slotIndex,
    required Uint8List bytes,
    required String mimeType,
    void Function(double progress)? onProgress,
  }) async {
    final path =
        ChurchStorageLayout.patrimonioPhotoPath(churchId, itemId, slotIndex);
    final url = await putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return (url: url, storagePath: path);
  }

  static Future<({String url, String storagePath})> uploadFinanceComprovante({
    required String churchId,
    required String lancamentoId,
    required Uint8List bytes,
    required String mimeType,
    DateTime? referenceDate,
    void Function(double progress)? onProgress,
  }) async {
    final ext = EcoFireImageProcess.extensionFromMime(mimeType);
    final path = ChurchStorageLayout.financeComprovantePath(
      tenantId: churchId,
      lancamentoId: lancamentoId,
      referenceDate: referenceDate,
      ext: ext,
    );
    final url = await putData(
      storagePath: path,
      bytes: bytes,
      mimeType: mimeType,
      onProgress: onProgress,
    );
    return (url: url, storagePath: path);
  }

  /// Fallback EcoFire: resolve URL quando Firestore não tem https válido.
  static Future<String?> downloadUrlFromStoragePath(String? storagePath) async {
    final p = (storagePath ?? '').trim();
    if (p.isEmpty || p.startsWith('http')) return null;
    try {
      await EcoFirePublishBootstrap.ensureHard(
        logLabel: 'storage_download_url',
        strict: false,
      );
      return await (await EcoFireDirectFirebase.storageRef(p)).getDownloadURL();
    } catch (_) {}
    return null;
  }

  /// Fallback logo — tenta paths canónicos da igreja.
  static Future<String?> churchLogoFallback(
    String churchId, {
    String? churchName,
  }) async {
    for (final path in ChurchStorageLayout.churchLogoObjectPathsToTry(
      churchId,
      churchName,
    )) {
      final url = await downloadUrlFromStoragePath(path);
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// Fallback foto membro — canónico + legado `foto_perfil.jpg`.
  static Future<String?> memberPhotoFallback(
    String churchId,
    String memberId,
  ) async {
    final paths = <String>[
      ChurchStorageLayout.memberProfilePhotoPath(churchId, memberId),
      ChurchStorageLayout.memberProfileThumbPath(churchId, memberId),
      ChurchStorageLayout.memberCanonicalProfilePhotoPathLegacy(
        churchId,
        memberId,
      ),
    ];
    for (final path in paths) {
      final url = await downloadUrlFromStoragePath(path);
      if (url != null && url.isNotEmpty) return url;
    }
    try {
      final prefix = ChurchStorageLayout.memberProfilePhotoPath(churchId, memberId)
          .split('/')
          .last
          .replaceAll('.webp', '');
      final folder = await EcoFireDirectFirebase.storageRef(
        '${ChurchStorageLayout.churchRoot(churchId)}/${ChurchStorageLayout.kSegMembros}/fotos',
      );
      final list = await folder.listAll();
      for (final item in list.items) {
        if (item.name.startsWith(prefix)) {
          return item.getDownloadURL();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fallback aviso/evento — tenta extensões comuns no path base.
  static Future<String?> postPhotoFallback(String storagePathBase) async {
    final base = storagePathBase.trim();
    if (base.isEmpty) return null;
    for (final ext in ['webp', 'jpg', 'jpeg', 'png']) {
      final url = await downloadUrlFromStoragePath('$base.$ext');
      if (url != null && url.isNotEmpty) return url;
    }
    if (base.contains('.')) {
      return downloadUrlFromStoragePath(base);
    }
    return null;
  }
}
