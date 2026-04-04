/// Campos de imagem no Firestore — igreja, gestor e membro (legado + novos nomes).
/// Não altera documentos existentes; apenas centraliza leitura para UI e uploads.
library;

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

  /// URL de download (https com token) — gravada no upload; UI usa `imageUrlFromMap` em `safe_network_image.dart`.
  static String? photoDownloadUrl(Map<String, dynamic>? m) {
    if (m == null) return null;
    for (final k in ['foto_url', 'FOTO_URL_OU_ID', 'fotoUrl', 'photoURL', 'photoUrl']) {
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
