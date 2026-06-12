import 'dart:async' show TimeoutException, unawaited;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';

/// Resolve mídia do chat **somente** via [storagePath] — nunca persiste download URL.
abstract final class ChurchChatMediaResolver {
  ChurchChatMediaResolver._();

  static const Duration mediaTimeout = Duration(seconds: 15);

  static final Map<String, _CachedUrl> _urlCache = {};

  static String normalizePath(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return '';
    if (t.toLowerCase().startsWith('gs://')) {
      final idx = t.indexOf('/o/');
      if (idx > 0) return Uri.decodeFull(t.substring(idx + 3).split('?').first);
    }
    return t.replaceAll('\\', '/');
  }

  /// Verifica existência no bucket antes de exibir.
  static Future<bool> objectExists(String? storagePath) async {
    final path = normalizePath(storagePath);
    if (path.isEmpty) return false;
    try {
      await _ref(path).getMetadata().timeout(mediaTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Gera URL de download na hora (com cache curto em memória).
  static Future<String?> resolveDownloadUrl({
    required String? storagePath,
    String? tenantId,
    String? messageId,
    bool forceRefresh = false,
    bool fastPreview = false,
  }) async {
    final path = normalizePath(storagePath);
    if (path.isEmpty) return null;

    if (!forceRefresh) {
      final hit = _urlCache[path];
      if (hit != null && !hit.isExpired) return hit.url;
    }

    try {
      await ensureFirebaseReadyForMediaUpload();
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage().catchError((_) {});
      }
      final ref = _ref(path);
      if (!fastPreview) {
        await ref.getMetadata().timeout(mediaTimeout);
      }
      final url = await ref.getDownloadURL().timeout(
            fastPreview ? const Duration(seconds: 8) : mediaTimeout,
          );
      if (url.trim().isEmpty) return null;
      _urlCache[path] = _CachedUrl(url.trim(), DateTime.now());
      return url.trim();
    } catch (e, st) {
      unawaited(
        SystemLogService.record(
          module: 'chat',
          message: 'falha ao resolver storagePath',
          tenantId: tenantId,
          error: e,
          stackTrace: st,
          severity: 'warn',
          extra: {
            'messageId': messageId ?? '',
            'storagePath': path,
          },
        ),
      );
      if (kDebugMode) {
        debugPrint('ChurchChatMediaResolver: $path → $e');
      }
      return null;
    }
  }

  static void forgetPath(String? storagePath) {
    final path = normalizePath(storagePath);
    if (path.isNotEmpty) _urlCache.remove(path);
  }

  static Reference _ref(String path) => firebaseDefaultStorage.ref(path);
}

class _CachedUrl {
  _CachedUrl(this.url, this.at);
  final String url;
  final DateTime at;
  static const _ttl = Duration(minutes: 25);
  bool get isExpired => DateTime.now().difference(at) > _ttl;
}
