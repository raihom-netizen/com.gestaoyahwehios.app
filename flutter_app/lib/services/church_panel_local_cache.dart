import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gestao_yahweh/core/cache/tenant_module_hive_cache.dart';
import 'package:gestao_yahweh/core/cache/tenant_module_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache local do painel igreja — Hive (mobile) + SharedPreferences (Web).
///
/// Módulos: cadastro, departamentos, cargos, configurações, logo.
abstract final class ChurchPanelLocalCache {
  ChurchPanelLocalCache._();

  static const _webPrefix = 'church_panel_cache_v1_';
  static const Duration kDefaultMaxAge = Duration(hours: 24);
  static const Duration _kWebDefaultMaxAge = Duration(minutes: 20);
  static const Duration _kWebCountMaxAge = Duration(minutes: 5);
  static const Duration _kWebLogoMaxAge = Duration(hours: 6);

  static const String moduleCadastro = 'cadastro_igreja';
  static const String moduleConfig = 'configuracoes';
  static const String moduleLogo = 'logo_path';

  static String _webKey(String churchId, String module) =>
      '$_webPrefix${churchId.trim()}_$module';

  static Duration _resolveWebMaxAge(String module, Duration requested) {
    // Só reduz quando o caller usa o padrão; respeita maxAge explícito.
    if (requested != kDefaultMaxAge) return requested;
    final m = module.trim().toLowerCase();
    if (m.endsWith('_count')) return _kWebCountMaxAge;
    if (m == moduleLogo) return _kWebLogoMaxAge;
    return _kWebDefaultMaxAge;
  }

  /// Lê mapa JSON do cadastro/config (stale-while-revalidate).
  static Future<Map<String, dynamic>?> readMap({
    required String churchId,
    required String module,
    Duration maxAge = kDefaultMaxAge,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty) return null;

    if (kIsWeb) {
      try {
        final effectiveMaxAge = _resolveWebMaxAge(module, maxAge);
        final p = await SharedPreferences.getInstance();
        final raw = p.getString(_webKey(id, module));
        final ts = p.getInt('${_webKey(id, module)}_ts');
        if (raw == null || raw.isEmpty) return null;
        if (ts != null &&
            DateTime.now().millisecondsSinceEpoch - ts >
                effectiveMaxAge.inMilliseconds) {
          return null;
        }
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
      return null;
    }

    final rows = await TenantModuleHiveCache.readDocs(
      id,
      module,
      maxAge: maxAge,
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  static Future<void> saveMap({
    required String churchId,
    required String module,
    required Map<String, dynamic> data,
  }) async {
    final id = churchId.trim();
    if (id.isEmpty || data.isEmpty) return;

    if (kIsWeb) {
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_webKey(id, module), jsonEncode(data));
        await p.setInt(
          '${_webKey(id, module)}_ts',
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {}
      return;
    }

    await TenantModuleHiveCache.saveDocs(id, module, [data]);
  }

  static Future<String?> readLogoPath(String churchId) async {
    final map = await readMap(
      churchId: churchId,
      module: moduleLogo,
      maxAge: const Duration(days: 7),
    );
    return (map?['logoPath'] ?? '').toString().trim().isEmpty
        ? null
        : (map!['logoPath'] as String).trim();
  }

  static Future<void> saveLogoPath({
    required String churchId,
    required String logoPath,
  }) =>
      saveMap(
        churchId: churchId,
        module: moduleLogo,
        data: {'logoPath': logoPath.trim()},
      );

  /// Contagens leves para bootstrap (departamentos, cargos, membros).
  static Future<void> saveModuleCount({
    required String churchId,
    required String module,
    required int count,
  }) =>
      saveMap(
        churchId: churchId,
        module: '${module}_count',
        data: {'count': count, 'at': DateTime.now().toIso8601String()},
      );

  static Future<int?> readModuleCount({
    required String churchId,
    required String module,
  }) async {
    final m = await readMap(churchId: churchId, module: '${module}_count');
    if (m == null) return null;
    return m['count'] is int ? m['count'] as int : int.tryParse('${m['count']}');
  }

  /// Chaves Hive alinhadas ao preload existente.
  static String hiveModuleKey(String subcollection) {
    switch (subcollection) {
      case 'departamentos':
        return TenantModuleKeys.departamentos;
      case 'cargos':
        return TenantModuleKeys.cargos;
      case 'membros':
        return TenantModuleKeys.membros;
      default:
        return subcollection;
    }
  }
}
