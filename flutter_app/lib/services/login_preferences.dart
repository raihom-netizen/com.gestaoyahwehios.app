import 'package:shared_preferences/shared_preferences.dart';

const String _kLastLoginIdentifier = 'last_login_identifier';
const String _kLastOAuthProvider = 'last_oauth_provider';

/// Preferências locais para login expresso / reconexão Google silenciosa (alinhado ao Controle Total).
class LoginPreferences {
  LoginPreferences._();

  static Future<String> getLastLoginIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_kLastLoginIdentifier) ?? '').trim();
  }

  static Future<void> setLastLoginIdentifier(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final clean = value.trim();
    if (clean.isEmpty) {
      await prefs.remove(_kLastLoginIdentifier);
      return;
    }
    await prefs.setString(_kLastLoginIdentifier, clean);
  }

  /// Último método com sucesso: `google` | `apple` | `email`.
  static Future<String?> getLastOAuthProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final s = (prefs.getString(_kLastOAuthProvider) ?? '').trim();
    if (s.isEmpty) return null;
    return s;
  }

  static Future<void> setLastOAuthProvider(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final v = value.trim().toLowerCase();
    if (v.isEmpty || (v != 'google' && v != 'apple' && v != 'email')) {
      await prefs.remove(_kLastOAuthProvider);
      return;
    }
    await prefs.setString(_kLastOAuthProvider, v);
  }

  /// Chamado ao sair da conta — evita Google silencioso com identidade errada.
  static Future<void> clearOAuthHints() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastOAuthProvider);
  }
}
