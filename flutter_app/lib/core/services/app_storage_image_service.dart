import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        churchTenantLogoUrl,
        firebaseStorageDownloadUrlLooksTokenized,
        firebaseStorageMediaUrlLooksLike,
        isValidImageUrl,
        normalizeFirebaseStorageObjectPath,
        sanitizeImageUrl;

/// Resolução centralizada de URLs exibíveis (Storage path, gs://, https).
/// Memoiza futures por chave e permite invalidação após upload.
class AppStorageImageService {
  AppStorageImageService._();
  static final AppStorageImageService instance = AppStorageImageService._();

  final Map<String, Future<String?>> _pending = {};
  final Map<String, String?> _resolved = {};

  static String _norm(String? s) => (s ?? '')
      .trim()
      .replaceAll('\\', '/')
      .replaceAll(RegExp(r'^\s+|\s+$'), '');

  /// Chave estável independente da ordem dos argumentos não usados.
  static String cacheKey({
    String? storagePath,
    String? imageUrl,
    String? gsUrl,
  }) {
    return '${_norm(storagePath)}§${_norm(gsUrl)}§${_norm(imageUrl)}';
  }

  Future<T?> _twice<T>(Future<T?> Function() op) async {
    try {
      return await op();
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      try {
        return await op();
      } catch (_) {
        return null;
      }
    }
  }

  Future<String?> _resolveUncached({
    String? storagePath,
    String? imageUrl,
    String? gsUrl,
  }) async {
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    final g = _norm(gsUrl);
    if (g.toLowerCase().startsWith('gs://')) {
      final out = await _twice(() async {
        final ref = FirebaseStorage.instance.refFromURL(g);
        final u =
            await ref.getDownloadURL().timeout(const Duration(seconds: 15));
        final s = sanitizeImageUrl(u);
        return isValidImageUrl(s) ? s : null;
      });
      if (out != null) return out;
    }

    final p = _norm(storagePath);
    if (p.isNotEmpty) {
      final out = await _twice(() async {
        final ref = FirebaseStorage.instance.ref(p);
        final u =
            await ref.getDownloadURL().timeout(const Duration(seconds: 15));
        final s = sanitizeImageUrl(u);
        return isValidImageUrl(s) ? s : null;
      });
      if (out != null) return out;
    }

    final u = _norm(imageUrl);
    if (u.isEmpty) return null;
    final s = sanitizeImageUrl(u);
    // Clientes às vezes gravam gs:// ou caminho `igrejas/...` em campos de "URL".
    if (s.toLowerCase().startsWith('gs://')) {
      final outGs = await _twice(() async {
        final ref = FirebaseStorage.instance.refFromURL(s);
        final uu =
            await ref.getDownloadURL().timeout(const Duration(seconds: 15));
        final fresh = sanitizeImageUrl(uu);
        return isValidImageUrl(fresh) ? fresh : null;
      });
      if (outGs != null) return outGs;
    } else if (!s.startsWith('http://') &&
        !s.startsWith('https://') &&
        firebaseStorageMediaUrlLooksLike(s)) {
      final bare =
          normalizeFirebaseStorageObjectPath(s.replaceFirst(RegExp(r'^/+'), ''));
      if (bare.isNotEmpty) {
        final outPath = await _twice(() async {
          final ref = FirebaseStorage.instance.ref(bare);
          final uu =
              await ref.getDownloadURL().timeout(const Duration(seconds: 15));
          final fresh = sanitizeImageUrl(uu);
          return isValidImageUrl(fresh) ? fresh : null;
        });
        if (outPath != null) return outPath;
      }
    }
    if (!isValidImageUrl(s)) return null;
    if (StorageMediaService.isFirebaseStorageMediaUrl(s)) {
      if (firebaseStorageDownloadUrlLooksTokenized(s)) {
        return s;
      }
      return _twice(() async {
        final r = await StorageMediaService.freshPlayableMediaUrl(s)
            .timeout(const Duration(seconds: 28));
        return r;
      });
    }
    return s;
  }

  /// Resolve para uma URL https exibível (token renovado quando aplicável).
  Future<String?> resolveImageUrl({
    String? storagePath,
    String? imageUrl,
    String? gsUrl,
  }) async {
    if (_norm(storagePath).isEmpty &&
        _norm(gsUrl).isEmpty &&
        _norm(imageUrl).isEmpty) {
      return null;
    }
    final key = cacheKey(
      storagePath: storagePath,
      imageUrl: imageUrl,
      gsUrl: gsUrl,
    );

    if (_resolved.containsKey(key)) {
      return _resolved[key];
    }
    final existing = _pending[key];
    if (existing != null) return existing;

    final fut = _resolveUncached(
      storagePath: storagePath,
      imageUrl: imageUrl,
      gsUrl: gsUrl,
    ).timeout(const Duration(seconds: 20), onTimeout: () => null).then((url) {
      _pending.remove(key);
      if (url != null && url.isNotEmpty) {
        _resolved[key] = url;
      }
      return url;
    }).catchError((Object e, StackTrace st) {
      debugPrint('AppStorageImageService.resolveImageUrl: $e');
      _pending.remove(key);
      return null;
    });

    _pending[key] = fut;
    return fut;
  }

  bool _validResolved(String? u) {
    final s = sanitizeImageUrl(u ?? '');
    return s.isNotEmpty && isValidImageUrl(s);
  }

  /// Logo da igreja: URL do Firestore → path salvo → `getDownloadURL` em caminhos padrão (ex.: `branding/logo_igreja.jpg`).
  Future<String?> resolveChurchTenantLogoUrl({
    required String tenantId,
    Map<String, dynamic>? tenantData,
    String? preferImageUrl,
    String? preferStoragePath,
    String? preferGsUrl,
  }) async {
    final tid = tenantId.trim();

    final r0 = await resolveImageUrl(
      storagePath: preferStoragePath,
      imageUrl: preferImageUrl,
      gsUrl: preferGsUrl,
    );
    if (_validResolved(r0)) return sanitizeImageUrl(r0!);

    if (tenantData != null) {
      final u = churchTenantLogoUrl(tenantData);
      if (_validResolved(u)) {
        final r1 = await resolveImageUrl(imageUrl: u);
        if (_validResolved(r1)) return sanitizeImageUrl(r1!);
      }
      final sp = ChurchImageFields.logoStoragePath(tenantData);
      if (sp != null && sp.isNotEmpty) {
        final r2 = await resolveImageUrl(storagePath: sp);
        if (_validResolved(r2)) return sanitizeImageUrl(r2!);
      }
    }

    if (tid.isNotEmpty) {
      return FirebaseStorageService.getChurchLogoDownloadUrl(
        tid,
        tenantData: tenantData,
      );
    }
    return null;
  }

  void invalidate({
    String? storagePath,
    String? imageUrl,
    String? gsUrl,
  }) {
    final key = cacheKey(
      storagePath: storagePath,
      imageUrl: imageUrl,
      gsUrl: gsUrl,
    );
    _resolved.remove(key);
    _pending.remove(key);
  }

  /// Após trocar logo/fotos de um tenant (prefixo `igrejas/{id}/...`).
  void invalidateStoragePrefix(String prefix) {
    final p = _norm(prefix);
    if (p.isEmpty) return;
    _resolved.removeWhere((k, _) => k.contains(p));
    _pending.removeWhere((k, _) => k.contains(p));
  }

  void clearAll() {
    _resolved.clear();
    _pending.clear();
  }
}
