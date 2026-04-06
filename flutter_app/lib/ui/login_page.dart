import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/services/auth_cpf_service.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/install_pwa_button.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/version_footer.dart';

class LoginPage extends StatefulWidget {
  final String title;
  final String afterLoginRoute;
  final String? prefillCpf;
  final String? churchLabel;
  /// Logo da igreja (URL https ou path Storage). Se vazio ou falhar ao carregar, usa o asset Gestão YAHWEH.
  final String? churchLogoUrl;
  /// Ex-módulo Frotas removido; mantido para compatibilidade.
  final bool showFleetBranding;
  final bool showGoogleLogin;
  /// Rota ao clicar em Voltar (null = '/').
  final String? backRoute;

  const LoginPage({
    super.key,
    this.title = 'Entrar',
    this.afterLoginRoute = '/app',
    this.prefillCpf,
    this.churchLabel,
    this.churchLogoUrl,
    this.showFleetBranding = false,
    this.showGoogleLogin = false,
    this.backRoute,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _cpfController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _rememberLogin = true; // padrão: salvar para não digitar toda vez
  bool _hasSavedCredentials = false;
  bool _quickBiometricReady = false;
  String? _errorMessage;

  /// Chaves por contexto: Painel Igreja e Painel Master guardam usuário/senha separados.
  String get _prefPrefix {
    if (widget.afterLoginRoute == '/admin') return 'master';
    if (widget.afterLoginRoute == '/painel') return 'igreja';
    return 'default';
  }

  String get _prefRememberLogin => 'remember_login_$_prefPrefix';
  String get _prefSavedCpf => 'saved_cpf_$_prefPrefix';
  String get _prefSavedSenha => 'saved_senha_$_prefPrefix';
  // compatibilidade com versão anterior (web-only)
  static const _legacyPrefRememberWeb = 'web_remember_password';
  static const _legacyPrefWebCpf = 'web_saved_cpf';
  static const _legacyPrefWebSenha = 'web_saved_senha';

  @override
  void initState() {
    super.initState();
    final pre = (widget.prefillCpf ?? '').trim();
    if (pre.isNotEmpty) {
      _cpfController.text = pre;
    }
    _cpfController.addListener(_clearError);
    _senhaController.addListener(_clearError);
    _loadSavedCredentials();
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _cpfController.removeListener(_clearError);
    _senhaController.removeListener(_clearError);
    _cpfController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    // Migração: legado (chaves antigas sem sufixo) só para contexto igreja/default
    final legacyCpf = (_prefPrefix == 'igreja' || _prefPrefix == 'default')
        ? prefs.getString(_legacyPrefWebCpf)
        : null;
    final legacySenha = (_prefPrefix == 'igreja' || _prefPrefix == 'default')
        ? prefs.getString(_legacyPrefWebSenha)
        : null;
    final legacyRemember = (_prefPrefix == 'igreja' || _prefPrefix == 'default')
        ? (prefs.getBool(_legacyPrefRememberWeb) == true)
        : false;

    final savedCpf = (prefs.getString(_prefSavedCpf) ?? legacyCpf ?? '').trim();
    final savedSenha = prefs.getString(_prefSavedSenha) ?? legacySenha ?? '';
    final remember = (prefs.getBool(_prefRememberLogin) == true) || legacyRemember;

    if (!mounted) return;
    if (_cpfController.text.trim().isEmpty && savedCpf.isNotEmpty) {
      _cpfController.text = savedCpf;
    }
    if (savedSenha.isNotEmpty) {
      _senhaController.text = savedSenha;
    }
    _hasSavedCredentials = savedCpf.isNotEmpty && savedSenha.isNotEmpty;
    if (remember && savedCpf.isNotEmpty && savedSenha.isNotEmpty) {
      setState(() => _rememberLogin = true);
    }
    await _refreshQuickBiometricState();
  }

  Future<void> _persistCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberLogin) {
      await prefs.setString(_prefSavedCpf, _cpfController.text.trim());
      await prefs.setString(_prefSavedSenha, _senhaController.text);
      await prefs.setBool(_prefRememberLogin, true);
      if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
        await prefs.setString(_legacyPrefWebCpf, _cpfController.text.trim());
        await prefs.setString(_legacyPrefWebSenha, _senhaController.text);
        await prefs.setBool(_legacyPrefRememberWeb, true);
      }
      return;
    }

    await prefs.remove(_prefSavedCpf);
    await prefs.remove(_prefSavedSenha);
    await prefs.setBool(_prefRememberLogin, false);
    if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
      await prefs.remove(_legacyPrefWebCpf);
      await prefs.remove(_legacyPrefWebSenha);
      await prefs.setBool(_legacyPrefRememberWeb, false);
    }
    _hasSavedCredentials = false;
    await _refreshQuickBiometricState();
  }

  Future<void> _refreshQuickBiometricState() async {
    if (kIsWeb) {
      if (mounted) setState(() => _quickBiometricReady = false);
      return;
    }
    final ready = _hasSavedCredentials && await BiometricService().canUseQuickBiometricLogin();
    if (mounted) setState(() => _quickBiometricReady = ready);
  }

  Future<void> _forgetThisDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSavedCpf);
    await prefs.remove(_prefSavedSenha);
    await prefs.setBool(_prefRememberLogin, false);
    if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
      await prefs.remove(_legacyPrefWebCpf);
      await prefs.remove(_legacyPrefWebSenha);
      await prefs.setBool(_legacyPrefRememberWeb, false);
    }
    await BiometricService().disableForThisDevice();

    if (!mounted) return;
    setState(() {
      _rememberLogin = false;
      _hasSavedCredentials = false;
      _quickBiometricReady = false;
      _cpfController.clear();
      _senhaController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Credenciais removidas deste dispositivo.')),
    );
  }

  Future<void> _onEntrarComBiometria() async {
    if (kIsWeb) return;
    if (_cpfController.text.trim().isEmpty || _senhaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há credenciais salvas neste dispositivo.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final okBio = await BiometricService().authenticate();
      if (!okBio) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometria não confirmada.')),
        );
        return;
      }

      final service = AuthCpfService();
      await service.signInByCpf(
        cpf: _cpfController.text.trim(),
        senha: _senhaController.text,
      );

      if (!mounted) return;
      final versionOk = await _ensureLatestVersion();
      if (!versionOk) {
        await FirebaseAuth.instance.signOut();
        return;
      }

      Navigator.pushReplacementNamed(context, widget.afterLoginRoute);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'CPF ou e-mail não encontrado.',
        'wrong-password' => 'Senha incorreta.',
        'invalid-credential' => 'Credenciais inválidas.',
        _ => 'Falha no login: ${e.code}',
      };
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Falha no login. Tente novamente.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha no login biométrico: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _ensureLatestVersion() async {
    final vr = await VersionService.instance.check();
    if (!vr.outdated || !vr.force) return true;

    if (!mounted) return false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Atualização necessária'),
        content: Text(
          vr.message.isNotEmpty
              ? vr.message
              : 'Seu app está desatualizado (v$appVersion).\nPara continuar, atualize para a versão ${vr.current}.',
        ),
        actions: [
          if (vr.updateUrl.isNotEmpty)
            FilledButton.icon(
              onPressed: () => VersionService.instance.openUpdateUrl(vr.updateUrl),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Atualizar'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
    return false;
  }

  Future<void> _onResetSenha() async {
    final cpfOuEmail = _cpfController.text.trim();
    if (cpfOuEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite seu CPF ou e-mail para receber o link de recuperação no seu e-mail.')),
      );
      return;
    }
    setState(() => _loading = true);

    try {
      final service = AuthCpfService();
      await service.sendPasswordResetByCpf(cpfOuEmail);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se o CPF ou e-mail estiver cadastrado, enviamos um link para redefinição da senha.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'user-not-found'
          ? 'CPF ou e-mail não encontrado. Verifique se o cadastro foi ativado e se o login foi criado (peça ao gestor "Criar login" se necessário).'
          : 'Não foi possível enviar o link: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar o link. Tente novamente ou entre em contato com a igreja.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        final gsi = GoogleSignIn(scopes: const ['email', 'profile']);
        final acc = await gsi.signIn();
        if (acc == null) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        final ga = await acc.authentication;
        final cred = GoogleAuthProvider.credential(
          accessToken: ga.accessToken,
          idToken: ga.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(cred);
      }
      if (!mounted) return;
      final isAdminRoute = widget.afterLoginRoute == '/admin';
      if (!isAdminRoute) {
        final versionOk = await _ensureLatestVersion();
        if (!versionOk) {
          await FirebaseAuth.instance.signOut();
          if (!kIsWeb) {
            try {
              await GoogleSignIn().signOut();
            } catch (_) {}
          }
          return;
        }
      }
      if (mounted) setState(() => _errorMessage = null);
      Navigator.pushReplacementNamed(context, widget.afterLoginRoute);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? e.code;
      final low = msg.toString().toLowerCase();
      final isDomain =
          low.contains('domain') || low.contains('authorized');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kIsWeb && isDomain
              ? 'Adicione este domínio em Firebase Console > Authentication > Authorized domains.'
              : 'Falha no Google: $msg'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onEntrar() async {
    final cpf = _cpfController.text.trim();
    final senha = _senhaController.text;

    if (cpf.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe CPF ou e-mail e senha.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final service = AuthCpfService();
      await service.signInByCpf(cpf: cpf, senha: senha);

      if (!mounted) return;
      // Painel Master: não bloquear por versão (admin precisa acessar sempre)
      final isAdminRoute = widget.afterLoginRoute == '/admin';
      if (!isAdminRoute) {
        final versionOk = await _ensureLatestVersion();
        if (!versionOk) {
          await FirebaseAuth.instance.signOut();
          return;
        }
      }
      _hasSavedCredentials = _cpfController.text.trim().isNotEmpty && _senhaController.text.isNotEmpty;
      await _persistCredentials();
      await BiometricService().maybeEnableBiometrics(context);
      await _refreshQuickBiometricState();
      if (mounted) setState(() => _errorMessage = null);
      Navigator.pushReplacementNamed(context, widget.afterLoginRoute);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'CPF ou e-mail não encontrado.',
        'invalid-email' => 'E-mail inválido.',
        'wrong-password' => 'Senha incorreta.',
        'invalid-credential' => 'Credenciais inválidas.',
        _ => 'Falha no login: ${e.code}',
      };
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Falha ao conectar. Tente novamente.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha no login: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onPasteSenha() async {
    final data = await Clipboard.getData('text/plain');
    final text = (data?.text ?? '').trim();

    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Área de transferência vazia.')),
      );
      return;
    }

    _senhaController.text = text;
    _senhaController.selection = TextSelection.fromPosition(
      TextPosition(offset: _senhaController.text.length),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Senha colada com sucesso.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
    );
  }

  Future<void> _onCopySenha() async {
    final senha = _senhaController.text;
    if (senha.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite ou cole uma senha primeiro.')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: senha));
    if (!mounted) return;
ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha copiada para a área de transferência.', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green),
      );
  }

  /// Login do Painel Master: só marca Gestão YAHWEH (nunca logo de igreja).
  bool get _isMasterAdminLogin => widget.afterLoginRoute == '/admin';

  /// Android/iOS — painel da igreja: tela única moderna (planos só na web).
  bool get _nativeChurchLogin =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      widget.afterLoginRoute == '/painel';

  /// Google: app (igreja) e web quando [showGoogleLogin]; nunca no login master.
  bool get _showGoogleButton =>
      widget.afterLoginRoute == '/painel' &&
      (!kIsWeb || widget.showGoogleLogin);

  Widget _buildNativeMobileChurchLogin(BuildContext context) {
    const deepBlue = Color(0xFF0A3D91);
    const midBlue = Color(0xFF1565C0);
    final theme = ThemeCleanPremium.primary;

    Widget logoBig() {
      return Image.asset(
        'assets/LOGO_GESTAO_YAHWEH.png',
        height: 100,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/icon/app_icon.png',
          height: 92,
          fit: BoxFit.contain,
        ),
      );
    }

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [deepBlue, midBlue, Color(0xFF1E40AF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      logoBig(),
                      const SizedBox(height: 10),
                      const Text(
                        'Gestão YAHWEH',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Gestor ou membro — entre com CPF/e-mail ou Google.\n'
                        'Se estiver vinculado a uma igreja, o painel abre em seguida.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Material(
                        color: Colors.white,
                        elevation: 8,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _cpfController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: 'CPF ou e-mail',
                                  hintText: '12345678901 ou seu@email.com',
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _senhaController,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  labelText: 'Senha',
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                              ),
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              CheckboxListTile(
                                value: _rememberLogin,
                                onChanged: (v) => setState(
                                    () => _rememberLogin = v ?? false),
                                title: const Text(
                                  'Lembrar neste aparelho',
                                  style: TextStyle(fontSize: 14),
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                contentPadding: EdgeInsets.zero,
                                activeColor: theme,
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: _loading ? null : _onEntrar,
                                child: _loading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Entrar'),
                              ),
                              if (_quickBiometricReady) ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed:
                                      _loading ? null : _onEntrarComBiometria,
                                  icon: const Icon(Icons.fingerprint_rounded),
                                  label: const Text('Entrar com biometria'),
                                ),
                              ],
                              if (_showGoogleButton) ...[
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(child: Divider(color: Colors.grey.shade300)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        'ou',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Expanded(child: Divider(color: Colors.grey.shade300)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1E293B),
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: Colors.grey.shade300),
                                    ),
                                  ),
                                  onPressed: _loading ? null : _onGoogleSignIn,
                                  icon: const FaIcon(
                                    FontAwesomeIcons.google,
                                    size: 18,
                                  ),
                                  label: const Text('Continuar com Google'),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Center(
                                child: TextButton(
                                  onPressed: _loading ? null : _onResetSenha,
                                  child: const Text('Esqueci a senha'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Column(
                  children: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, '/login_admin'),
                      child: Text(
                        'Acesso painel master',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  children: [
                    Text(
                      '"$kVersiculoRodape"\n— $kVersiculoRef',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.65),
                        height: 1.25,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'v$appVersion',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandLogoWidget({
    required double height,
    required Color fallbackIconColor,
  }) {
    final raw = _isMasterAdminLogin
        ? ''
        : (widget.churchLogoUrl ?? '').trim();
    Widget gestaoYahwehAssets() {
      Widget lastResort() {
        if (_isMasterAdminLogin) {
          return _MasterGestaoYahwehMark(
            maxHeight: height,
            foreground: fallbackIconColor,
          );
        }
        return Icon(
          Icons.church_rounded,
          size: height * 0.85,
          color: fallbackIconColor,
        );
      }

      return Image.asset(
        'assets/LOGO_GESTAO_YAHWEH.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/icon/app_icon.png',
          height: height * 0.92,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => lastResort(),
        ),
      );
    }

    if (raw.isEmpty) {
      return gestaoYahwehAssets();
    }

    return SafeNetworkImage(
      imageUrl: raw,
      height: height,
      fit: BoxFit.contain,
      errorWidget: gestaoYahwehAssets(),
      placeholder: SizedBox(
        height: height,
        width: height * 1.2,
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_nativeChurchLogin) {
      return _buildNativeMobileChurchLogin(context);
    }

    final theme = ThemeCleanPremium.primary;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 26),
          onPressed: () {
            final target = widget.backRoute ?? '/';
            Navigator.of(context, rootNavigator: true)
                .pushNamedAndRemoveUntil(target, (_) => false);
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 32,
              child: _brandLogoWidget(
                height: 32,
                fallbackIconColor: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (kIsWeb) const InstallPwaButton(),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _brandLogoWidget(
                        height: 88,
                        fallbackIconColor: theme,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _cpfController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'CPF ou e-mail',
                          hintText: 'Ex.: 12345678901 ou seu@email.com',
                          helperText: 'Entre com o mesmo e-mail do cadastro ou só o CPF (11 dígitos).',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _senhaController,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                      ],
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _rememberLogin,
                        onChanged: (v) => setState(() => _rememberLogin = v ?? false),
                        title: const Text('Lembrar usuário e senha', style: TextStyle(fontSize: 14)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: theme,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loading ? null : _onEntrar,
                        child: _loading
                            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Entrar'),
                      ),
                      if (_showGoogleButton) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'ou',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey.shade300)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E293B),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: _loading ? null : _onGoogleSignIn,
                          icon: const FaIcon(FontAwesomeIcons.google, size: 18),
                          label: const Text('Continuar com Google'),
                        ),
                      ],
                      TextButton(
                        onPressed: _loading ? null : _onResetSenha,
                        child: const Text('Esqueci a senha'),
                      ),
                      if (widget.afterLoginRoute == '/painel' && kIsWeb) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/login_admin'),
                          child: const Text('Acesso painel master'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VersionFooter(),
        ],
      ),
    );
  }
}

/// Quando os PNG da app não carregam no dispositivo, o master continua com identidade Gestão YAHWEH
/// (alinhado ao drawer do [AdminPanelPage], não ícone de igreja genérico).
class _MasterGestaoYahwehMark extends StatelessWidget {
  final double maxHeight;
  final Color foreground;

  const _MasterGestaoYahwehMark({
    required this.maxHeight,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
          maxWidth: maxHeight * 4,
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.admin_panel_settings_rounded,
                color: foreground,
                size: 28,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Gestão',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    'YAHWEH',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      height: 1.05,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginBrandHeader extends StatelessWidget {
  const _LoginBrandHeader({this.showFleetBranding = true});

  final bool showFleetBranding;

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: ThemeCleanPremium.spaceLg, bottom: ThemeCleanPremium.spaceSm),
          child: Center(
            child: SizedBox(
              height: 80,
              child: Image.asset(
                'assets/LOGO_GESTAO_YAHWEH.png',
                height: 80,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/icon/app_icon.png',
                  height: 72,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.church_rounded, size: 64, color: primary),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: ThemeCleanPremium.spaceMd),
          child: Text(
            'Simples, prático e confiável',
            style: TextStyle(
              color: ThemeCleanPremium.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        if (showFleetBranding) ...[
          Divider(thickness: 1, color: Colors.grey.shade200),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          Text(
            'CONTROLE DE FROTAS',
            style: TextStyle(
              color: primary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: ThemeCleanPremium.spaceSm),
          SizedBox(
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 140,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primary, ThemeCleanPremium.primaryLight],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    boxShadow: [BoxShadow(color: primary.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 6))],
                  ),
                ),
                Positioned(left: 16, child: CircleAvatar(radius: 18, backgroundColor: Colors.white.withOpacity(0.95), child: Icon(Icons.local_shipping_rounded, color: primary, size: 22))),
                Positioned(right: 16, child: CircleAvatar(radius: 18, backgroundColor: Colors.white.withOpacity(0.95), child: Icon(Icons.directions_car_filled_rounded, color: ThemeCleanPremium.primaryLight, size: 22))),
                const Positioned(bottom: 8, child: Icon(Icons.route_rounded, color: Colors.white, size: 22)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
