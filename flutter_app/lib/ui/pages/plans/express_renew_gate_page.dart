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
///   - CTA direto: «Clique aqui para alterar plano».
///   - Botão grande com autenticação Google — usa o e-mail salvo no
///     navegador/celular (Google popup/redirect na web; Google silencioso →
///     Apple → Google interativo no app nativo).
///   - Link discreto para «Entrar com e-mail e senha» (fallback).
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

  const ExpressRenewGatePage({super.key, this.prefillEmail});

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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginPage(
          title: 'Entrar — Atualizar plano',
          afterLoginRoute: '/atualizar-plano',
          backRoute: '/atualizar-plano',
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
            onLoginExpresso: _onLoginExpresso,
            onManualLogin: _openManualLogin,
          );
        }
        return const RenewPlanPage(expressMode: true);
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atualizar plano'),
        backgroundColor: ThemeCleanPremium.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _ExpressGateLoginScaffold extends StatelessWidget {
  final bool inFlight;
  final String? errorMessage;
  final String? prefillEmailHint;
  final VoidCallback onLoginExpresso;
  final VoidCallback onManualLogin;

  const _ExpressGateLoginScaffold({
    required this.inFlight,
    required this.errorMessage,
    required this.prefillEmailHint,
    required this.onLoginExpresso,
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
                      _PremiumHeader(isWide: isWide),
                      const SizedBox(height: 18),
                      _LoginCard(
                        inFlight: inFlight,
                        errorMessage: errorMessage,
                        prefillEmailHint: prefillEmailHint,
                        onLoginExpresso: onLoginExpresso,
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
            'Clique abaixo para alterar seu plano. '
            'Faça login Google e siga direto para os planos e pagamento.',
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
  final VoidCallback onManualLogin;

  const _LoginCard({
    required this.inFlight,
    required this.errorMessage,
    required this.prefillEmailHint,
    required this.onLoginExpresso,
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
