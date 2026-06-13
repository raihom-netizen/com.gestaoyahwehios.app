import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:gestao_yahweh/services/auth_gate_panel_access_service.dart';
import 'package:gestao_yahweh/utils/firestore_json_safe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste o perfil resolvido do [AuthGate] para abrir o painel **sem rede**
/// (Android/iOS) com o mesmo utilizador já autenticado localmente.
typedef AuthProfileCacheListener = void Function(
  String uid,
  Map<String, dynamic> profile,
);

class AuthProfileCacheService {
  AuthProfileCacheService._();
  static final AuthProfileCacheService instance = AuthProfileCacheService._();

  static const _keyPrefix = 'auth_gate_profile_json_v2_';

  final Map<String, Map<String, dynamic>> _memory = {};
  final List<AuthProfileCacheListener> _listeners = [];

  void addListener(AuthProfileCacheListener listener) {
    _listeners.add(listener);
  }

  void removeListener(AuthProfileCacheListener listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners(String uid, Map<String, dynamic> profile) {
    if (_listeners.isEmpty) return;
    final copy = Map<String, dynamic>.from(profile);
    for (final l in List<AuthProfileCacheListener>.from(_listeners)) {
      try {
        l(uid, copy);
      } catch (_) {}
    }
  }

  /// Pré-carrega perfil em RAM antes do AuthGate (web: evita spinner sem rede).
  static Future<void> warmUpForStartup() async {
    final uid = AppShellSessionCache.cachedUidSync();
    if (uid == null || uid.isEmpty) return;
    await instance.load(uid);
  }

  /// Leitura síncrona após `load`/`save` — evita spinner no 1.º frame do AuthGate.
  Map<String, dynamic>? peek(String uid) {
    final u = uid.trim();
    if (u.isEmpty) return null;
    final m = _memory[u];
    if (m == null || m.isEmpty) return null;
    if (AuthGateProfileCachePolicy.requiresOnlineVerification(m)) {
      return null;
    }
    return Map<String, dynamic>.from(m);
  }

  static dynamic _fromJsonSafe(dynamic v) {
    if (v == null) return null;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), _fromJsonSafe(val)));
    }
    if (v is List) {
      return v.map(_fromJsonSafe).toList();
    }
    return v;
  }

  /// Grava cópia serializável (sem [Timestamp] cru) para `SharedPreferences`.
  Future<void> save(String uid, Map<String, dynamic> profile) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    _memory[u] = Map<String, dynamic>.from(profile);
    _notifyListeners(u, profile);
    if (!AuthGateProfileCachePolicy.shouldPersistToDisk(profile)) {
      return;
    }
    try {
      final enc = firestoreToJsonSafe(profile);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$u', jsonEncode(enc));
      await prefs.remove('auth_gate_profile_json_v1_$u');
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> load(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    final mem = peek(u);
    if (mem != null && (mem['igrejaId'] ?? '').toString().trim().isNotEmpty) {
      return mem;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      var raw = prefs.getString('$_keyPrefix$u');
      raw ??= prefs.getString('auth_gate_profile_json_v1_$u');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(
        _fromJsonSafe(decoded) as Map<dynamic, dynamic>,
      );
      final restored = _restoreFirestoreTimestampsDeep(m) as Map<String, dynamic>;
      if ((restored['igrejaId'] ?? '').toString().trim().isEmpty) {
        return null;
      }
      if (AuthGateProfileCachePolicy.requiresOnlineVerification(restored)) {
        return null;
      }
      _memory[u] = restored;
      return restored;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeEpochMs(int v) => v > 1000000000000 && v < 4102444800000;

  static bool _isTimestampKey(String k) {
    if (k == 'createdAt' || k == 'updatedAt') return true;
    if (k.endsWith('At')) return true;
    if (k.endsWith('Date')) return true;
    return false;
  }

  /// Reconstrói [Timestamp] a partir de ms epoch (gravados por [_toJsonSafe]).
  static dynamic _restoreFirestoreTimestampsDeep(dynamic v) {
    if (v is Map) {
      final out = <String, dynamic>{};
      for (final e in v.entries) {
        final k = e.key.toString();
        final val = e.value;
        if (val is int && _looksLikeEpochMs(val) && _isTimestampKey(k)) {
          try {
            out[k] = Timestamp.fromMillisecondsSinceEpoch(val);
          } catch (_) {
            out[k] = val;
          }
        } else {
          out[k] = _restoreFirestoreTimestampsDeep(val);
        }
      }
      return out;
    }
    if (v is List) {
      return v.map(_restoreFirestoreTimestampsDeep).toList();
    }
    return v;
  }

  Future<void> clear(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return;
    _memory.remove(u);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$u');
      await prefs.remove('auth_gate_profile_json_v1_$u');
    } catch (_) {}
  }
}
