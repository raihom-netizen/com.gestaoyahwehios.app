import 'package:shared_preferences/shared_preferences.dart';

/// Status da cota local (aparelho) — janela de **24 horas** após estourar o limite.
class UtilitariosQuotaStatus {
  final int used;
  final int limit;
  final int remaining;
  final DateTime? unlockAt;
  final bool isAdmin;

  const UtilitariosQuotaStatus({
    required this.used,
    required this.limit,
    required this.remaining,
    required this.unlockAt,
    this.isAdmin = false,
  });

  bool get exhausted => !isAdmin && remaining <= 0;

  /// Ex.: `Liberado em 10/07/2026 às 19h45`
  String? get unlockLabel {
    final at = unlockAt;
    if (at == null || !exhausted) return null;
    return 'Liberado em ${UtilitariosDailyQuotaService.formatUnlockAt(at)}';
  }
}

/// Cota **local** do módulo Utilitários (por usuário, no aparelho).
///
/// - [heavy]: comprimir PDF/imagem → **15** usos
/// - [light]: conversões leves → **15** usos
/// - Ao estourar: bloqueia por **24 horas** a partir desse momento
/// - **Admin / master:** sem limite
///
/// Não usa servidor — só SharedPreferences.
abstract final class UtilitariosDailyQuotaService {
  UtilitariosDailyQuotaService._();

  static const int kHeavyLimitPerDay = 15;
  static const int kLightLimitPerDay = 15;
  static const Duration kLockDuration = Duration(hours: 24);

  static const _kHeavyUsed = 'util_quota_heavy_v2_used_';
  static const _kHeavyUnlock = 'util_quota_heavy_v2_unlock_';
  static const _kLightUsed = 'util_quota_light_v2_used_';
  static const _kLightUnlock = 'util_quota_light_v2_unlock_';

  static String _uidKey(String uid) {
    final clean = uid.trim();
    return clean.isEmpty ? 'anon' : clean;
  }

  static String formatUnlockAt(DateTime at) {
    final d = at.day.toString().padLeft(2, '0');
    final m = at.month.toString().padLeft(2, '0');
    final y = at.year.toString();
    final h = at.hour.toString().padLeft(2, '0');
    final min = at.minute.toString().padLeft(2, '0');
    return '$d/$m/$y às ${h}h$min';
  }

  /// Ex.: `liberado na data 10/07/2026 às 19h45`
  static String unlockPhrase(DateTime at) =>
      'liberado na data ${formatUnlockAt(at)}';

  static Future<UtilitariosQuotaStatus> heavyStatus(
    String uid, {
    bool isAdmin = false,
  }) =>
      _status(
        uid: uid,
        isAdmin: isAdmin,
        usedKey: _kHeavyUsed,
        unlockKey: _kHeavyUnlock,
        limit: kHeavyLimitPerDay,
      );

  static Future<UtilitariosQuotaStatus> lightStatus(
    String uid, {
    bool isAdmin = false,
  }) =>
      _status(
        uid: uid,
        isAdmin: isAdmin,
        usedKey: _kLightUsed,
        unlockKey: _kLightUnlock,
        limit: kLightLimitPerDay,
      );

  static Future<UtilitariosQuotaStatus> _status({
    required String uid,
    required bool isAdmin,
    required String usedKey,
    required String unlockKey,
    required int limit,
  }) async {
    if (isAdmin) {
      return UtilitariosQuotaStatus(
        used: 0,
        limit: limit,
        remaining: limit,
        unlockAt: null,
        isAdmin: true,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final uk = '$usedKey${_uidKey(uid)}';
    final lk = '$unlockKey${_uidKey(uid)}';
    final unlockMs = prefs.getInt(lk);
    DateTime? unlockAt =
        unlockMs != null ? DateTime.fromMillisecondsSinceEpoch(unlockMs) : null;
    var used = prefs.getInt(uk) ?? 0;

    // Janela de 24h já passou → zera.
    if (unlockAt != null && !DateTime.now().isBefore(unlockAt)) {
      await prefs.remove(uk);
      await prefs.remove(lk);
      used = 0;
      unlockAt = null;
    }

    final remaining = (limit - used).clamp(0, limit);
    return UtilitariosQuotaStatus(
      used: used,
      limit: limit,
      remaining: remaining,
      unlockAt: remaining <= 0 ? unlockAt : null,
    );
  }

  /// Retorna `null` se pode usar; senão mensagem com data/hora de liberação.
  static Future<String?> checkHeavy(
    String uid, {
    bool isAdmin = false,
  }) async {
    if (isAdmin) return null;
    final s = await heavyStatus(uid);
    if (!s.exhausted) return null;
    return 'Limite de compressões atingido. ${unlockPhrase(
      s.unlockAt ?? DateTime.now().add(kLockDuration),
    )}.';
  }

  static Future<String?> checkLight(
    String uid, {
    bool isAdmin = false,
  }) async {
    if (isAdmin) return null;
    final s = await lightStatus(uid);
    if (!s.exhausted) return null;
    return 'Limite de conversões atingido. ${unlockPhrase(
      s.unlockAt ?? DateTime.now().add(kLockDuration),
    )}.';
  }

  /// Consome 1 uso pesado. Ao atingir o limite, trava por 24h.
  static Future<void> consumeHeavy(
    String uid, {
    bool isAdmin = false,
  }) async {
    if (isAdmin) return;
    final err = await checkHeavy(uid);
    if (err != null) throw StateError(err);
    await _inc(
      uid: uid,
      usedKey: _kHeavyUsed,
      unlockKey: _kHeavyUnlock,
      limit: kHeavyLimitPerDay,
    );
  }

  /// Consome 1 uso leve. Ao atingir o limite, trava por 24h.
  static Future<void> consumeLight(
    String uid, {
    bool isAdmin = false,
  }) async {
    if (isAdmin) return;
    final err = await checkLight(uid);
    if (err != null) throw StateError(err);
    await _inc(
      uid: uid,
      usedKey: _kLightUsed,
      unlockKey: _kLightUnlock,
      limit: kLightLimitPerDay,
    );
  }

  static Future<void> _inc({
    required String uid,
    required String usedKey,
    required String unlockKey,
    required int limit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final uk = '$usedKey${_uidKey(uid)}';
    final lk = '$unlockKey${_uidKey(uid)}';
    final next = (prefs.getInt(uk) ?? 0) + 1;
    await prefs.setInt(uk, next);
    if (next >= limit) {
      final unlock = DateTime.now().add(kLockDuration);
      await prefs.setInt(lk, unlock.millisecondsSinceEpoch);
    }
  }
}
