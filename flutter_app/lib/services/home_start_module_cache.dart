import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gestao_yahweh/services/app_session_cache.dart';
import 'package:gestao_yahweh/services/delegate_access_service.dart';
import 'package:gestao_yahweh/services/widget_update_service.dart';
import 'package:gestao_yahweh/utils/firestore_user_doc_id.dart';
import 'package:gestao_yahweh/ui/widgets/home_start_module_picker.dart';
import 'package:gestao_yahweh/constants/shell_module_indices.dart';

/// Índice da tela inicial preferida — abre direto no módulo escolhido, sem flash em «Início».
class HomeStartModuleCache {
  HomeStartModuleCache._();

  static const _kUid = 'home_start_mod_uid_v1';
  static const _kIdx = 'home_start_mod_idx_v1';

  static int? _memory;
  static String? _memoryUid;

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = (prefs.getString(_kUid) ?? '').trim();
    if (uid.isEmpty) {
      _memory = null;
      _memoryUid = null;
      return;
    }
    final idx = prefs.getInt(_kIdx);
    final migrated = idx == null ? null : migrateHomeStartModuleIndex(idx);
    if (migrated == null ||
        !kHomeDefaultStartModuleLabels.containsKey(migrated)) {
      _memory = null;
      _memoryUid = null;
      return;
    }
    _memoryUid = uid;
    _memory = migrated;
  }

  static int? getSync(String uid) {
    if (_memory == null) return null;
    final clean = uid.trim();
    final stored = (_memoryUid ?? '').trim();
    if (clean.isEmpty) return _memory;
    if (stored.isEmpty || stored == clean) return _memory;
    final session = firestoreUserDocIdStrictFromSession();
    if (session.isNotEmpty && (session == clean || session == stored)) {
      return _memory;
    }
    final cached = AppSessionCache.cachedUidSync();
    if (cached != null && cached.isNotEmpty) {
      if (cached == clean || cached == stored) return _memory;
    }
    final owner = DelegateAccessService.dataOwnerUid;
    if (owner != null && owner.isNotEmpty) {
      if (owner == clean || owner == stored) return _memory;
    }
    return null;
  }

  /// Resolve tela inicial no cold start — tenta uid do shell, doc Firestore e sessão em cache.
  static int? resolveForShell({
    required String shellUid,
    String? docUid,
  }) {
    final candidates = <String>{
      if (docUid != null && docUid.trim().isNotEmpty) docUid.trim(),
      shellUid.trim(),
      AppSessionCache.cachedUidSync() ?? '',
      (_memoryUid ?? '').trim(),
      firestoreUserDocIdStrictFromSession(),
      DelegateAccessService.dataOwnerUid ?? '',
    }..removeWhere((s) => s.isEmpty);
    for (final c in candidates) {
      final v = getSync(c);
      if (v != null && kHomeDefaultStartModuleLabels.containsKey(v)) return v;
    }
    if (_memory != null && kHomeDefaultStartModuleLabels.containsKey(_memory)) {
      return _memory;
    }
    return null;
  }

  /// Módulo de abertura no shell — preferência explícita ou Escalas (motor do sistema).
  static int resolveStartupModule({
    required String shellUid,
    String? docUid,
    int? initialModuleIndex,
  }) {
    if (initialModuleIndex != null &&
        kHomeDefaultStartModuleLabels.containsKey(initialModuleIndex)) {
      return initialModuleIndex;
    }
    final preferred = resolveForShell(shellUid: shellUid, docUid: docUid);
    if (preferred != null &&
        kHomeDefaultStartModuleLabels.containsKey(preferred)) {
      return preferred;
    }
    return ShellModuleIndex.escalas;
  }

  static Future<void> save(String uid, int moduleIndex) async {
    final clean = uid.trim();
    if (clean.isEmpty || !kHomeDefaultStartModuleLabels.containsKey(moduleIndex)) {
      return;
    }
    _memoryUid = clean;
    _memory = moduleIndex;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, clean);
    await prefs.setInt(_kIdx, moduleIndex);
    unawaited(WidgetUpdateService.syncOpenModuleIndex(moduleIndex));
  }

  static Future<void> clear() async {
    _memory = null;
    _memoryUid = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kIdx);
  }

  static Future<void> prefetch(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    try {
      final snap = await homePlanningRef(clean).get(
        const GetOptions(source: Source.serverAndCache),
      );
      final data = snap.data();
      if (data == null || !data.containsKey(kHomeDefaultStartModuleField)) {
        // Sem preferência explícita no servidor — não sobrescrever cache local.
        return;
      }
      final raw = data[kHomeDefaultStartModuleField];
      final schema = data[kHomeDefaultStartModuleSchemaField];
      final schemaNum = schema is num ? schema.toInt() : 1;
      final preferred = resolveHomeStartModuleIndex(
        raw: raw is num ? raw.toInt() : 0,
        schema: schemaNum,
      );
      if (!kHomeDefaultStartModuleLabels.containsKey(preferred)) return;
      await save(clean, preferred);
    } catch (e, st) {
      debugPrint('HomeStartModuleCache.prefetch: $e\n$st');
    }
  }
}
