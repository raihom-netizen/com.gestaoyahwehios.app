import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/utils/firestore_json_safe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persiste o perfil resolvido do [AuthGate] para abrir o painel **sem rede**
/// (Android/iOS) com o mesmo utilizador já autenticado localmente.
class AuthProfileCacheService {
  AuthProfileCacheService._();
  static final AuthProfileCacheService instance = AuthProfileCacheService._();

  static const _keyPrefix = 'auth_gate_profile_json_v1_';

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
    try {
      final enc = firestoreToJsonSafe(profile);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_keyPrefix$u', jsonEncode(enc));
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> load(String uid) async {
    final u = uid.trim();
    if (u.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyPrefix$u');
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final m = Map<String, dynamic>.from(
        _fromJsonSafe(decoded) as Map<dynamic, dynamic>,
      );
      return _restoreFirestoreTimestampsDeep(m) as Map<String, dynamic>;
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
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$u');
    } catch (_) {}
  }
}
