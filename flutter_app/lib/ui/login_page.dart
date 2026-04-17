import 'dart:async' show TimeoutException, unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/services/auth_cpf_service.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:gestao_yahweh/data/planos_oficiais.dart';
import 'package:gestao_yahweh/ui/widgets/install_pwa_button.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';
import 'package:gestao_yahweh/ui/widgets/update_checker.dart';
import 'package:gestao_yahweh/ui/widgets/version_footer.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_official_social_bar.dart';
import 'package:intl/intl.dart';

enum _SmartStep { choosePersona, gestorBranch, credentials }

class LoginPage extends StatefulWidget {
  final String title;
  final String afterLoginRoute;
  final String? prefillEmail;
  final String? churchLabel;
  /// Logo da igreja (URL https ou path Storage). Se vazio ou falhar ao carregar, usa o asset Gestão YAHWEH.
  final String? churchLogoUrl;
  /// Ex-módulo Frotas removido; mantido para compatibilidade.
  final bool showFleetBranding;
  /// Rota ao clicar em Voltar (null = '/').
  final String? backRoute;

  /// Fluxo Membro vs Gestor + login Google no painel da igreja.
  /// `null` = ativo quando [afterLoginRoute] é `/painel` e não é login master.
  final bool? showSmartLoginFlow;

  const LoginPage({
    super.key,
    this.title = 'Entrar',
    this.afterLoginRoute = '/app',
    this.prefillEmail,
    this.churchLabel,
    this.churchLogoUrl,
    this.showFleetBranding = false,
    this.backRoute,
    this.showSmartLoginFlow,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool _rememberLogin = true; // padrão: salvar para não digitar toda vez
  bool _hasSavedCredentials = false;
  bool _quickBiometricReady = false;
  /// App iOS/Android: com biometria + credenciais salvas, o usuário pode exibir e-mail/senha.
  bool _showManualCredentialFields = false;
  String? _errorMessage;

  _SmartStep _smartStep = _SmartStep.choosePersona;

  /// Após escolher persona: membro (true) ou gestor já cadastrado (false).
  bool _credentialsAsMembro = true;

  /// Chaves por contexto: Painel Igreja e Painel Master guardam usuário/senha separados.
  String get _prefPrefix {
    if (widget.afterLoginRoute == '/admin') return 'master';
    if (widget.afterLoginRoute == '/painel') return 'igreja';
    return 'default';
  }

  String get _prefRememberLogin => 'remember_login_$_prefPrefix';
  String get _prefSavedLogin => 'saved_login_$_prefPrefix';
  String get _prefSavedSenha => 'saved_senha_$_prefPrefix';
  // compatibilidade com versão anterior (web-only)
  static const _legacyPrefRememberWeb = 'web_remember_password';
  static const _legacyPrefWebLogin = 'web_saved_login';
  static const _legacyPrefWebCpf = 'web_saved_cpf';
  static const _legacyPrefWebSenha = 'web_saved_senha';

  @override
  void initState() {
    super.initState();
    if (!_useSmartFlow) {
      _smartStep = _SmartStep.credentials;
    }
    final pre = (widget.prefillEmail ?? '').trim();
    if (pre.isNotEmpty) {
      _emailController.text = pre;
    }
    _emailController.addListener(_clearError);
    _senhaController.addListener(_clearError);
    _loadSavedCredentials();
    if (kIsWeb &&
        widget.afterLoginRoute == '/painel' &&
        !_isMasterAdminLogin) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _completeGoogleRedirectIfNeeded());
    }
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _emailController.removeListener(_clearError);
    _senhaController.removeListener(_clearError);
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    // Migração: legado (chaves antigas sem sufixo) só para contexto igreja/default
    final legacyWebLogin = (_prefPrefix == 'igreja' || _prefPrefix == 'default')
        ? (prefs.getString(_legacyPrefWebLogin) ?? prefs.getString(_legacyPrefWebCpf))
        : null;
    final legacySenha = (_prefPrefix == 'igreja' || _prefPrefix == 'default')
        ? prefs.getString(_legacyPrefWebSenha)
        : null;
    final legacyRemember = (_prefPrefix == 'igreja' || _prefPrefix == 'default')
        ? (prefs.getBool(_legacyPrefRememberWeb) == true)
        : false;

    // saved_cpf_* = chave antiga (podia ser CPF ou e-mail)
    final legacySavedCpfKey = 'saved_cpf_$_prefPrefix';
    var savedLogin = (prefs.getString(_prefSavedLogin) ??
            prefs.getString(legacySavedCpfKey) ??
            legacyWebLogin ??
            '')
        .trim();

    // App (login estilo divulgação): apenas e-mail — não resolver CPF para preencher o campo.
    if (savedLogin.isNotEmpty && !savedLogin.contains('@')) {
      if (_nativeChurchLogin) {
        savedLogin = '';
      } else {
        final digits = savedLogin.replaceAll(RegExp(r'[^0-9]'), '');
        if (digits.length == 11) {
          final resolved = await AuthCpfService().resolveEmailByCpf(digits);
          if (resolved != null && resolved.isNotEmpty) {
            savedLogin = resolved;
            await prefs.setString(_prefSavedLogin, resolved);
            if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
              await prefs.setString(_legacyPrefWebLogin, resolved);
            }
          }
        }
      }
    }

    final savedSenha = prefs.getString(_prefSavedSenha) ?? legacySenha ?? '';
    final remember = (prefs.getBool(_prefRememberLogin) == true) || legacyRemember;

    if (!mounted) return;
    if (_emailController.text.trim().isEmpty && savedLogin.isNotEmpty) {
      _emailController.text = savedLogin;
    }
    if (savedSenha.isNotEmpty) {
      _senhaController.text = savedSenha;
    }
    _hasSavedCredentials = savedLogin.isNotEmpty && savedSenha.isNotEmpty;
    if (remember && savedLogin.isNotEmpty && savedSenha.isNotEmpty) {
      setState(() => _rememberLogin = true);
    }
    await _refreshQuickBiometricState();
  }

  Future<void> _persistCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberLogin) {
      final login = _emailController.text.trim();
      await prefs.setString(_prefSavedLogin, login);
      await prefs.remove('saved_cpf_$_prefPrefix');
      await prefs.setString(_prefSavedSenha, _senhaController.text);
      await prefs.setBool(_prefRememberLogin, true);
      if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
        await prefs.setString(_legacyPrefWebLogin, login);
        await prefs.remove(_legacyPrefWebCpf);
        await prefs.setString(_legacyPrefWebSenha, _senhaController.text);
        await prefs.setBool(_legacyPrefRememberWeb, true);
      }
      return;
    }

    await prefs.remove(_prefSavedLogin);
    await prefs.remove('saved_cpf_$_prefPrefix');
    await prefs.remove(_prefSavedSenha);
    await prefs.setBool(_prefRememberLogin, false);
    if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
      await prefs.remove(_legacyPrefWebLogin);
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
    await prefs.remove(_prefSavedLogin);
    await prefs.remove('saved_cpf_$_prefPrefix');
    await prefs.remove(_prefSavedSenha);
    await prefs.setBool(_prefRememberLogin, false);
    if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
      await prefs.remove(_legacyPrefWebLogin);
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
      _emailController.clear();
      _senhaController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Credenciais removidas deste dispositivo.')),
    );
  }

  Future<void> _onEntrarComBiometria() async {
    if (kIsWeb) return;
    if (_emailController.text.trim().isEmpty || _senhaController.text.isEmpty) {
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
      await service.signInWithEmail(
        email: _emailController.text.trim(),
        senha: _senhaController.text,
      );

      if (!mounted) return;
      final ok = await _finalizeChurchLoginAfterAuth(persistPasswordFields: true);
      if (ok) {
        BiometricService.markBiometricVerifiedForNextPainelEntry();
      }
      if (!ok) return;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'E-mail não encontrado.',
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
    if (!vr.outdated) return true;
    if (!mounted) return true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      unawaited(showPremiumVersionUpdateDialog(context, vr));
    });
    return true;
  }

  /// Após Firebase Auth válido: versão, credenciais locais, navegação.
  Future<bool> _finalizeChurchLoginAfterAuth({
    required bool persistPasswordFields,
  }) async {
    if (!mounted) return false;
    final isAdminRoute = widget.afterLoginRoute == '/admin';
    if (!isAdminRoute) {
      final versionOk = await _ensureLatestVersion();
      if (!versionOk) {
        await FirebaseAuth.instance.signOut();
        return false;
      }
    }
    if (persistPasswordFields) {
      _hasSavedCredentials = _emailController.text.trim().isNotEmpty &&
          _senhaController.text.isNotEmpty;
      await _persistCredentials();
      if (!_nativeChurchLogin) {
        if (!mounted) return false;
        await BiometricService().maybeEnableBiometrics(context);
        await _refreshQuickBiometricState();
      }
    } else {
      final u = FirebaseAuth.instance.currentUser;
      final login = (u?.email ?? _emailController.text).trim();
      if (login.isNotEmpty) {
        _emailController.text = login;
      }
      if (_rememberLogin && login.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefSavedLogin, login);
        await prefs.remove('saved_cpf_$_prefPrefix');
        await prefs.remove(_prefSavedSenha);
        await prefs.setBool(_prefRememberLogin, true);
        if (_prefPrefix == 'igreja' || _prefPrefix == 'default') {
          await prefs.setString(_legacyPrefWebLogin, login);
          await prefs.remove(_legacyPrefWebCpf);
          await prefs.remove(_legacyPrefWebSenha);
          await prefs.setBool(_legacyPrefRememberWeb, true);
        }
      }
      _hasSavedCredentials = false;
      await _refreshQuickBiometricState();
    }
    if (mounted) setState(() => _errorMessage = null);
    if (!mounted) return false;
    Navigator.pushReplacementNamed(context, widget.afterLoginRoute);
    return true;
  }

  Future<void> _afterGoogleSignInSuccess() async {
    final fn = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable(
      'repairMyChurchBinding',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );
    try {
      await fn.call(<String, dynamic>{}).timeout(const Duration(seconds: 46));
    } on FirebaseFunctionsException catch (e) {
      final code = (e.code).toLowerCase();
      if (code.contains('not-found')) rethrow;
      debugPrint('repairMyChurchBinding (soft fail): ${e.code} ${e.message}');
    } on TimeoutException catch (e) {
      debugPrint('repairMyChurchBinding: timeout $e');
    } catch (e, st) {
      debugPrint('repairMyChurchBinding: $e\n$st');
    }
    await FirebaseAuth.instance.currentUser?.getIdToken(true);
    await _finalizeChurchLoginAfterAuth(persistPasswordFields: false);
  }

  /// Mensagens em português para erros comuns do Google Auth na web.
  String _messageForGoogleWebAuth(FirebaseAuthException e) {
    final code = e.code.toLowerCase();
    if (code.contains('account-exists-with-different-credential')) {
      return 'Este e-mail já tem login com senha. Use e-mail e senha ou peça ao gestor para alinhar o acesso.';
    }
    if (code.contains('invalid-credential')) {
      return 'Não foi possível validar o login com Google. Tente de novo ou use e-mail e senha.';
    }
    if (code.contains('popup-closed') || code.contains('cancel')) {
      return 'Login Google cancelado.';
    }
    if (code.contains('unauthorized-domain')) {
      return 'Este domínio não está autorizado para login Google. '
          'Em Firebase Console → Authentication → Settings, adicione o domínio em "Authorized domains".';
    }
    if (code.contains('operation-not-allowed')) {
      return 'Login com Google não está ativado no projeto. '
          'Ative o provedor Google em Firebase Console → Authentication → Sign-in method.';
    }
    if (code.contains('web-storage-unsupported') ||
        code.contains('storage-unsupported')) {
      return 'O navegador bloqueou armazenamento necessário para o login. '
          'Saia do modo anônimo ou permita cookies e armazenamento para este site.';
    }
    return e.message ?? e.code;
  }

  /// Web: conclui login após `signInWithRedirect` (quando popup falha ou navegador bloqueia).
  Future<void> _completeGoogleRedirectIfNeeded() async {
    if (!kIsWeb || !mounted) return;
    if (widget.afterLoginRoute != '/painel' || _isMasterAdminLogin) return;
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      if (result.user == null) return;
      if (!mounted) return;
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
      await _afterGoogleSignInSuccess();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      final msg = _messageForGoogleWebAuth(e);
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      final code = (e.code).toLowerCase();
      final msg = code.contains('not-found')
          ? (_credentialsAsMembro
              ? 'Não encontramos cadastro de membro ou gestor com este Google. '
                  'Confira se o e-mail na igreja é o mesmo da conta Google. '
                  'Se você é gestor e quer cadastrar uma igreja nova, volte e escolha a opção correspondente.'
              : 'Não encontramos uma igreja vinculada a este Google. '
                  'Use e-mail e senha de gestor ou cadastre sua igreja na opção correta.')
          : (e.message ?? e.code);
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _errorMessage = 'Falha ao concluir login Google.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao concluir login Google: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onGoogleChurchLogin() async {
    if (!_showChurchGoogleButton || _loading) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      UserCredential cred;
      if (kIsWeb) {
        final provider = firebaseWebGoogleAuthProvider();
        try {
          cred =
              await FirebaseAuth.instance.signInWithPopup(provider);
        } on FirebaseAuthException catch (e) {
          final code = e.code.toLowerCase();
          // Popup bloqueado, erro interno comum em Safari/embedded ou redirect pendente.
          if (code == 'popup-blocked' ||
              code == 'internal-error' ||
              (code.contains('popup') && code.contains('blocked'))) {
            await FirebaseAuth.instance.signInWithRedirect(provider);
            return;
          }
          rethrow;
        }
      } else {
        try {
          await appGoogleSignIn().signOut();
        } catch (_) {}
        final googleUser = await appGoogleSignIn().signIn();
        if (googleUser == null) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        final ga = await googleUser.authentication;
        final idTok = ga.idToken;
        if (idTok == null || idTok.isEmpty) {
          if (mounted) setState(() => _loading = false);
          const msg =
              'Google não retornou o token de identificação. Atualize o Google Play Services (Android), '
              'verifique data e hora do aparelho e tente de novo. Se persistir, use e-mail e senha.';
          if (mounted) {
            setState(() => _errorMessage = msg);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text(msg)));
          }
          return;
        }
        final oauth = GoogleAuthProvider.credential(
          accessToken: ga.accessToken,
          idToken: idTok,
        );
        cred = await FirebaseAuth.instance.signInWithCredential(oauth);
      }

      if (cred.user == null || !mounted) return;

      await _afterGoogleSignInSuccess();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      final msg = _messageForGoogleWebAuth(e);
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      final code = (e.code).toLowerCase();
      final msg = code.contains('not-found')
          ? (_credentialsAsMembro
              ? 'Não encontramos cadastro de membro ou gestor com este Google. '
                  'Confira se o e-mail na igreja é o mesmo da conta Google. '
                  'Se você é gestor e quer cadastrar uma igreja nova, volte e escolha a opção correspondente.'
              : 'Não encontramos uma igreja vinculada a este Google. '
                  'Use e-mail e senha de gestor ou cadastre sua igreja na opção correta.')
          : (e.message ?? e.code);
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on MissingPluginException catch (e) {
      if (!mounted) return;
      final msg =
          'Login com Google não está disponível nesta plataforma. Use e-mail e senha ou acesse pelo navegador.';
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$msg\n${e.message}')));
    } on PlatformException catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      final isDevErr = isGoogleSignInAndroidConfigError(e);
      final msg = isDevErr
          ? 'Login Google indisponível neste aparelho (assinatura do app). '
              'Use e-mail e senha. Se o problema continuar, o gestor deve '
              'conferir o SHA-1 no Firebase Console ou reinstalar o app pela loja.'
          : 'Falha no login com Google. Tente de novo ou use e-mail e senha.';
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$msg\n(${e.code})')));
    } catch (e) {
      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      final msg = 'Falha no login com Google. Tente de novo ou use e-mail e senha.';
      setState(() => _errorMessage = msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$msg\n$e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onResetSenha() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite seu e-mail para receber o link de recuperação.')),
      );
      return;
    }
    if (!AuthCpfService.looksLikeEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite um e-mail válido.')),
      );
      return;
    }
    setState(() => _loading = true);

    try {
      final service = AuthCpfService();
      await service.sendPasswordResetEmailOnly(email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Se o e-mail estiver cadastrado, enviamos um link para redefinição da senha.',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'user-not-found'
          ? 'E-mail não encontrado. Verifique se o cadastro foi ativado e se o login foi criado (peça ao gestor "Criar login" se necessário).'
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

  Future<void> _onEntrar() async {
    final email = _emailController.text.trim();
    final senha = _senhaController.text;

    if (email.isEmpty || senha.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe e-mail e senha.')),
      );
      return;
    }
    if (!AuthCpfService.looksLikeEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Digite um e-mail válido.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final service = AuthCpfService();
      await service.signInWithEmail(email: email, senha: senha);

      if (!mounted) return;
      final ok = await _finalizeChurchLoginAfterAuth(persistPasswordFields: true);
      if (!ok) return;
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = switch (e.code) {
        'user-not-found' => 'E-mail não encontrado.',
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
      const SnackBar(
        content: Text('Senha copiada para a área de transferência.',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Biometria rápida quando há credenciais salvas e o serviço está pronto (nativo).
  List<Widget> _biometricQuickActions(Color theme) {
    if (kIsWeb || !_quickBiometricReady) return const <Widget>[];
    return <Widget>[
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _loading ? null : _onEntrarComBiometria,
        icon: const Icon(Icons.fingerprint_rounded, size: 22),
        label: const Text('Entrar com biometria'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme,
          side: BorderSide(color: theme.withValues(alpha: 0.45)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      TextButton(
        onPressed: _loading ? null : _forgetThisDevice,
        child: Text(
          'Remover credenciais deste aparelho',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
      ),
    ];
  }

  List<Widget> _senhaClipboardRow() {
    return <Widget>[
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          children: [
            TextButton.icon(
              onPressed: _loading ? null : _onPasteSenha,
              icon: Icon(Icons.content_paste_go_rounded,
                  size: 18, color: Colors.grey.shade700),
              label: Text(
                'Colar senha',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            TextButton.icon(
              onPressed: _loading ? null : _onCopySenha,
              icon: Icon(Icons.copy_rounded,
                  size: 18, color: Colors.grey.shade700),
              label: Text(
                'Copiar senha',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Login do Painel Master: só marca Gestão YAHWEH (nunca logo de igreja).
  bool get _isMasterAdminLogin => widget.afterLoginRoute == '/admin';

  bool get _useSmartFlow {
    if (_isMasterAdminLogin) return false;
    if (widget.afterLoginRoute != '/painel') return false;
    return widget.showSmartLoginFlow ?? true;
  }

  /// Web + Android/iOS/macOS — o plugin `google_sign_in` não implementa Windows/Linux.
  bool get _googleSignInSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Login com Google + e-mail/senha no painel da igreja (após etapa de credenciais no fluxo inteligente).
  bool get _showChurchGoogleButton =>
      widget.afterLoginRoute == '/painel' &&
      !_isMasterAdminLogin &&
      (!_useSmartFlow || _smartStep == _SmartStep.credentials) &&
      _googleSignInSupported;

  /// Callout “cadastrar igreja” e resumo de planos: não exibir no fluxo **membro** (evita cadastro duplicado).
  bool get _showGestorMarketingBlocks =>
      _showIgrejaPainelExtras &&
      (!_useSmartFlow ||
          _smartStep != _SmartStep.credentials ||
          !_credentialsAsMembro);

  void _onBackLeadingPressed() {
    if (_useSmartFlow) {
      if (_smartStep == _SmartStep.credentials) {
        setState(() {
          _errorMessage = null;
          _smartStep =
              _credentialsAsMembro ? _SmartStep.choosePersona : _SmartStep.gestorBranch;
        });
        return;
      }
      if (_smartStep == _SmartStep.gestorBranch) {
        setState(() {
          _errorMessage = null;
          _smartStep = _SmartStep.choosePersona;
        });
        return;
      }
    }
    final target = widget.backRoute ?? '/';
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil(target, (_) => false);
  }

  /// Cadastro gestor: leva e-mail digitado no login, se válido, para pré-preencher `/signup`.
  void _openGestorSignup() {
    final e = _emailController.text.trim();
    if (AuthCpfService.looksLikeEmail(e)) {
      Navigator.pushNamed(
        context,
        '/signup?email=${Uri.encodeComponent(e)}',
      );
    } else {
      Navigator.pushNamed(context, '/signup');
    }
  }

  static Widget _googleMark() {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFdadce0)),
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildGoogleSignInButton(Color theme) {
    if (!_showChurchGoogleButton) return const SizedBox.shrink();
    return OutlinedButton(
      onPressed: _loading ? null : _onGoogleChurchLogin,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: Colors.grey.shade400),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _googleMark(),
          const SizedBox(width: 10),
          Text(
            'Continuar com Google',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: theme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartChoosePersonaBody(Color theme, {required bool usePoppins}) {
    TextStyle titleStyle() => usePoppins
        ? GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: ThemeCleanPremium.onSurface,
          )
        : TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade900,
          );

    Widget card({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          onTap: _loading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Colors.grey.shade900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Como você deseja entrar?',
          textAlign: TextAlign.center,
          style: titleStyle(),
        ),
        const SizedBox(height: 8),
        Text(
          'Assim evitamos que um membro abra o cadastro de nova igreja por engano.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        card(
          icon: Icons.person_rounded,
          title: 'Sou membro',
          subtitle:
              'Já sou cadastrado na minha igreja. Entrar com Google ou e-mail e senha.',
          onTap: () => setState(() {
            _credentialsAsMembro = true;
            _smartStep = _SmartStep.credentials;
            _errorMessage = null;
          }),
        ),
        const SizedBox(height: 12),
        card(
          icon: Icons.manage_accounts_rounded,
          title: 'Sou gestor ou quero conhecer o sistema',
          subtitle:
              'Primeiro crie a conta (Google ou e-mail). Depois seu perfil e os dados da igreja em etapas — ou entre se já tiver conta.',
          onTap: () => setState(() {
            _errorMessage = null;
            _smartStep = _SmartStep.gestorBranch;
          }),
        ),
      ],
    );
  }

  Widget _buildSmartGestorBranchBody(Color theme, {required bool usePoppins}) {
    TextStyle titleStyle() => usePoppins
        ? GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: ThemeCleanPremium.onSurface,
          )
        : TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.grey.shade900,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Gestão para sua igreja',
          textAlign: TextAlign.center,
          style: titleStyle(),
        ),
        const SizedBox(height: 10),
        Text(
          'Nova igreja: abra o cadastro e siga perfil + dados da igreja. Já tem igreja: entre com Google ou e-mail.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _loading ? null : _openGestorSignup,
          style: FilledButton.styleFrom(
            backgroundColor: theme,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.add_business_rounded),
          label: const Text(
            'Quero cadastrar minha igreja (30 dias grátis)',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _credentialsAsMembro = false;
                    _smartStep = _SmartStep.credentials;
                    _errorMessage = null;
                  }),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: BorderSide(color: theme.withValues(alpha: 0.6)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(Icons.login_rounded, color: theme),
          label: Text(
            'Já sou gestor — entrar com Google ou e-mail',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: theme,
            ),
          ),
        ),
      ],
    );
  }

  /// Android/iOS — painel da igreja: tela com login + resumo de planos + cadastro gestor.
  bool get _nativeChurchLogin =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS) &&
      widget.afterLoginRoute == '/painel';

  /// App nativo: biometria ativa + credenciais salvas — só botão "Entrar" (uma leitura biométrica).
  bool get _painelBiometricCompact =>
      _nativeChurchLogin &&
      _quickBiometricReady &&
      !_showManualCredentialFields &&
      (!_useSmartFlow || _smartStep == _SmartStep.credentials);

  /// Extras de marketing só no fluxo painel da igreja (não no login master).
  bool get _showIgrejaPainelExtras =>
      widget.afterLoginRoute == '/painel' && !_isMasterAdminLogin;

  Widget _buildGestorCadastroCallout(Color theme) {
    return Card(
      elevation: 0,
      color: const Color(0xFFEEF2FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.add_business_rounded, color: theme, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sou gestor de uma igreja',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Colors.grey.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Cadastre sua igreja pelo aplicativo: crie a conta, escolha o plano e use '
              '30 dias grátis para testar o sistema completo (membros, escalas, financeiro e mais).',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _openGestorSignup,
              style: FilledButton.styleFrom(
                backgroundColor: theme,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.how_to_reg_rounded),
              label: const Text(
                'Cadastrar minha igreja agora',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Já tem conta? Use o formulário acima para entrar.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanosResumoCard(Color theme) {
    final brl = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFE4E7EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.layers_outlined, color: theme, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Planos para sua igreja',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Mensalidades aproximadas; no cadastro você confirma o plano e a forma de pagamento.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            ...planosOficiais.map((p) {
              final priceLabel = p.monthlyPrice != null
                  ? '${brl.format(p.monthlyPrice!)}/mês'
                  : (p.note ?? 'Sob consulta');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.featured)
                      Padding(
                        padding: const EdgeInsets.only(right: 6, top: 2),
                        child: Icon(Icons.star_rounded,
                            size: 16, color: Colors.amber.shade800),
                      )
                    else
                      const SizedBox(width: 22),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            p.members,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      priceLabel,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: theme,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/planos'),
                icon: Icon(Icons.open_in_new_rounded, size: 18, color: theme),
                label: Text(
                  'Ver página completa de planos',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Painel igreja (app): sem campos de e-mail/senha até o usuário pedir o modo manual.
  Widget _buildNativeBiometricOnlyBody(Color theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Toque em Entrar para usar digital ou Face ID. '
          'Para digitar e-mail e senha, use a opção abaixo.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        _buildGoogleSignInButton(theme),
        if (_showChurchGoogleButton) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade300)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'ou',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade300)),
            ],
          ),
          const SizedBox(height: 10),
        ],
        FilledButton.icon(
          onPressed: _loading ? null : _onEntrarComBiometria,
          icon: const Icon(Icons.fingerprint_rounded),
          label: const Text('Entrar'),
          style: FilledButton.styleFrom(
            backgroundColor: theme,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() => _showManualCredentialFields = true),
          child: Text(
            'Entrar com e-mail e senha',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: theme,
            ),
          ),
        ),
        TextButton(
          onPressed: _loading ? null : _forgetThisDevice,
          child: Text(
            'Remover credenciais deste aparelho',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
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
      ],
    );
  }

  /// Mesmo fundo e AppBar do site de divulgação ([SitePublicPage]); login só com e-mail + senha.
  Widget _buildNativeMobileChurchLogin(BuildContext context) {
    final topBar = ThemeCleanPremium.navSidebar;
    final theme = ThemeCleanPremium.primary;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              topBar,
              ThemeCleanPremium.primaryLight,
              const Color(0xFFF0F4FF),
              ThemeCleanPremium.surfaceVariant,
            ],
            stops: const [0.0, 0.12, 0.22, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 26),
                  onPressed: _onBackLeadingPressed,
                  tooltip: 'Voltar',
                ),
                title: Row(
                  children: [
                    SizedBox(
                      height: 44,
                      child: _GestaoYahwehLogoPng(
                        height: 44,
                        iconFallbackColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Gestão YAHWEH',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                backgroundColor: topBar,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    ThemeCleanPremium.spaceMd,
                    ThemeCleanPremium.spaceMd,
                    ThemeCleanPremium.spaceMd,
                    24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: _brandLogoWidget(
                          height: 120,
                          maxWidth: MediaQuery.sizeOf(context).width - 40,
                          fallbackIconColor: theme,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Um sistema de excelência feito para sua igreja',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 18),
                      RepaintBoundary(
                        child: Card(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE4E7EF)),
                          ),
                          padding: const EdgeInsets.all(18),
                          child: _useSmartFlow &&
                                  _smartStep != _SmartStep.credentials
                              ? _smartStep == _SmartStep.choosePersona
                                  ? _buildSmartChoosePersonaBody(theme,
                                      usePoppins: false)
                                  : _buildSmartGestorBranchBody(theme,
                                      usePoppins: false)
                              : _painelBiometricCompact
                                  ? _buildNativeBiometricOnlyBody(theme)
                                  : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _credentialsAsMembro
                                    ? 'Membro: use o mesmo e-mail cadastrado na igreja. '
                                        'Pode entrar com Google ou e-mail e senha.'
                                    : 'Gestor: use o e-mail da conta da igreja. '
                                        'Pode entrar com Google ou e-mail e senha.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade700,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _buildGoogleSignInButton(theme),
                              if (_showChurchGoogleButton) ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: Divider(color: Colors.grey.shade300)),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      child: Text(
                                        'ou',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Expanded(child: Divider(color: Colors.grey.shade300)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'E-mail',
                                  hintText: 'seu@email.com',
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
                                    icon: Icon(_obscure
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                              ),
                              ..._senhaClipboardRow(),
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
                              ..._biometricQuickActions(theme),
                              const SizedBox(height: 8),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: theme,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
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
                      ),
                      if (_nativeChurchLogin && !_showGestorMarketingBlocks) ...[
                        const SizedBox(height: 14),
                        const YahwehOfficialSocialChannelsBar(compact: true),
                      ],
                      if (_showGestorMarketingBlocks) ...[
                        const SizedBox(height: 14),
                        _buildGestorCadastroCallout(theme),
                        const SizedBox(height: 12),
                        const YahwehOfficialSocialChannelsBar(compact: true),
                        const SizedBox(height: 12),
                        _buildPlanosResumoCard(theme),
                      ],
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/login_admin'),
                          child: Text(
                            'Acesso painel master',
                            style: TextStyle(
                              color: theme,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: theme.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const VersionFooter(showVersion: true),
                    ],
                  ),
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
    double? maxWidth,
  }) {
    final raw = _isMasterAdminLogin
        ? ''
        : (widget.churchLogoUrl ?? '').trim();
    Widget gestaoYahwehAssets() {
      return _GestaoYahwehLogoPng(
        height: height,
        maxWidth: maxWidth,
        iconFallbackColor: fallbackIconColor,
        masterMarkFallback: _isMasterAdminLogin
            ? _MasterGestaoYahwehMark(
                maxHeight: height,
                foreground: fallbackIconColor,
              )
            : null,
      );
    }

    if (raw.isEmpty) {
      return gestaoYahwehAssets();
    }

    return SafeNetworkImage(
      imageUrl: raw,
      height: height,
      width: maxWidth,
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
          onPressed: _onBackLeadingPressed,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 46,
              child: _brandLogoWidget(
                height: 46,
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
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: LayoutBuilder(
                    builder: (context, bx) {
                      final logoMaxW = bx.maxWidth;
                      final logoH = (logoMaxW * 0.42).clamp(132.0, 210.0);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Center(
                        child: _brandLogoWidget(
                          height: logoH,
                          maxWidth: logoMaxW,
                          fallbackIconColor: theme,
                        ),
                      ),
                      if (!_isMasterAdminLogin &&
                          (widget.churchLogoUrl ?? '').trim().isEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Gestão YAHWEH',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: theme,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (_useSmartFlow &&
                          _smartStep != _SmartStep.credentials)
                        (_smartStep == _SmartStep.choosePersona
                            ? _buildSmartChoosePersonaBody(theme,
                                usePoppins: true)
                            : _buildSmartGestorBranchBody(theme,
                                usePoppins: true))
                      else ...[
                        Text(
                          widget.title,
                          style: GoogleFonts.poppins(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: ThemeCleanPremium.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.afterLoginRoute == '/painel' &&
                            (!_useSmartFlow ||
                                _smartStep == _SmartStep.credentials)) ...[
                          const SizedBox(height: 8),
                          Text(
                            _credentialsAsMembro
                                ? 'Membro: mesmo e-mail cadastrado na igreja. Google ou e-mail e senha.'
                                : 'Gestor: e-mail da conta da igreja. Google ou e-mail e senha.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildGoogleSignInButton(theme),
                        if (_showChurchGoogleButton) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                  child:
                                      Divider(color: Colors.grey.shade300)),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                child: Text(
                                  'ou',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Expanded(
                                  child:
                                      Divider(color: Colors.grey.shade300)),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: 'E-mail',
                            hintText: 'Ex.: seu@email.com',
                            helperText: widget.afterLoginRoute == '/painel'
                                ? (_credentialsAsMembro
                                    ? 'Mesmo e-mail do cadastro na igreja (membro).'
                                    : 'E-mail da conta de gestor.')
                                : 'Use o mesmo e-mail do cadastro na igreja.',
                            border: const OutlineInputBorder(),
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
                              icon: Icon(_obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        ..._senhaClipboardRow(),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(_errorMessage!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ],
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: _rememberLogin,
                          onChanged: (v) =>
                              setState(() => _rememberLogin = v ?? false),
                          title: const Text('Lembrar usuário e senha',
                              style: TextStyle(fontSize: 14)),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: theme,
                        ),
                        ..._biometricQuickActions(theme),
                        const SizedBox(height: 16),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _loading ? null : _onEntrar,
                          child: _loading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Text(
                                  'Entrar',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                        TextButton(
                          onPressed: _loading ? null : _onResetSenha,
                          child: const Text('Esqueci a senha'),
                        ),
                      ],
                      if (_nativeChurchLogin && !_showGestorMarketingBlocks) ...[
                        const SizedBox(height: 16),
                        const YahwehOfficialSocialChannelsBar(compact: true),
                      ],
                      if (_showGestorMarketingBlocks) ...[
                        const SizedBox(height: 18),
                        _buildGestorCadastroCallout(theme),
                        const SizedBox(height: 12),
                        const YahwehOfficialSocialChannelsBar(compact: true),
                        const SizedBox(height: 14),
                        _buildPlanosResumoCard(theme),
                      ],
                      if (widget.afterLoginRoute == '/painel') ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () =>
                              Navigator.pushNamed(context, '/login_admin'),
                          child: const Text('Acesso painel master'),
                        ),
                      ],
                    ],
                  );
                    },
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

/// Logo PNG com decodificação proporcional ao [devicePixelRatio] (telas retina / web nítido).
class _GestaoYahwehLogoPng extends StatelessWidget {
  final double height;
  final double? maxWidth;
  final Color iconFallbackColor;
  final Widget? masterMarkFallback;

  const _GestaoYahwehLogoPng({
    required this.height,
    this.maxWidth,
    required this.iconFallbackColor,
    this.masterMarkFallback,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
    final cacheH = (height * dpr).round().clamp(128, 4096);
    final cacheIcon = (height * 0.92 * dpr).round().clamp(128, 4096);

    Widget core = Image.asset(
      'assets/LOGO_GESTAO_YAHWEH.png',
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
      cacheHeight: cacheH,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/icon/app_icon.png',
        height: height * 0.92,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        cacheHeight: cacheIcon,
        errorBuilder: (_, __, ___) =>
            masterMarkFallback ??
            Icon(
              Icons.church_rounded,
              size: height * 0.85,
              color: iconFallbackColor,
            ),
      ),
    );
    if (maxWidth != null) {
      core = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: core,
      );
    }
    return core;
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
