import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_flow.dart';
import 'package:gestao_yahweh/core/ecofire/ecofire_media_upload.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap.dart';
import 'package:gestao_yahweh/services/church_tenant_media_service.dart';
import 'package:gestao_yahweh/core/public_site_media_auth.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart'
    show
        firebaseStorageObjectPathFromHttpUrl,
        imageUrlFromMap,
        isValidImageUrl,
        refreshFirebaseStorageDownloadUrl,
        sanitizeImageUrl,
        freshFirebaseStorageDisplayUrl,
        firebaseStorageMediaUrlLooksLike;

/// Camada única de mídia Storage — **padrão EcoFire** (`StorageUploadService` + refresh de URL).
/// Uploads devem sempre gravar o retorno de [Reference.getDownloadURL]; quando a URL antiga falhar,
/// use [freshPlayableMediaUrl] para renovar o token (imagem ou vídeo).
///
/// A lógica pesada está em [freshFirebaseStorageDisplayUrl] em `safe_network_image.dart`.
class StorageMediaService {
  StorageMediaService._();

  /// Detecta URL de mídia hospedada no Firebase Storage (incl. `googleapis.com/.../o/...?alt=media`).
  static bool isFirebaseStorageMediaUrl(String url) =>
      firebaseStorageMediaUrlLooksLike(url);

  /// Renova URL do Firebase Storage (token) — **inclui web** (antes o vídeo pulava o refresh na web).
  static Future<String> freshPlayableMediaUrl(String rawUrl) async {
    return freshFirebaseStorageDisplayUrl(rawUrl);
  }

  /// Só imagens: delega para [refreshFirebaseStorageDownloadUrl] (usa [freshFirebaseStorageDisplayUrl]).
  static Future<String?> freshImageUrl(String? rawUrl) =>
      refreshFirebaseStorageDownloadUrl(rawUrl);

  /// Valor adequado para gravar em campos de “URL pública” no Firestore: **https** com token.
  /// Converte `gs://` ou caminho `igrejas/...` em download URL; devolve null se não resolver.
  static Future<String?> publishableHttpsUrlForFirestore(String? raw) async {
    final u = await downloadUrlFromPathOrUrl(raw);
    final s = sanitizeImageUrl(u ?? '');
    if (s.isEmpty) return null;
    if (s.toLowerCase().startsWith('gs://')) return null;
    if (!s.startsWith('http://') && !s.startsWith('https://')) return null;
    return s;
  }

  /// Não persistir isto como URL de exibição (use [publishableHttpsUrlForFirestore] após upload).
  static bool looksLikeGsUri(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    return t.startsWith('gs://');
  }

  /// Caminho `igrejas/...` a partir de path bruto, `gs://` ou URL https do Storage.
  static String? storageObjectPathFromPathOrUrl(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return null;
    final low = t.toLowerCase();
    if (low.startsWith('gs://')) {
      final rest = t.substring(5);
      final idx = rest.indexOf('/');
      if (idx >= 0 && idx < rest.length - 1) {
        return rest.substring(idx + 1);
      }
      return null;
    }
    if (t.contains('/') &&
        !low.startsWith('http://') &&
        !low.startsWith('https://')) {
      return t.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
    }
    return firebaseStorageObjectPathFromHttpUrl(t);
  }

  /// Path canónico no bucket — normaliza `gs://`, URL https antiga ou path relativo.
  static String? normalizeFirestoreStoragePath(String? raw) {
    final path = storageObjectPathFromPathOrUrl(raw);
    if (path == null || path.isEmpty) return null;
    return path.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  }

  /// Resolve caminho `igrejas/...` ou URL antiga para URL atual de download.
  static Future<String?> downloadUrlFromPathOrUrl(String? raw) async {
    await ensureFirebaseReadyForMediaUpload();
    if (raw == null) return null;
    final t = raw.trim();
    if (t.isEmpty) return null;
    final s = sanitizeImageUrl(t);
    if (isValidImageUrl(s) && isFirebaseStorageMediaUrl(s)) {
      return freshPlayableMediaUrl(s);
    }
    if (s.toLowerCase().startsWith('gs://')) {
      try {
        if (kIsWeb) {
          await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
        }
        final url = await firebaseDefaultStorage
            .refFromURL(s)
            .getDownloadURL()
            .timeout(const Duration(seconds: 15));
        ChurchTenantMediaActivity.recordDownload(s);
        return url;
      } catch (_) {}
      return null;
    }
    if (s.contains('/') && !s.startsWith('http')) {
      try {
        if (kIsWeb) {
          await PublicSiteMediaAuth.ensureWebAnonymousForStorage();
        }
        final url = await firebaseDefaultStorage
            .ref(s)
            .getDownloadURL()
            .timeout(const Duration(seconds: 15));
        ChurchTenantMediaActivity.recordDownload(s);
        return url;
      } catch (_) {}
      if (EcoFireFlow.enabled) {
        return EcoFireMediaUpload.resolveDisplayUrl(storagePath: s);
      }
    }
    return null;
  }

  /// Pastas `membros/{stem}/` encontradas em qualquer string do mapa (URL https antiga, path, notas).
  /// Ajuda quando o doc usa id ≠ pasta no Storage (ex.: CPF no doc, `foto_perfil` em `membros/{uid}/`).
  static List<String> memberProfileFolderStemsFromFirestoreMap(
      Map<String, dynamic> data) {
    final out = <String>{};
    final re = RegExp(r'(?:^|/)membros/([^/]+)/foto_perfil', caseSensitive: false);
    void considerPath(String? path) {
      if (path == null || path.isEmpty) return;
      final m = re.firstMatch(path.replaceAll('\\', '/'));
      if (m != null) {
        final stem = m.group(1)!.trim();
        if (stem.isNotEmpty) out.add(stem);
      }
    }

    void scan(String s) {
      if (s.isEmpty) return;
      considerPath(firebaseStorageObjectPathFromHttpUrl(s));
      considerPath(s);
    }

    void walk(dynamic v) {
      if (v is String) {
        scan(v);
      } else if (v is Map) {
        for (final e in v.values) {
          walk(e);
        }
      } else if (v is Iterable) {
        for (final e in v) {
          walk(e);
        }
      }
    }

    walk(data);
    return out.toList();
  }

  /// Fallback em cascata para mapas de mídia:
  /// URL principal -> URL fresh -> storagePath -> null
  static Future<String?> resolveImageFromMap(Map<String, dynamic>? data) async {
    if (data == null) return null;
    final primary = sanitizeImageUrl(imageUrlFromMap(data));
    if (primary.isNotEmpty && isValidImageUrl(primary)) {
      final fresh = await freshImageUrl(primary);
      return sanitizeImageUrl(fresh ?? primary);
    }
    for (final k in const [
      'storagePath',
      'storage_path',
      'imageStoragePath',
      'photoStoragePath',
      'logoPath',
      'path',
      'ref',
    ]) {
      final raw = (data[k] ?? '').toString().trim();
      if (raw.isEmpty) continue;
      final url = await downloadUrlFromPathOrUrl(raw);
      if (url != null && url.trim().isNotEmpty) return sanitizeImageUrl(url);
    }
    return null;
  }
}
