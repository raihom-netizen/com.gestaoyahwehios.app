import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        churchTenantLogoUrl,
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
    if (tenantData == null) {
      return '$tid§§${_norm(preferImageUrl)}§${_norm(preferStoragePath)}§${_norm(preferGsUrl)}';
    }
    final u = churchTenantLogoUrl(tenantData);
    final sp = ChurchImageFields.logoStoragePath(tenantData) ?? '';
    final proc1 = (tenantData['logoProcessedUrl'] ?? '').toString().trim();
    final proc2 = (tenantData['logoProcessed'] ?? '').toString().trim();
    final updated = tenantData['updatedAt'] ?? tenantData['updated_at'];
    return '$tid§${_norm(u)}§${_norm(sp)}§${_norm(proc1)}§${_norm(proc2)}§${updated ?? ''}§${_norm(preferImageUrl)}§${_norm(preferStoragePath)}§${_norm(preferGsUrl)}';
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
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    if (firebaseStorageDownloadUrlLooksTokenized(norm)) {
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
          StorageMediaService.isFirebaseStorageMediaUrl(s0) &&
          firebaseStorageDownloadUrlLooksTokenized(s0)) {
        return _firebaseStorageDisplayUrlPreferFresh(s0);
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

  bool _validResolved(String? u) {
    final s = sanitizeImageUrl(u ?? '');
    return s.isNotEmpty && isValidImageUrl(s);
  }

  /// Rejeita URL do Storage se for `.../configuracoes/logo_igreja.*` com poucos bytes (placeholder 1×1 ou ficheiro estragado).
  Future<String?> _rejectIfTinyCanonicalChurchLogoUrl(String? resolved) async {
    final u = sanitizeImageUrl(resolved ?? '');
    if (!isValidImageUrl(u)) return resolved;
    if (!StorageMediaService.isFirebaseStorageMediaUrl(u)) return resolved;
    final path = firebaseStorageObjectPathFromHttpUrl(u);
    if (path == null || path.isEmpty) return resolved;
    final low = path.toLowerCase();
    if (!low.contains('/configuracoes/logo_igreja')) return resolved;
    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }
    try {
      final ref = FirebaseStorage.instance.ref(path);
      final m = await ref.getMetadata().timeout(const Duration(seconds: 8));
      final sz = m.size ?? 0;
      if (sz > 0 &&
          sz < ChurchStorageLayout.kChurchIdentityLogoMinBytesForFirestoreSync) {
        return null;
      }
    } catch (_) {}
    return resolved;
  }

  /// Logo da igreja: **objeto real no Storage primeiro** (token fresco via SDK; ignora placeholder
  /// menor que [ChurchStorageLayout.kChurchIdentityLogoMinBytesForFirestoreSync]) → depois URLs processadas / Firestore.
  ///
  /// Ordem antiga (processada antes do bucket) fazia o site/escala/cadastro público ficarem com
  /// link morto ou token expirado em [logoProcessedUrl] mesmo havendo ficheiro válido em
  /// `configuracoes/logo_igreja.png` ou [logoPath].
  ///
  /// Resultado é **memoizado** por [churchTenantLogoCacheKey] para o mesmo tenant/dados.
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

    final fut = _resolveChurchTenantLogoUrlUncached(
      tenantId: tenantId,
      tenantData: tenantData,
      preferImageUrl: preferImageUrl,
      preferStoragePath: preferStoragePath,
      preferGsUrl: preferGsUrl,
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

  Future<String?> _resolveChurchTenantLogoUrlUncached({
    required String tenantId,
    Map<String, dynamic>? tenantData,
    String? preferImageUrl,
    String? preferStoragePath,
    String? preferGsUrl,
  }) async {
    final tid = tenantId.trim();

    if (kIsWeb) {
      await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      try {
        await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
    }

    if (tid.isNotEmpty) {
      final fromBucket = await FirebaseStorageService.getChurchLogoDownloadUrl(
        tid,
        tenantData: tenantData,
      );
      final bucketOk = await _rejectIfTinyCanonicalChurchLogoUrl(fromBucket);
      if (_validResolved(bucketOk)) return sanitizeImageUrl(bucketOk!);
    }

    if (tenantData != null) {
      for (final key in ['logoProcessedUrl', 'logoProcessed']) {
        final raw = tenantData[key];
        final s = raw?.toString().trim();
        if (s != null && s.isNotEmpty) {
          final r = await resolveImageUrl(imageUrl: s);
          final ok = await _rejectIfTinyCanonicalChurchLogoUrl(r);
          if (_validResolved(ok)) return sanitizeImageUrl(ok!);
        }
      }
    }

    final r0 = await resolveImageUrl(
      storagePath: preferStoragePath,
      imageUrl: preferImageUrl,
      gsUrl: preferGsUrl,
    );
    final r0b = await _rejectIfTinyCanonicalChurchLogoUrl(r0);
    if (_validResolved(r0b)) return sanitizeImageUrl(r0b!);

    if (tenantData != null) {
      final u = churchTenantLogoUrl(tenantData);
      if (_validResolved(u)) {
        final r1 = await resolveImageUrl(imageUrl: u);
        final r1b = await _rejectIfTinyCanonicalChurchLogoUrl(r1);
        if (_validResolved(r1b)) return sanitizeImageUrl(r1b!);
      }
      final sp = ChurchImageFields.logoStoragePath(tenantData);
      if (sp != null && sp.isNotEmpty) {
        final r2 = await resolveImageUrl(storagePath: sp);
        final r2b = await _rejectIfTinyCanonicalChurchLogoUrl(r2);
        if (_validResolved(r2b)) return sanitizeImageUrl(r2b!);
      }
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

    final idx = p.indexOf('igrejas/');
    if (idx >= 0) {
      final rest = p.substring(idx + 'igrejas/'.length);
      final parts = rest.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.isNotEmpty) {
        final seg = parts.first;
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
