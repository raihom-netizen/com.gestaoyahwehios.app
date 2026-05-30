import 'package:gestao_yahweh/services/app_shell_session_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLastLoginIdentifier = 'last_login_identifier';
const String _kLastOAuthProvider = 'last_oauth_provider';

/// Consumido pelo [AuthGate] após `signOut` (uma vez) — força rota em vez de `/` (web) ou `/login`.
const String _kPostSignOutRouteOverride = 'gv_post_signout_route_override';

/// Login automático do painel nas próximas aberturas (web + Android).
const String kAutoPainelLogin = 'auto_painel_login_v1';

/// Após «Trocar conta» — não refazer OAuth silencioso até novo login manual.
const String _kAccountSwitchPending = 'gv_account_switch_pending_v1';

/// Preferências locais para login expresso / reconexão Google silenciosa (alinhado ao Controle Total).
class LoginPreferences {
  LoginPreferences._();

  static String? _memoryLastOAuth;
  static bool _memoryAutoPainel = false;
  static bool _memoryAccountSwitchPending = false;
  static bool? _memoryReturningUser;

  /// Prefs críticas em RAM antes do 1º frame (Controle Total).
  static Future<void> warmUpForStartup() async {
    final prefs = await SharedPreferences.getInstance();
    _memoryLastOAuth =
        (prefs.getString(_kLastOAuthProvider) ?? '').trim().isEmpty
            ? null
            : prefs.getString(_kLastOAuthProvider);
    _memoryAutoPainel = prefs.getBool(kAutoPainelLogin) == true;
    _memoryAccountSwitchPending =
        prefs.getBool(_kAccountSwitchPending) ?? false;
    if (_memoryAccountSwitchPending) {
      _memoryReturningUser = false;
      return;
    }
    final id = (prefs.getString(_kLastLoginIdentifier) ?? '').trim();
    _memoryReturningUser = id.isNotEmpty || _memoryAutoPainel;
  }

  static bool? get startupReturningUser => _memoryReturningUser;

  static bool? get startupAccountSwitchPending => _memoryAccountSwitchPending;

  static Future<bool> isAccountSwitchPending() async {
    if (_memoryAccountSwitchPending) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kAccountSwitchPending) ?? false;
  }

  /// Após login bem-sucedido — sessão permanente neste aparelho até trocar conta.
  static Future<void> markSuccessfulLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAccountSwitchPending, false);
    _memoryAccountSwitchPending = false;
    _memoryReturningUser = true;
  }

  static String? get lastOAuthProviderSync {
    final s = _memoryLastOAuth?.trim().toLowerCase() ?? '';
    if (s.isEmpty) return null;
    return s;
  }

  static bool get autoPainelLoginSync => _memoryAutoPainel;

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

  /// Configurações → «Trocar e-mail de login»: limpa credenciais locais para novo utilizador.
  static Future<void> prepareChurchAccountSwitch() async {
    _memoryLastOAuth = null;
    _memoryAutoPainel = false;
    _memoryReturningUser = false;
    _memoryAccountSwitchPending = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAccountSwitchPending, true);
    await prefs.setString(_kPostSignOutRouteOverride, '/igreja/login');
    await prefs.remove(_kLastLoginIdentifier);
    await prefs.remove(_kLastOAuthProvider);
    await prefs.remove(kAutoPainelLogin);
    await prefs.remove('last_route');
    await prefs.setBool('biometric_enabled', false);
    await prefs.setBool('biometric_asked', true);
    const prefix = 'igreja';
    await prefs.remove('remember_login_$prefix');
    await prefs.remove('saved_login_$prefix');
    await prefs.remove('saved_senha_$prefix');
    await prefs.remove('saved_cpf_$prefix');
    await prefs.remove('remember_login_default');
    await prefs.remove('saved_login_default');
    await prefs.remove('saved_senha_default');
    await prefs.remove('saved_cpf_default');
    await prefs.remove('web_remember_password');
    await prefs.remove('web_saved_login');
    await prefs.remove('web_saved_cpf');
    await prefs.remove('web_saved_senha');
    await AppShellSessionCache.clear();
  }
}
