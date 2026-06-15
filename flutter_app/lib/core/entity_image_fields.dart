/// Campos de imagem no Firestore — igreja, gestor e membro (legado + novos nomes).
/// Não altera documentos existentes; apenas centraliza leitura para UI e uploads.
library;

import 'package:gestao_yahweh/core/church_storage_layout.dart';
import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';
import 'package:gestao_yahweh/services/storage_media_service.dart';

String? _normalizeStoragePathField(String? raw, {String? churchIdHint}) {
  var path = StorageMediaService.normalizeFirestoreStoragePath(raw);
  if (path == null || path.isEmpty) return null;
  if (path.endsWith('/configuracoes') || path.endsWith('/configuracoes/')) {
    final tid = churchIdHint?.trim() ?? '';
    if (tid.isNotEmpty) {
      path = ChurchStorageLayout.churchIdentityLogoPath(tid);
    } else {
      path = '${path.replaceAll(RegExp(r'/+$'), '')}/logo_igreja.png';
    }
  }
  return path;
}

/// Logo / identidade visual da igreja.
abstract final class ChurchImageFields {
  ChurchImageFields._();

  static String? logoStoragePath(
    Map<String, dynamic>? m, {
    String? churchIdHint,
  }) {
    if (m == null) return null;
    final tid = (churchIdHint ??
            m['tenantId'] ??
            m['churchId'] ??
            m['igrejaId'] ??
            m['id'] ??
            '')
        .toString()
        .trim();
    for (final k in [
      'logoStoragePath',
      'logo_storage_path',
      'logoPath',
      'logo_path',
      'churchLogoPath',
      'church_logo_path',
      'imageStoragePath',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isEmpty) continue;
      final normalized = _normalizeStoragePathField(v, churchIdHint: tid);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  /// URL https legada gravada em `logoPath` (migração manual) — só exibição imediata.
  static String? logoHttpsUrlFromDoc(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in ['logoPath', 'logo_path', 'logoUrl', 'logo_url']) {
      final v = (m[k] ?? '').toString().trim();
      final low = v.toLowerCase();
      if (low.startsWith('http://') || low.startsWith('https://')) return v;
    }
    return null;
  }
}

/// Foto de perfil do membro (e gestor como administrador).
abstract final class MemberImageFields {
  MemberImageFields._();

  static String? photoStoragePath(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      'fotoStoragePath',
      'photoStoragePath',
      'FOTO_STORAGE_PATH',
      'fotoPath',
      'photoPath',
      'foto_storage_path',
      'imageStoragePath',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      final normalized = _normalizeStoragePathField(v);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  /// URL de download full (https) — carteirinha / PDF.
  static String? photoDownloadUrl(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      YahwehPerformanceV4.profileFullField,
      'foto_url',
      'FOTO_URL_OU_ID',
      'fotoUrl',
      'photoURL',
      'photoUrl',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      if (v.startsWith('https://') || v.startsWith('http://')) return v;
    }
    return null;
  }

  /// Miniatura para listas — path Storage ou URL https.
  static String? photoThumbStoragePath(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      'photoThumbStoragePath',
      'fotoThumbPath',
      'foto_thumb_path',
      'thumbStoragePath',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      final normalized = _normalizeStoragePathField(v);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  /// Miniatura para listas — nunca usar full na UI de galeria.
  static String? photoThumbDownloadUrl(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      YahwehPerformanceV4.profileThumbField,
      YahwehPerformanceV4.profileThumbFieldLegacy,
      'photoThumbUrl',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      if (v.startsWith('https://') || v.startsWith('http://')) return v;
    }
    return null;
  }

  static String? gsPhotoUrl(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in ['fotoGsUrl', 'photoGsUrl', 'foto_gs_url', 'gsUrl']) {
      final v = (m[k] ?? '').toString().trim();
      if (v.toLowerCase().startsWith('gs://')) return v;
    }
    return null;
  }
}

/// Capa / galeria de avisos e eventos — listas usam thumb; full só ao abrir.
abstract final class FeedImageFields {
  FeedImageFields._();

  static String? thumbStoragePath(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in ['thumbStoragePath', 'thumb_storage_path']) {
      final v = (m[k] ?? '').toString().trim();
      final normalized = _normalizeStoragePathField(v);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    final iv = m['imageVariants'];
    if (iv is Map) {
      for (final tier in ['thumb_300', 'thumb_200', 'medium_800']) {
        final e = iv[tier];
        if (e is Map) {
          final sp = (e['storagePath'] ?? '').toString().trim();
          if (sp.isNotEmpty) return sp;
        }
      }
    }
    return null;
  }

  static String? imageStoragePath(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      'imageStoragePath',
      'fotoPath',
      'image_storage_path',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      final normalized = _normalizeStoragePathField(v);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }
}

/// Patrimônio — listagem carrega só foto principal (thumb na lista).
abstract final class PatrimonioImageFields {
  PatrimonioImageFields._();

  static String? fotoPrincipalPath(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in ['fotoPrincipalPath', 'foto_principal_path']) {
      final v = (m[k] ?? '').toString().trim();
      final normalized = _normalizeStoragePathField(v);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return FeedImageFields.imageStoragePath(m);
  }

  static String? fotoPrincipalThumbPath(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      'fotoPrincipalThumbPath',
      'foto_principal_thumb_path',
      'thumbStoragePath',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      final normalized = _normalizeStoragePathField(v);
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  static List<String> galleryPaths(Map<String, dynamic>? m) {
    if (m == null) return const [];
    for (final k in ['gallery', 'galeria', 'fotoStoragePaths', 'fotos']) {
      final raw = m[k];
      if (raw is List) {
        return raw
            .map((e) => _normalizeStoragePathField(e?.toString()) ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }
}
