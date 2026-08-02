import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:gestao_yahweh/models/controle_total_config.dart';

/// Configurações Controle Total por usuário (`users/{uid}/settings/controle_total`).
class ControleTotalConfigService {
  ControleTotalConfigService();

  final Map<String, ControleTotalConfig> _memory = {};

  Future<ControleTotalConfig> getConfigCacheFirst(String uid) async {
    final key = uid.trim();
    if (key.isEmpty) return const ControleTotalConfig();
    final hit = _memory[key];
    if (hit != null) return hit;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(key)
          .collection('settings')
          .doc('controle_total')
          .get();
      final config = ControleTotalConfig.fromMap(snap.data());
      _memory[key] = config;
      return config;
    } catch (_) {
      const fallback = ControleTotalConfig();
      _memory[key] = fallback;
      return fallback;
    }
  }

  void invalidate([String? uid]) {
    if (uid == null || uid.isEmpty) {
      _memory.clear();
    } else {
      _memory.remove(uid.trim());
    }
  }
}
