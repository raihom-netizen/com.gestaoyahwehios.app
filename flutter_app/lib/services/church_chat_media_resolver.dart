import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/services/system_log_service.dart';

/// Resolve mídia do chat **somente** via [storagePath] — nunca persiste download URL.
abstract final class ChurchChatMediaResolver {
  ChurchChatMediaResolver._();

  static const Duration mediaTimeout = Duration(seconds: 12);
  static const int kMaxInlineDownloadBytes = 6 * 1024 * 1024;

  static final Map<String, _CachedUrl> _urlCache = {};

  static String normalizePath(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return '';
    if (t.toLowerCase().startsWith('gs://')) {
      final idx = t.indexOf('/o/');
      if (idx > 0) return Uri.decodeFull(t.substring(idx + 3).split('?').first);
      final slash = t.indexOf('/', 5);
      if (slash > 0 && slash < t.length - 1) {
        return t.substring(slash + 1);
      }
    }
    if (t.contains('firebasestorage.googleapis.com') ||
        t.contains('firebasestorage.app')) {
      return StorageMediaService.normalizeFirestoreStoragePath(t) ?? t;
    }
    return t.replaceAll('\\', '/');
  }

  /// Verifica existência no bucket (diagnóstico — não usar na UI quente).
  static Future<bool> objectExists(String? storagePath) async {
    final path = normalizePath(storagePath);
    if (path.isEmpty) return false;
    try {
      await firebaseDefaultStorage.ref(path).getMetadata().timeout(mediaTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// URL de download na hora (cache curto). **Sem** getMetadata bloqueante.
  static Future<String?> resolveDownloadUrl({
    required String? storagePath,
    String? tenantId,
    String? messageId,
    bool forceRefresh = false,
    bool fastPreview = true,
  }) async {
    final path = normalizePath(storagePath);
    if (path.isEmpty) return null;

    if (!forceRefresh) {
      final hit = _urlCache[path];
      if (hit != null && !hit.isExpired) return hit.url;
    }

    try {
      await ensureFirebaseCore(requireAuth: true);
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage().catchError((_) {});
      }
      final url = await StorageMediaService.downloadUrlFromPathOrUrl(path)
          .timeout(
            fastPreview ? const Duration(seconds: 10) : mediaTimeout,
            onTimeout: () => null,
          );
      if (url == null || url.trim().isEmpty) return null;
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

  /// Baixa bytes do objeto (PDF preview, partilha) — até [maxBytes].
  static Future<Uint8List?> downloadBytes({
    required String? storagePath,
    int maxBytes = kMaxInlineDownloadBytes,
  }) async {
    final path = normalizePath(storagePath);
    if (path.isEmpty) return null;
    try {
      await ensureFirebaseCore(requireAuth: true);
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage().catchError((_) {});
      }
      final data = await firebaseDefaultStorage
          .ref(path)
          .getData(maxBytes)
          .timeout(const Duration(seconds: 14));
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }

  static void forgetPath(String? storagePath) {
    final path = normalizePath(storagePath);
    if (path.isNotEmpty) _urlCache.remove(path);
  }
}

class _CachedUrl {
  _CachedUrl(this.url, this.at);
  final String url;
  final DateTime at;
  static const _ttl = Duration(minutes: 25);
  bool get isExpired => DateTime.now().difference(at) > _ttl;
}
