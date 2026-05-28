import 'package:shared_preferences/shared_preferences.dart';

const String _kLastLoginIdentifier = 'last_login_identifier';
const String _kLastOAuthProvider = 'last_oauth_provider';

/// Consumido pelo [AuthGate] após `signOut` (uma vez) — força rota em vez de `/` (web) ou `/login`.
const String _kPostSignOutRouteOverride = 'gv_post_signout_route_override';

/// Login automático do painel nas próximas aberturas (web + Android).
const String kAutoPainelLogin = 'auto_painel_login_v1';

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

  /// Lê a rota pós-logout sem apagar (navegação web antes do [FirebaseAuth.signOut]).
  static Future<String?> peekPostSignOutRouteOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_kPostSignOutRouteOverride) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  /// Lê e apaga a rota pós-logout definida antes do [FirebaseAuth.signOut] (ex.: trocar de conta).
  static Future<String?> consumePostSignOutRouteOverride() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_kPostSignOutRouteOverride) ?? '').trim();
    if (v.isEmpty) return null;
    await prefs.remove(_kPostSignOutRouteOverride);
    return v;
  }

  /// Configurações → «Trocar de conta»: próximo redirect do AuthGate vai para o login do painel da igreja
  /// e os campos locais de e-mail/senha «lembrar» ficam limpos para outro utilizador escolher.
  static Future<void> prepareChurchAccountSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPostSignOutRouteOverride, '/igreja/login');
    await prefs.remove(_kLastLoginIdentifier);
    await prefs.remove(_kLastOAuthProvider);
    await prefs.remove(kAutoPainelLogin);
    await prefs.setBool('biometric_enabled', false);
    await prefs.setBool('biometric_asked', true);
    const prefix = 'igreja';
    await prefs.remove('remember_login_$prefix');
    await prefs.remove('saved_login_$prefix');
    await prefs.remove('saved_senha_$prefix');
    await prefs.remove('saved_cpf_$prefix');
    await prefs.remove('web_remember_password');
    await prefs.remove('web_saved_login');
    await prefs.remove('web_saved_cpf');
    await prefs.remove('web_saved_senha');
  }
}
