import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:gestao_yahweh/services/app_google_sign_in.dart';
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/services/login_preferences.dart';
import 'package:gestao_yahweh/ui/login_page.dart';
import 'package:gestao_yahweh/ui/pages/plans/renew_plan_page.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Rota pública `/atualizar-plano` — gate de autenticação para o fluxo
/// «Atualizar plano expresso» vindo do app iOS (botão Reader/SaaS).
///
/// Tela pré-login (super premium):
///   - Logo do sistema, gradiente de marca e título «Atualizar plano».
///   - CTA: Google (popup ou redirect no Safari iOS) e, na web, Apple.
///   - «Entrar com e-mail e senha» abre [LoginPage] (mesmo fluxo pós-login).
///
/// Quando há sessão Firebase, renderiza diretamente
/// [RenewPlanPage] em modo `expressMode` (cabeçalho com plano atual +
/// vencimento, lista de planos, ciclo, forma de pagamento e checkout
/// Mercado Pago — sem painel).
///
/// Aceita `?email=...` da URL (pré-preenche o e-mail no fallback de login).
class ExpressRenewGatePage extends StatefulWidget {
  /// E-mail enviado pelo app iOS (`?email=`) para pré-preenchimento do login.
  final String? prefillEmail;

  /// `true` quando `?from=ios_app` — mensagens alinhadas ao fluxo Reader no iPhone.
  final bool openedFromIosApp;

  const ExpressRenewGatePage({
    super.key,
    this.prefillEmail,
    this.openedFromIosApp = false,
  });

  @override
  State<ExpressRenewGatePage> createState() => _ExpressRenewGatePageState();
}

class _ExpressRenewGatePageState extends State<ExpressRenewGatePage> {
  late final Stream<User?> _authStream;
  bool _expressInFlight = false;
  String? _expressError;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
    if (kIsWeb) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _completeWebOAuthRedirectIfNeeded());
    }
  }

  /// Safari iOS costuma usar `signInWithRedirect`; ao voltar à URL `/atualizar-plano` é preciso isto.
  Future<void> _completeWebOAuthRedirectIfNeeded() async {
    if (!kIsWeb || !mounted) return;
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      if (result.user != null && mounted) setState(() => _expressError = null);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final friendly = googleAuthErrorMessagePt(e);
      setState(() => _expressError =
          friendly ?? 'Não foi possível concluir o login. Tente de novo.');
    } catch (_) {}
  }

  Future<void> _onAppleWebLogin() async {
    if (_expressInFlight || !kIsWeb) return;
    setState(() {
      _expressInFlight = true;
      _expressError = null;
    });
    try {
      final provider = OAuthProvider('apple.com');
      provider.addScope('email');
      provider.addScope('name');
      try {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        final code = e.code.toLowerCase();
        if (code == 'popup-blocked' ||
            code == 'internal-error' ||
            (code.contains('popup') && code.contains('blocked'))) {
          await FirebaseAuth.instance.signInWithRedirect(provider);
          return;
        }
        final friendly = googleAuthErrorMessagePt(e);
        if (mounted) {
          setState(() => _expressError = friendly ??
              'Apple: ${e.message ?? e.code}. Verifique se o provedor está ativo no Firebase.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _expressError =
            'Falha no login com Apple. Tente Google ou e-mail e senha.');
      }
    } finally {
      if (mounted) setState(() => _expressInFlight = false);
    }
  }

  Future<void> _onLoginExpresso() async {
    if (_expressInFlight) return;
    try {
      if (kIsWeb) {
        setState(() {
          _expressInFlight = true;
          _expressError = null;
        });
        // Web: signInWithPopup → fallback signInWithRedirect (Safari/iOS).
        final provider = firebaseWebGoogleAuthProvider();
        try {
          await FirebaseAuth.instance.signInWithPopup(provider);
        } on FirebaseAuthException catch (e) {
          final code = e.code.toLowerCase();
          if (code == 'popup-blocked' ||
              code == 'internal-error' ||
              (code.contains('popup') && code.contains('blocked'))) {
            await FirebaseAuth.instance.signInWithRedirect(provider);
            return;
          }
          final friendly = googleAuthErrorMessagePt(e);
          if (friendly != null && mounted) {
            setState(() => _expressError = friendly);
          }
        }
      } else {
        // Mobile: 1.ª fase silenciosa sem indicador; depois Apple / Google com UI.
        setState(() => _expressError = null);
        final silentCred = await ExpressLoginService.tryGoogleSilentOnly();
        if (!mounted) return;
        if (silentCred != null && silentCred.user != null) return;
        setState(() => _expressInFlight = true);
        final lastOauth = await LoginPreferences.getLastOAuthProvider();
        final res = await ExpressLoginService.tryExpressLogin(
          skipSilentPhase: true,
          skipApplePhase: lastOauth == 'google' || lastOauth == 'email',
          onBeforeNativeOAuthUi: () {
            if (!mounted) return;
            setState(() => _expressInFlight = false);
          },
        );
        if (res.isError && mounted) {
          setState(() => _expressError =
              res.errorMessage ?? 'Falha no login expresso. Tente de novo.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _expressError = e.toString());
    } finally {
      if (mounted) setState(() => _expressInFlight = false);
    }
  }

  void _openManualLogin() {
    final renewTarget = widget.openedFromIosApp
        ? '/atualizar-plano?from=ios_app'
        : '/atualizar-plano';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginPage(
          title: 'Entrar — Atualizar plano',
          afterLoginRoute: renewTarget,
          backRoute: renewTarget,
          prefillEmail: widget.prefillEmail,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            snap.data == null) {
          return const _LoadingScaffold();
        }
        final user = snap.data;
        if (user == null) {
          return _ExpressGateLoginScaffold(
            inFlight: _expressInFlight,
            errorMessage: _expressError,
            prefillEmailHint: widget.prefillEmail,
            openedFromIosApp: widget.openedFromIosApp,
            onLoginExpresso: _onLoginExpresso,
            onAppleWebLogin: kIsWeb ? _onAppleWebLogin : null,
            onManualLogin: _openManualLogin,
          );
        }
        return _TenantClaimGate(
          key: ValueKey<String>(user.uid),
          user: user,
          openedFromIosApp: widget.openedFromIosApp,
          child: RenewPlanPage(
            expressMode: true,
            expressCheckoutReturnPath: widget.openedFromIosApp
                ? '/atualizar-plano?from=ios_app'
                : '/atualizar-plano',
          ),
        );
      },
    );
  }
}

/// Só libera [RenewPlanPage] quando o token tiver `igrejaId` / `tenantId`
/// (evita «igrejaId ausente» no Mercado Pago com sessão errada ou claims atrasadas).
class _TenantClaimGate extends StatefulWidget {
  final User user;
  final bool openedFromIosApp;
  final Widget child;

  const _TenantClaimGate({
    super.key,
    required this.user,
    required this.openedFromIosApp,
    required this.child,
  });

  @override
  State<_TenantClaimGate> createState() => _TenantClaimGateState();
}

class _TenantClaimGateState extends State<_TenantClaimGate> {
  bool _checking = true;
  bool _hasTenantClaim = false;
  StreamSubscription<User?>? _tokenSub;
  bool _verifyBusy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_verifyClaims());
    _tokenSub = FirebaseAuth.instance.idTokenChanges().listen((u) {
      if (u?.uid == widget.user.uid && !_hasTenantClaim && mounted) {
        unawaited(_verifyClaims());
      }
    });
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }

  Future<void> _verifyClaims() async {
    if (_verifyBusy) return;
    _verifyBusy = true;
    if (!mounted) {
      _verifyBusy = false;
      return;
    }
    setState(() {
      _checking = true;
    });
    try {
      for (var i = 0; i < 12; i++) {
        if (!mounted) return;
        final tr = await widget.user.getIdTokenResult(i > 0);
        final id = (tr.claims?['igrejaId'] ?? tr.claims?['tenantId'] ?? '')
            .toString()
            .trim();
        if (id.isNotEmpty) {
          if (mounted) {
            setState(() {
              _hasTenantClaim = true;
              _checking = false;
            });
          }
          return;
        }
        await Future<void>.delayed(Duration(milliseconds: 220 + 90 * i));
      }
      if (mounted) {
        setState(() {
          _hasTenantClaim = false;
          _checking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasTenantClaim = false;
          _checking = false;
        });
      }
    } finally {
      _verifyBusy = false;
    }
  }

  Future<void> _signOutAndBackToLogin() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const _LoadingScaffold(
        subtitle: 'A validar o acesso da igreja…',
      );
    }
    if (!_hasTenantClaim) {
      return _NoTenantClaimScaffold(
        openedFromIosApp: widget.openedFromIosApp,
        userEmail: (widget.user.email ?? '').trim(),
        onRetry: () => unawaited(_verifyClaims()),
        onSignOut: _signOutAndBackToLogin,
      );
    }
    return widget.child;
  }
}

class _NoTenantClaimScaffold extends StatelessWidget {
  final bool openedFromIosApp;
  final String userEmail;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;

  const _NoTenantClaimScaffold({
    required this.openedFromIosApp,
    required this.userEmail,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('Atualizar plano'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Icon(Icons.domain_rounded,
                      size: 56, color: ThemeCleanPremium.primary.withValues(alpha: 0.85)),
                  const SizedBox(height: 16),
                  Text(
                    openedFromIosApp
                        ? 'Conta sem vínculo ao painel da igreja'
                        : 'Conta sem vínculo com uma igreja',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    openedFromIosApp
                        ? 'Para alterar o plano e pagar pelo site, use o login de '
                            'gestor da sua igreja (Google, Apple ou e-mail e senha '
                            'cadastrados no Gestão YAHWEH). Contas de membro não '
                            'incluem permissão de cobrança.'
                        : 'Para renovar ou alterar o plano, entre com uma conta de '
                            'gestor vinculada à igreja no Gestão YAHWEH.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  if (userEmail.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person_outline_rounded,
                              color: ThemeCleanPremium.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              userEmail,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: () => unawaited(onSignOut()),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sair e entrar com outra conta'),
                    style: FilledButton.styleFrom(
                      backgroundColor: ThemeCleanPremium.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Já atualizei o acesso — verificar de novo'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  final String? subtitle;

  const _LoadingScaffold({this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atualizar plano'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpressGateLoginScaffold extends StatelessWidget {
  final bool inFlight;
  final String? errorMessage;
  final String? prefillEmailHint;
  final bool openedFromIosApp;
  final VoidCallback onLoginExpresso;
  final VoidCallback? onAppleWebLogin;
  final VoidCallback onManualLogin;

  const _ExpressGateLoginScaffold({
    required this.inFlight,
    required this.errorMessage,
    required this.prefillEmailHint,
    this.openedFromIosApp = false,
    required this.onLoginExpresso,
    required this.onAppleWebLogin,
    required this.onManualLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final isWide = c.maxWidth >= 720;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (openedFromIosApp) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.phone_iphone_rounded,
                                  color: YahwehDesignSystem.brandPrimary,
                                  size: 22),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Abriu pelo app no iPhone. Entre com o login de '
                                  'gestor da igreja; em seguida escolha o plano e pague '
                                  '(PIX ou cartão).',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _PremiumHeader(isWide: isWide),
                      const SizedBox(height: 18),
                      _LoginCard(
                        inFlight: inFlight,
                        errorMessage: errorMessage,
                        prefillEmailHint: prefillEmailHint,
                        onLoginExpresso: onLoginExpresso,
                        onAppleWebLogin: onAppleWebLogin,
                        onManualLogin: onManualLogin,
                      ),
                      const SizedBox(height: 14),
                      _SecurityFooter(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PremiumHeader extends StatelessWidget {
  final bool isWide;
  const _PremiumHeader({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, isWide ? 28 : 22, 20, isWide ? 26 : 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A3D91), // navSidebar
            YahwehDesignSystem.brandPrimary,
            Color(0xFF2B6FE0), // brandPrimaryLight
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: YahwehDesignSystem.brandPrimary.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Image.asset(
              'assets/logo.png',
              height: isWide ? 64 : 54,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Atualizar plano',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            kIsWeb
                ? 'Entre com Google, Apple ou e-mail e senha. '
                    'Em seguida escolha o plano e conclua o pagamento.'
                : 'Faça login e siga para os planos e pagamento.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 13.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.28), width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.workspace_premium_rounded,
                    color: YahwehDesignSystem.brandGold, size: 16),
                SizedBox(width: 6),
                Text(
                  'Gestão YAHWEH — Super Premium',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final bool inFlight;
  final String? errorMessage;
  final String? prefillEmailHint;
  final VoidCallback onLoginExpresso;
  final VoidCallback? onAppleWebLogin;
  final VoidCallback onManualLogin;

  const _LoginCard({
    required this.inFlight,
    required this.errorMessage,
    required this.prefillEmailHint,
    required this.onLoginExpresso,
    required this.onAppleWebLogin,
    required this.onManualLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE4E7EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (prefillEmailHint != null && prefillEmailHint!.isNotEmpty) ...[
            _EmailHintBadge(email: prefillEmailHint!),
            const SizedBox(height: 12),
          ],
          // Botão principal: Login expresso (gradiente premium).
          _ExpressLoginButton(
            loading: inFlight,
            onTap: onLoginExpresso,
          ),
          if (onAppleWebLogin != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: inFlight ? null : onAppleWebLogin,
                icon: const Icon(Icons.apple, size: 22),
                label: const Text(
                  'Continuar com Apple',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF111827),
                  side: const BorderSide(color: Color(0xFF1F2937), width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Após o login, carregamos somente a tela de planos (mensal/anual) '
            'e o checkout Mercado Pago.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          if (errorMessage != null && errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: Color(0xFFB91C1C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF991B1B)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          const _OrDivider(),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: inFlight ? null : onManualLogin,
            icon: const Icon(Icons.alternate_email_rounded, size: 18),
            label: const Text(
              'Entrar com e-mail e senha',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            style: TextButton.styleFrom(
              foregroundColor: YahwehDesignSystem.brandPrimary,
              minimumSize: const Size(0, 44),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailHintBadge extends StatelessWidget {
  final String email;
  const _EmailHintBadge({required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDBEAFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_read_rounded,
              size: 18, color: YahwehDesignSystem.brandPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                    color: Color(0xFF1E3A8A), fontSize: 12, height: 1.4),
                children: [
                  const TextSpan(text: 'Vamos entrar com '),
                  TextSpan(
                    text: email,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpressLoginButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _ExpressLoginButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [
              Color(0xFF111827),
              Color(0xFF1F2937),
              Color(0xFF0F766E),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: loading ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.flash_on_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Clique aqui para alterar plano',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Entrar com Google e abrir planos',
                          style: TextStyle(
                            color: Color(0xFFD1FAE5),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (loading)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  else
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: Divider(color: Color(0xFFE5E7EB))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'ou',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(child: Divider(color: Color(0xFFE5E7EB))),
      ],
    );
  }
}

class _SecurityFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline_rounded,
            size: 14, color: Color(0xFF64748B)),
        const SizedBox(width: 6),
        Text(
          'Conexão segura · Pagamento via Mercado Pago',
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
