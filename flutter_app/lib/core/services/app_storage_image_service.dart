import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageDownloadUrlLooksTokenized,
        firebaseStorageMediaUrlLooksLike,
        firebaseStorageObjectPathFromHttpUrl,
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

  /// Memoização de [resolveChurchTenantLogoUrl] — evita repetir Storage/Firestore a cada rebuild.
  final Map<String, Future<String?>> _churchLogoPending = {};
  final Map<String, String?> _churchLogoResolved = {};

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

  /// Chave estável para cache da logo (muda quando o Firestore altera URL/path/processada).
  static String churchTenantLogoCacheKey({
    required String tenantId,
    Map<String, dynamic>? tenantData,
    String? preferImageUrl,
    String? preferStoragePath,
    String? preferGsUrl,
  }) {
    final tid = tenantId.trim();
    final sp = preferStoragePath?.trim().isNotEmpty == true
        ? preferStoragePath!.trim()
        : (ChurchImageFields.logoStoragePath(tenantData) ?? '');
    final updated = tenantData?['updatedAt'] ?? tenantData?['updated_at'];
    return '$tid§${_norm(sp)}§${updated ?? ''}§${_norm(preferImageUrl)}§${_norm(preferGsUrl)}';
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

  /// Tokens em URLs antigas expiram; `getDownloadURL` no path do objeto renova (web + app).
  Future<String?> _firebaseStorageDisplayUrlPreferFresh(String raw) async {
    final norm = sanitizeImageUrl(raw);
    if (!isValidImageUrl(norm) ||
        !StorageMediaService.isFirebaseStorageMediaUrl(norm)) {
      return isValidImageUrl(norm) ? norm : null;
    }
    if (!kIsWeb) {
      await ensureFirebaseInitialized();
    }
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    if (firebaseStorageDownloadUrlLooksTokenized(norm)) {
      // App: bytes via getData — evita 2× getDownloadURL por miniatura em listas.
      if (!kIsWeb) return norm;
      final path = firebaseStorageObjectPathFromHttpUrl(norm);
      if (path != null && path.isNotEmpty) {
        final byPath = await _twice(() async {
          final ref = FirebaseStorage.instance.ref(path);
          final u =
              await ref.getDownloadURL().timeout(const Duration(seconds: 15));
          final ss = sanitizeImageUrl(u);
          return isValidImageUrl(ss) ? ss : null;
        });
        if (byPath != null) return byPath;
      }
      final byFresh = await _twice(() async {
        final r = await StorageMediaService.freshPlayableMediaUrl(norm)
            .timeout(const Duration(seconds: 28));
        final ss = sanitizeImageUrl(r);
        return isValidImageUrl(ss) ? ss : null;
      });
      if (byFresh != null) return byFresh;
      return norm;
    }
    final refreshed = await _twice(() async {
      final r = await StorageMediaService.freshPlayableMediaUrl(norm)
          .timeout(const Duration(seconds: 28));
      final ss = sanitizeImageUrl(r);
      return isValidImageUrl(ss) ? ss : null;
    });
    return refreshed ?? norm;
  }

  Future<String?> _resolveUncached({
    String? storagePath,
    String? imageUrl,
    String? gsUrl,
  }) async {
    final urlImmediate = _norm(imageUrl);
    if (urlImmediate.isNotEmpty) {
      final s0 = sanitizeImageUrl(urlImmediate);
      if (isValidImageUrl(s0) &&
          (s0.startsWith('http://') || s0.startsWith('https://'))) {
        // Mobile: URL já está no Firestore — exibir já (sem getDownloadURL por card).
        if (!kIsWeb) return s0;
        if (StorageMediaService.isFirebaseStorageMediaUrl(s0) &&
            firebaseStorageDownloadUrlLooksTokenized(s0)) {
          return _firebaseStorageDisplayUrlPreferFresh(s0);
        }
        if (!StorageMediaService.isFirebaseStorageMediaUrl(s0)) {
          return s0;
        }
      }
    }

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
      return _firebaseStorageDisplayUrlPreferFresh(s);
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

  /// Logo da igreja — delega a [ChurchBrandService] (`logoPath` → URL dinâmica).
  Future<String?> resolveChurchTenantLogoUrl({
    required String tenantId,
    Map<String, dynamic>? tenantData,
    String? preferImageUrl,
    String? preferStoragePath,
    String? preferGsUrl,
  }) {
    final cacheKey = churchTenantLogoCacheKey(
      tenantId: tenantId,
      tenantData: tenantData,
      preferImageUrl: preferImageUrl,
      preferStoragePath: preferStoragePath,
      preferGsUrl: preferGsUrl,
    );

    if (_churchLogoResolved.containsKey(cacheKey)) {
      return Future<String?>.value(_churchLogoResolved[cacheKey]);
    }
    final inflight = _churchLogoPending[cacheKey];
    if (inflight != null) return inflight;

    final fut = ChurchBrandService.getLogoUrl(
      churchId: tenantId,
      tenantData: tenantData,
    )
        .timeout(const Duration(seconds: 28), onTimeout: () => null)
        .then((url) {
      _churchLogoPending.remove(cacheKey);
      if (url != null && url.isNotEmpty) {
        _churchLogoResolved[cacheKey] = url;
      }
      return url;
    }).catchError((Object e, StackTrace st) {
      debugPrint('AppStorageImageService.resolveChurchTenantLogoUrl: $e');
      _churchLogoPending.remove(cacheKey);
      return null;
    });

    _churchLogoPending[cacheKey] = fut;
    return fut;
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

    final idx = p.indexOf('igrejas/');
    if (idx >= 0) {
      final rest = p.substring(idx + 'igrejas/'.length);
      final parts = rest.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        final seg = parts.first;
        ChurchBrandService.invalidate(churchId: seg);
        final pref = '$seg§';
        _churchLogoResolved.removeWhere((k, _) => k.startsWith(pref));
        _churchLogoPending.removeWhere((k, _) => k.startsWith(pref));
      }
    }
  }

  void clearAll() {
    _resolved.clear();
    _pending.clear();
    _churchLogoResolved.clear();
    _churchLogoPending.clear();
  }
}
