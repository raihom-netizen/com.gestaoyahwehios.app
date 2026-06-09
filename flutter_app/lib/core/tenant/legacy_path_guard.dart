import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;

/// Bloqueio de paths legados — tudo tenant deve passar por `igrejas/{churchId}/`.
abstract final class LegacyPathGuard {
  LegacyPathGuard._();

  static const canonicalFirestoreRoot = 'igrejas';
  static const canonicalStoragePrefix = 'igrejas/';

  /// Coleções **proibidas** fora de `igrejas/{churchId}/` (dados de módulo).
  static const forbiddenModuleCollections = <String>{
    'members',
    'membros', // só válido sob igrejas/{id}/
    'events',
    'eventos',
    'announcements',
    'avisos',
    'finance',
    'financeiro',
    'departments',
    'departamentos',
    'positions',
    'cargos',
    'patrimony',
    'patrimonio',
    'scales',
    'escalas',
  };

  /// `users/` na raiz é permitido (perfil global Auth) — não incluir acima.
  static bool isCanonicalChurchSubPath(String fullPath) {
    final p = fullPath.replaceAll('\\', '/').trim();
    if (!p.startsWith('$canonicalFirestoreRoot/')) return false;
    final parts = p.split('/').where((s) => s.isNotEmpty).toList();
    return parts.length >= 3;
  }

  /// Valida path Firestore; em debug falha cedo se detectar legado fora de igrejas/.
  static void assertCanonicalFirestorePath(String fullPath, {String? context}) {
    final p = fullPath.replaceAll('\\', '/').trim();
    if (p.isEmpty) return;

    if (p.startsWith('$canonicalFirestoreRoot/')) return;

    for (final banned in forbiddenModuleCollections) {
      if (p == banned || p.startsWith('$banned/')) {
        final msg =
            'LEGACY_PATH: $p${context != null ? " ($context)" : ""} — use igrejas/{churchId}/...';
        assert(false, msg);
        if (kDebugMode) debugPrint('⚠ $msg');
        return;
      }
    }
  }

  static void assertCanonicalStoragePath(String storagePath, {String? context}) {
    final p = storagePath.replaceAll('\\', '/').trim();
    if (p.isEmpty) return;
    if (p.startsWith(canonicalStoragePrefix)) return;
    if (p.startsWith('tenants/')) {
      final msg =
          'LEGACY_STORAGE: $p${context != null ? " ($context)" : ""} — use igrejas/{churchId}/...';
      assert(false, msg);
      if (kDebugMode) debugPrint('⚠ $msg');
    }
  }
}
