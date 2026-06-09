/// Campos de imagem no Firestore — igreja, gestor e membro (legado + novos nomes).
/// Não altera documentos existentes; apenas centraliza leitura para UI e uploads.
library;

import 'package:gestao_yahweh/core/yahweh_performance_v4.dart';

/// Logo / identidade visual da igreja.
abstract final class ChurchImageFields {
  ChurchImageFields._();

  static String? logoStoragePath(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in [
      'logoPath',
      'logo_path',
      'logo_storage_path',
      'churchLogoPath',
      'church_logo_path',
      'logoStoragePath',
      'imageStoragePath',
    ]) {
      final v = (m[k] ?? '').toString().trim();
      if (v.isNotEmpty) return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
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
      if (v.isNotEmpty) return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
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
      if (v.isNotEmpty) {
        return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
      }
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
      if (v.isNotEmpty) {
        return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
      }
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
      if (v.isNotEmpty) {
        return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
      }
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
      if (v.isNotEmpty) {
        return v.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
      }
    }
    return null;
  }

  static List<String> galleryPaths(Map<String, dynamic>? m) {
    if (m == null) return const [];
    for (final k in ['gallery', 'galeria', 'fotoStoragePaths', 'fotos']) {
      final raw = m[k];
      if (raw is List) {
        return raw
            .map((e) => e?.toString().trim() ?? '')
            .where((s) => s.isNotEmpty)
            .map((s) => s.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), ''))
            .toList();
      }
    }
    return const [];
  }
}
