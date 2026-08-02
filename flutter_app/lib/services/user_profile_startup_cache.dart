import 'package:gestao_yahweh/models/user_profile.dart';

/// Cache leve do perfil Controle Total para abrir formulários sem round-trip.
class UserProfileStartupCache {
  UserProfileStartupCache._();

  static UserProfile? _cached;
  static String? _cachedUid;

  static void seed({required String shellUid, required UserProfile profile}) {
    _cachedUid = shellUid.trim();
    _cached = profile;
  }

  static UserProfile? resolveForShell({required String shellUid}) {
    final uid = shellUid.trim();
    if (uid.isEmpty) return null;
    if (_cachedUid == uid) return _cached;
    return null;
  }

  static void invalidate() {
    _cached = null;
    _cachedUid = null;
  }
}
