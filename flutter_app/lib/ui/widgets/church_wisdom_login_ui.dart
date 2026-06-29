import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_yahweh_brand_logo.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// Accent login WISDOMAPP — navy + teal + dourado.
const Color kChurchWisdomLoginTeal = Color(0xFF0D9488);
const Color kChurchWisdomLoginNavy = Color(0xFF0B1B4B);
const Color kChurchWisdomLoginGold = Color(0xFFD4AF37);

/// Fundo completo do login igreja — gradiente WISDOMAPP.
class ChurchWisdomLoginBackdrop extends StatelessWidget {
  const ChurchWisdomLoginBackdrop({
    super.key,
    required this.child,
    this.appBar,
    this.bottomBar,
    this.sessionFinalizing = false,
  });

  final Widget child;
  final PreferredSizeWidget? appBar;
  final Widget? bottomBar;
  final bool sessionFinalizing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            kChurchWisdomLoginNavy,
            YahwehWisdomVisualKit.navyMid,
            Color.lerp(kChurchWisdomLoginTeal, Colors.white, 0.82)!,
            const Color(0xFFF0F9FF),
          ],
          stops: const [0.0, 0.18, 0.42, 1.0],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: appBar,
        body: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (sessionFinalizing)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Color(0x33FFFFFF),
                  color: Colors.white,
                ),
              ),
            if (bottomBar != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
                child: bottomBar!,
              ),
          ],
        ),
      ),
    );
  }
}

/// AppBar login WISDOMAPP.
class ChurchWisdomLoginAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const ChurchWisdomLoginAppBar({
    super.key,
    required this.onBack,
    this.actions = const [],
  });

  final VoidCallback onBack;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: onBack,
        tooltip: 'Voltar',
      ),
      title: Row(
        children: [
          SizedBox(
            height: 40,
            child: GestaoYahwehBrandLogo(
              height: 40,
              fallbackIconColor: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gestão YAHWEH',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 17,
                letterSpacing: -0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      actions: actions,
    );
  }
}

/// Hero card — estilo WISDOMAPP (gradiente teal/azul + título dourado).
class ChurchWisdomLoginHeroCard extends StatelessWidget {
  const ChurchWisdomLoginHeroCard({
    super.key,
    required this.logo,
    this.subtitle,
    this.greeting,
  });

  final Widget logo;
  final String? subtitle;
  final String? greeting;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusXl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0F766E),
            Color(0xFF1D4ED8),
            kChurchWisdomLoginNavy,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: kChurchWisdomLoginTeal.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'GESTÃO YAHWEH',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: kChurchWisdomLoginGold,
            ),
          ),
          const SizedBox(height: 12),
          Center(child: logo),
          if (greeting != null && greeting!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              greeting!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ],
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card branco do formulário — WISDOMAPP.
class ChurchWisdomLoginFormCard extends StatelessWidget {
  const ChurchWisdomLoginFormCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return YahwehWisdomSectionCard(
      borderTint: kChurchWisdomLoginTeal,
      padding: const EdgeInsets.all(20),
      child: child,
    );
  }
}

/// Faixa «Login expresso» — credenciais offline (padrão Controle Total / WISDOMAPP).
class ChurchWisdomExpressLoginBar extends StatelessWidget {
  const ChurchWisdomExpressLoginBar({
    super.key,
    required this.emailHint,
    required this.loading,
    required this.onEnter,
  });

  final String emailHint;
  final bool loading;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final hint = emailHint.trim();
    return Material(
      elevation: 12,
      shadowColor: kChurchWisdomLoginTeal.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: loading ? null : onEnter,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF0F766E),
                Color(0xFF134074),
                kChurchWisdomLoginNavy,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Login expresso',
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hint.contains('@')
                          ? 'Entrar com $hint (salvo offline)'
                          : 'Credenciais salvas neste aparelho',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFD1FAE5),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Entrar',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
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
}

/// Rodapé bíblico — alinhado ao painel WISDOMAPP.
class ChurchWisdomLoginScriptureFooter extends StatelessWidget {
  const ChurchWisdomLoginScriptureFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        'Consagre ao Senhor tudo o que você faz, e os seus planos serão bem-sucedidos. — Provérbios 16:3',
        textAlign: TextAlign.center,
        style: GoogleFonts.poppins(
          fontSize: 11,
          fontStyle: FontStyle.italic,
          color: const Color(0xFF64748B),
          height: 1.35,
        ),
      ),
    );
  }
}
