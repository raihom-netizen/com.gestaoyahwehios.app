import 'package:shared_preferences/shared_preferences.dart';

/// Sessão «painel aberto com sucesso» — reabertura rápida (padrão Controle Total [AppSessionCache]).
/// Limpar só em sair / trocar conta ([LoginPreferences.prepareChurchAccountSwitch]).
abstract final class AppShellSessionCache {
  AppShellSessionCache._();

  static const _kShellReadyUid = 'gv_shell_ready_uid_v1';
  static const _kShellReadyAtMs = 'gv_shell_ready_at_ms_v1';

  static String? _memoryUid;
  static bool _memoryReady = false;

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    _memoryUid = (prefs.getString(_kShellReadyUid) ?? '').trim();
    _memoryReady = _memoryUid != null && _memoryUid!.isNotEmpty;
  }

  static bool isShellReadyForSync(String? uid) {
    if (uid == null || uid.isEmpty) return false;
    return _memoryReady && _memoryUid == uid;
  }

  static String? cachedUidSync() {
    if (!_memoryReady) return null;
    final u = _memoryUid;
    if (u == null || u.isEmpty) return null;
    return u;
  }

  static Future<void> markShellReady(String uid) async {
    final clean = uid.trim();
    if (clean.isEmpty) return;
    _memoryUid = clean;
    _memoryReady = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShellReadyUid, clean);
    await prefs.setInt(
      _kShellReadyAtMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<void> clear() async {
    _memoryUid = null;
    _memoryReady = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kShellReadyUid);
    await prefs.remove(_kShellReadyAtMs);
  }
}
