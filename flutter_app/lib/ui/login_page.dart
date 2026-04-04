import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/services/auth_cpf_service.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/install_pwa_button.dart';
import 'package:gestao_yahweh/ui/widgets/version_footer.dart';

class LoginPage extends StatefulWidget {
  final String title;
  final String afterLoginRoute;
  final String? prefillCpf;
  final String? churchLabel;
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
    if (!kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login com Google disponível na versão web.')),
        );
      }
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, widget.afterLoginRoute);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? e.code;
      final isDomain = msg.toString().toLowerCase().contains('domain') || msg.toString().toLowerCase().contains('authorized');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isDomain
              ? 'Adicione este domínio em Firebase Console > Authentication > Authorized domains.'
              : 'Falha no login: $msg'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final theme = ThemeCleanPremium.primary;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 26),
          onPressed: () {
            Navigator.of(context).pushReplacementNamed(widget.backRoute ?? '/');
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 32,
              child: Image.asset(
                'assets/LOGO_GESTAO_YAHWEH.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.church_rounded, color: Colors.white, size: 28),
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
        actions: const [InstallPwaButton()],
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
                      Image.asset(
                        'assets/LOGO_GESTAO_YAHWEH.png',
                        height: 88,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.church_rounded, size: 72, color: theme),
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
                      TextButton(
                        onPressed: _loading ? null : _onResetSenha,
                        child: const Text('Esqueci a senha'),
                      ),
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
                errorBuilder: (_, __, ___) => Icon(Icons.church_rounded, size: 64, color: primary),
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
