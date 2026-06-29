import 'package:shared_preferences/shared_preferences.dart';

/// Credenciais locais (e-mail + senha) em RAM — leitura instantânea no login offline-first.
class LoginCredentialsSnapshot {
  const LoginCredentialsSnapshot({
    this.login = '',
    this.password = '',
    this.remember = false,
  });

  final String login;
  final String password;
  final bool remember;

  bool get hasCredentials =>
      login.trim().isNotEmpty && password.isNotEmpty;
}

/// Cache por contexto (`igreja`, `master`, `default`) — aquecido no arranque.
abstract final class LoginCredentialsCache {
  LoginCredentialsCache._();

  static const _prefixes = ['igreja', 'master', 'default'];
  static final Map<String, LoginCredentialsSnapshot> _ram = {};

  static LoginCredentialsSnapshot? peek(String prefPrefix) {
    final key = prefPrefix.trim().isEmpty ? 'default' : prefPrefix.trim();
    return _ram[key];
  }

  static Future<void> warmUpForStartup() async {
    final prefs = await SharedPreferences.getInstance();
    for (final prefix in _prefixes) {
      _ram[prefix] = _readFromPrefs(prefs, prefix);
    }
  }

  static LoginCredentialsSnapshot _readFromPrefs(
    SharedPreferences prefs,
    String prefix,
  ) {
    final savedLoginKey = 'saved_login_$prefix';
    final savedSenhaKey = 'saved_senha_$prefix';
    final rememberKey = 'remember_login_$prefix';

    var login = (prefs.getString(savedLoginKey) ??
            prefs.getString('saved_cpf_$prefix') ??
            '')
        .trim();

    if (login.isEmpty && (prefix == 'igreja' || prefix == 'default')) {
      login = (prefs.getString('web_saved_login') ??
              prefs.getString('web_saved_cpf') ??
              '')
          .trim();
    }

    var password = (prefs.getString(savedSenhaKey) ?? '').trim();
    if (password.isEmpty && (prefix == 'igreja' || prefix == 'default')) {
      password = (prefs.getString('web_saved_senha') ?? '').trim();
    }

    final remember = prefs.getBool(rememberKey) == true ||
        ((prefix == 'igreja' || prefix == 'default') &&
            prefs.getBool('web_remember_password') == true);

    return LoginCredentialsSnapshot(
      login: login,
      password: password,
      remember: remember,
    );
  }

  static Future<void> write({
    required String prefPrefix,
    required String login,
    required String password,
    required bool remember,
  }) async {
    final prefix = prefPrefix.trim().isEmpty ? 'default' : prefPrefix.trim();
    final prefs = await SharedPreferences.getInstance();
    if (remember && login.trim().isNotEmpty && password.isNotEmpty) {
      await prefs.setString('saved_login_$prefix', login.trim());
      await prefs.setString('saved_senha_$prefix', password);
      await prefs.setBool('remember_login_$prefix', true);
      if (prefix == 'igreja' || prefix == 'default') {
        await prefs.setString('web_saved_login', login.trim());
        await prefs.setString('web_saved_senha', password);
        await prefs.setBool('web_remember_password', true);
      }
    } else {
      await prefs.remove('saved_login_$prefix');
      await prefs.remove('saved_senha_$prefix');
      await prefs.remove('remember_login_$prefix');
      if (prefix == 'igreja' || prefix == 'default') {
        await prefs.remove('web_saved_login');
        await prefs.remove('web_saved_senha');
        await prefs.remove('web_remember_password');
      }
    }
    _ram[prefix] = LoginCredentialsSnapshot(
      login: remember ? login.trim() : '',
      password: remember ? password : '',
      remember: remember,
    );
  }

  static Future<void> clear(String prefPrefix) async {
    await write(
      prefPrefix: prefPrefix,
      login: '',
      password: '',
      remember: false,
    );
  }
}
