import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/entity_image_fields.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_storage_metadata_verify.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';
import 'package:gestao_yahweh/services/tenant_resolver_service.dart';

/// Logo institucional — **fonte única**: `logoPath` → Storage canónico.
abstract final class ChurchBrandService {
  ChurchBrandService._();

  static final Map<String, _BrandCacheEntry> _cache = {};
  static final Map<String, Future<String?>> _logoUrlPending = {};
  static final Map<String, Future<Uint8List?>> _logoBytesPending = {};

  /// Campos legados removidos do Firestore ao gravar logo nova.
  static const List<String> legacyLogoUrlFirestoreKeys = [
    'logoUrl',
    'logo_url',
    'logoProcessedUrl',
    'logoProcessed',
    'logoImage',
    'logoDownloadUrl',
    'logoVariants',
  ];

  static String canonicalLogoPath(String churchId) =>
      ChurchStorageLayout.churchIdentityLogoPath(churchId.trim());

  static String? logoPathFromData(
    Map<String, dynamic>? data, {
    required String churchId,
  }) {
    final fromDoc = ChurchImageFields.logoStoragePath(
      data,
      churchIdHint: churchId,
    );
    if (fromDoc != null && fromDoc.isNotEmpty) return fromDoc;
    final cid = churchId.trim();
    if (cid.isEmpty) return null;
    return canonicalLogoPath(cid);
  }

  static String _updatedAtKey(Map<String, dynamic>? data) {
    final v = data?['updatedAt'] ?? data?['updated_at'];
    if (v is Timestamp) return v.millisecondsSinceEpoch.toString();
    return v?.toString() ?? '';
  }

  static String _cacheKey(String churchId, Map<String, dynamic>? data) =>
      '${churchId.trim()}|${_updatedAtKey(data)}';

  /// Path canónico no Storage — Firestore `logoPath` ou fallback padrão.
  static Future<String?> getLogoPath({
    required String churchId,
    Map<String, dynamic>? tenantData,
    bool verifyStorage = false,
  }) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return null;

    Map<String, dynamic>? data = tenantData;
    if (data == null) {
      data = await _loadTenantData(cid);
    }

    final path = logoPathFromData(data, churchId: cid);
    if (path == null || path.isEmpty) return null;

    if (verifyStorage) {
      try {
        await ChurchStorageMetadataVerify.assertExists(path);
      } catch (_) {
        return null;
      }
    }
    return path;
  }

  /// URL dinâmica via SDK (`getDownloadURL`) — **nunca** persistida no Firestore.
  static Future<String?> getLogoUrl({
    required String churchId,
    Map<String, dynamic>? tenantData,
  }) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return null;

    Map<String, dynamic>? data = tenantData;
    if (data == null) {
      data = await _loadTenantData(cid);
    }

    final key = _cacheKey(cid, data);
    final cached = _cache[key];
    if (cached?.url != null && cached!.url!.isNotEmpty) {
      return cached.url;
    }

    final inflight = _logoUrlPending[key];
    if (inflight != null) return inflight;

    final fut = _resolveLogoUrl(cid, data, key);
    _logoUrlPending[key] = fut;
    return fut;
  }

  static Future<String?> _resolveLogoUrl(
    String churchId,
    Map<String, dynamic>? data,
    String cacheKey,
  ) async {
    try {
      await ensureFirebaseReadyForMediaUpload();
      if (kIsWeb) {
        await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      }
      final path = logoPathFromData(data, churchId: churchId);
      if (path == null || path.isEmpty) return null;

      unawaited(_repairLegacyLogoUrlInFirestore(churchId, path));

      try {
        final md = await firebaseDefaultStorage
            .ref(path)
            .getMetadata()
            .timeout(const Duration(seconds: 8));
        final sz = md.size ?? 0;
        if (sz > 0 &&
            sz <
                ChurchStorageLayout
                    .kChurchIdentityLogoMinBytesForFirestoreSync) {
          return null;
        }
      } catch (_) {
        // Metadata indisponível (rede/web) — tenta getDownloadURL mesmo assim.
      }

      final url = await StorageMediaService.downloadUrlFromPathOrUrl(path)
          .timeout(const Duration(seconds: 12));
      if (url != null && url.isNotEmpty) {
        _cache[cacheKey] = _BrandCacheEntry(
          path: path,
          url: url,
          updatedAtKey: _updatedAtKey(data),
        );
      }
      return url;
    } catch (e, st) {
      debugPrint('ChurchBrandService.getLogoUrl: $e\n$st');
      return null;
    } finally {
      _logoUrlPending.remove(cacheKey);
    }
  }

  /// Bytes da logo — útil para PDF/carteirinha offline.
  static Future<Uint8List?> getLogoBytes({
    required String churchId,
    Map<String, dynamic>? tenantData,
  }) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return null;

    Map<String, dynamic>? data = tenantData;
    if (data == null) {
      data = await _loadTenantData(cid);
    }

    final key = _cacheKey(cid, data);
    final cached = _cache[key];
    if (cached?.bytes != null && cached!.bytes!.isNotEmpty) {
      return cached.bytes;
    }

    final inflight = _logoBytesPending[key];
    if (inflight != null) return inflight;

    final fut = _resolveLogoBytes(cid, data, key);
    _logoBytesPending[key] = fut;
    return fut;
  }

  static Future<Uint8List?> _resolveLogoBytes(
    String churchId,
    Map<String, dynamic>? data,
    String cacheKey,
  ) async {
    try {
      await ensureFirebaseReadyForPublishUpload();
      final path = await getLogoPath(
        churchId: churchId,
        tenantData: data,
        verifyStorage: true,
      );
      if (path == null || path.isEmpty) return null;

      final bytes = await firebaseDefaultStorage
          .ref(path)
          .getData(1024 * 1024 * 4)
          .timeout(const Duration(seconds: 30));
      if (bytes != null && bytes.isNotEmpty) {
        final prev = _cache[cacheKey];
        _cache[cacheKey] = _BrandCacheEntry(
          path: path,
          url: prev?.url,
          bytes: bytes,
          updatedAtKey: _updatedAtKey(data),
        );
      }
      return bytes;
    } catch (e, st) {
      debugPrint('ChurchBrandService.getLogoBytes: $e\n$st');
      return null;
    } finally {
      _logoBytesPending.remove(cacheKey);
    }
  }

  /// Patch Firestore — só `logoPath`; remove URLs legadas.
  static Map<String, dynamic> logoPathFirestorePatch(String storagePath) {
    final patch = <String, dynamic>{
      'logoPath': storagePath.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    for (final k in legacyLogoUrlFirestoreKeys) {
      patch[k] = FieldValue.delete();
    }
    return patch;
  }

  static Future<void> persistLogoPath({
    required String churchId,
    required String storagePath,
  }) async {
    final cid = churchId.trim();
    var path = StorageMediaService.normalizeFirestoreStoragePath(storagePath) ??
        storagePath.trim();
    if (path.endsWith('/configuracoes') || path.endsWith('/configuracoes/')) {
      path = canonicalLogoPath(cid);
    }
    if (cid.isEmpty || path.isEmpty) {
      throw StateError('churchId ou storagePath vazio.');
    }
    if (!path.startsWith('igrejas/') || path.contains('firebasestorage')) {
      throw StateError('logoPath inválido — use igrejas/{id}/configuracoes/logo_igreja.png');
    }
    await ensureFirebaseReadyForPublishUpload();
    await ChurchStorageMetadataVerify.assertExists(path);
    await ChurchOperationalPaths.churchDoc(cid).set(
      logoPathFirestorePatch(path),
      SetOptions(merge: true),
    );
    invalidate(churchId: cid);
    unawaited(_repairLegacyLogoUrlInFirestore(cid, path));
    TenantResolverService.invalidateRegistrationContextCache(
      seedId: cid,
      userUid: firebaseDefaultAuth.currentUser?.uid,
    );
  }

  /// Se `logoPath` ainda guarda URL https, corrige para path canónico (silencioso).
  static Future<void> _repairLegacyLogoUrlInFirestore(
    String churchId,
    String canonicalPath,
  ) async {
    try {
      final snap = await ChurchOperationalPaths.churchDoc(churchId).get();
      final raw = (snap.data()?['logoPath'] ?? '').toString().trim();
      final low = raw.toLowerCase();
      if (!low.startsWith('http://') && !low.startsWith('https://')) return;
      await ChurchOperationalPaths.churchDoc(churchId).set(
        logoPathFirestorePatch(canonicalPath),
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  /// Pré-carrega logo em memória — Dashboard, carteirinha, certificado, chat, site.
  static Future<void> preloadForSession({
    required String churchId,
    Map<String, dynamic>? tenantData,
  }) async {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    unawaited(getLogoUrl(churchId: cid, tenantData: tenantData));
    unawaited(getLogoBytes(churchId: cid, tenantData: tenantData));
  }

  static void invalidate({required String churchId}) {
    final cid = churchId.trim();
    if (cid.isEmpty) return;
    _cache.removeWhere((k, _) => k.startsWith('$cid|'));
    _logoUrlPending.removeWhere((k, _) => k.startsWith('$cid|'));
    _logoBytesPending.removeWhere((k, _) => k.startsWith('$cid|'));
  }

  static Future<Map<String, dynamic>?> _loadTenantData(String churchId) async {
    try {
      await ensureFirebaseCore(requireAuth: false);
      final snap = await ChurchOperationalPaths.churchDoc(churchId).get();
      return snap.data();
    } catch (_) {
      return null;
    }
  }
}

final class _BrandCacheEntry {
  const _BrandCacheEntry({
    required this.path,
    this.url,
    this.bytes,
    required this.updatedAtKey,
  });

  final String path;
  final String? url;
  final Uint8List? bytes;
  final String updatedAtKey;
}
