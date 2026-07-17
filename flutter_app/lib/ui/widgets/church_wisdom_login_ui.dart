import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_yahweh_brand_logo.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';
import 'package:google_fonts/google_fonts.dart';

/// Accent login WISDOMAPP — navy + teal + dourado.
const Color kChurchWisdomLoginTeal = Color(0xFF0D9488);
const Color kChurchWisdomLoginNavy = Color(0xFF0B1B4B);
const Color kChurchWisdomLoginGold = Color(0xFFD4AF37);

/// Largura máxima do card de autenticação (web/desktop).
const double kAuthScreenMaxWidth = 420;

/// Centraliza o conteúdo do login/cadastro — evita campos «gigantes» em telas largas.
///
/// Centraliza vertical + horizontalmente quando o conteúdo cabe na viewport
/// (desktop web); quando não cabe (mobile/teclado aberto), rola normalmente.
class ChurchWisdomAuthCenter extends StatelessWidget {
  const ChurchWisdomAuthCenter({
    super.key,
    required this.child,
    this.maxWidth = kAuthScreenMaxWidth,
    this.bottomInset = 28,
  });

  final Widget child;
  final double maxWidth;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final padding = EdgeInsets.fromLTRB(
      ThemeCleanPremium.spaceMd,
      ThemeCleanPremium.spaceMd,
      ThemeCleanPremium.spaceMd,
      bottomInset,
    );
    return LayoutBuilder(
      builder: (context, viewport) {
        final minHeight = viewport.hasBoundedHeight
            ? (viewport.maxHeight - padding.vertical).clamp(0.0, double.infinity)
            : 0.0;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Cabeçalho de marca dentro do card branco — logo em destaque + título + subtítulo.
class ChurchWisdomCardBrandHeader extends StatelessWidget {
  const ChurchWisdomCardBrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.logo,
    this.logoHeight = 72,
  });

  final String title;
  final String? subtitle;
  /// Logo custom (ex.: logo da igreja). Sem valor → escudo Gestão YAHWEH.
  final Widget? logo;
  final double logoHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Center(
          child: logo ??
              GestaoYahwehBrandLogo(
                height: logoHeight,
                showHeroGlow: true,
                heroGlowColor: kChurchWisdomLoginGold,
              ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
            letterSpacing: -0.3,
            height: 1.2,
          ),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 18),
      ],
    );
  }
}

/// Campos compactos — altura menor, visual mais moderno.
InputDecoration authCompactFieldDecoration({
  String? labelText,
  String? hintText,
  String? helperText,
  Widget? suffixIcon,
  Widget? prefixIcon,
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    helperText: helperText,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
      borderSide: const BorderSide(color: kChurchWisdomLoginTeal, width: 1.6),
    ),
    labelStyle: const TextStyle(fontSize: 13),
    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade600),
    helperStyle: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
  );
}

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
    this.compact = false,
  });

  final Widget logo;
  final String? subtitle;
  final String? greeting;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(
          compact ? ThemeCleanPremium.radiusLg : ThemeCleanPremium.radiusXl,
        ),
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
            color: kChurchWisdomLoginTeal.withValues(alpha: compact ? 0.28 : 0.35),
            blurRadius: compact ? 20 : 28,
            offset: Offset(0, compact ? 10 : 14),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 20,
        compact ? 16 : 22,
        compact ? 16 : 20,
        compact ? 16 : 20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'GESTÃO YAHWEH',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.w800,
              letterSpacing: compact ? 1.2 : 1.4,
              color: kChurchWisdomLoginGold,
            ),
          ),
          SizedBox(height: compact ? 8 : 12),
          Center(child: logo),
          if (greeting != null && greeting!.trim().isNotEmpty) ...[
            SizedBox(height: compact ? 10 : 14),
            Text(
              greeting!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: compact ? 17 : 20,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ],
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            SizedBox(height: compact ? 6 : 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: compact ? 12 : 13,
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
  const ChurchWisdomLoginFormCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return YahwehWisdomSectionCard(
      borderTint: kChurchWisdomLoginTeal,
      padding: padding ??
          EdgeInsets.all(ThemeCleanPremium.isMobile(context) ? 18 : 24),
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
