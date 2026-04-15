import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre https/http no navegador (app externo). Não depende só de [canLaunchUrl]
/// (no Android 11+ falha sem `<queries>` no manifest; mesmo assim tentamos [launchUrl]).
Future<void> openHttpsUrlInBrowser(BuildContext context, String rawUrl) async {
  var t = rawUrl.trim();
  if (t.isEmpty) return;
  var uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme) {
    uri = Uri.tryParse('https://$t');
  }
  if (uri == null || !uri.hasScheme) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Link inválido.'),
      );
    }
    return;
  }
  try {
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar(
          'Não foi possível abrir o navegador. Use «Copiar link» e cole no browser.',
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.feedbackSnackBar('Erro ao abrir link: $e'),
      );
    }
  }
}

/// Estado de erro padronizado para módulos do painel da igreja (cartão premium + retry).
class ChurchPanelErrorBody extends StatelessWidget {
  final String title;
  final Object? error;
  final VoidCallback? onRetry;
  final String retryLabel;

  const ChurchPanelErrorBody({
    super.key,
    required this.title,
    this.error,
    this.onRetry,
    this.retryLabel = 'Tentar novamente',
  });

  @override
  Widget build(BuildContext context) {
    final detail = kDebugMode && error != null ? error.toString() : null;
    return ThemeCleanPremium.premiumErrorState(
      title: title,
      subtitle: detail ??
          'Verifique sua conexão ou tente novamente em instantes.',
      onRetry: onRetry,
      retryLabel: retryLabel,
    );
  }
}

/// Indicador de carregamento centralizado (módulos do painel).
class ChurchPanelLoadingBody extends StatelessWidget {
  const ChurchPanelLoadingBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(
          strokeWidth: 2.6,
          color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

/// Filtro de período (7 / 15 / 30 dias) no painel principal — texto sempre legível.
///
/// Substitui [ChoiceChip], que com tema M3 costuma deixar rótulos claros em fundo claro
/// ou invisíveis quando não selecionado.
class ChurchPanelPeriodDaysChip extends StatelessWidget {
  final int days;
  final bool selected;
  final VoidCallback onTap;

  const ChurchPanelPeriodDaysChip({
    super.key,
    required this.days,
    required this.selected,
    required this.onTap,
  });

  static const Color _borderUnselected = Color(0xFFCBD5E1);
  static const Color _labelUnselected = Color(0xFF334155);

  @override
  Widget build(BuildContext context) {
    final p = ThemeCleanPremium.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: p.withValues(alpha: 0.14),
        highlightColor: p.withValues(alpha: 0.06),
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? p.withValues(alpha: 0.14) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? p : _borderUnselected,
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? p.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: selected ? 12 : 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle_rounded, size: 18, color: p),
                  const SizedBox(width: 6),
                ],
                Text(
                  '$days dias',
                  style: TextStyle(
                    color: selected ? p : _labelUnselected,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
                    height: 1.2,
                    letterSpacing: 0.12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Orientação do PDF (retrato / paisagem): segmentos largos, borda visível e toque ≥ 48dp.
///
/// Substitui [FilterChip] fraco usado antes nos relatórios.
class PremiumPdfOrientationBar extends StatelessWidget {
  final bool landscape;
  final ValueChanged<bool> onChanged;

  const PremiumPdfOrientationBar({
    super.key,
    required this.landscape,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = ThemeCleanPremium.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.aspect_ratio_rounded, size: 20, color: p),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Orientação do PDF',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: ThemeCleanPremium.onSurface,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: false,
              label: Text('Vertical'),
              tooltip: 'Retrato (página em pé)',
              icon: Icon(Icons.crop_portrait_rounded, size: 22),
            ),
            ButtonSegment<bool>(
              value: true,
              label: Text('Paisagem'),
              tooltip: 'Paisagem (largura)',
              icon: Icon(Icons.crop_landscape_rounded, size: 22),
            ),
          ],
          selected: {landscape},
          onSelectionChanged: (Set<bool> next) {
            if (next.isEmpty) return;
            onChanged(next.first);
          },
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: p,
            selectedForegroundColor: Colors.white,
            foregroundColor: ThemeCleanPremium.onSurface,
            backgroundColor: const Color(0xFFEFF6FF),
            side: BorderSide(color: p.withValues(alpha: 0.5), width: 1.75),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            minimumSize: const Size(0, ThemeCleanPremium.minTouchTarget),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Abas de módulo no painel da igreja — mesmo visual “pill” do Patrimônio (fundo primário + indicador branco).
///
/// Usar em mobile dentro do [IgrejaCleanShell] com [embeddedInShell] para alinhar ao cabeçalho do shell sem
/// duplicar AppBar. [tabs] devem ser [Tab] com texto (e opcionalmente ícone).
class ChurchPanelPillTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<Widget> tabs;
  /// Altura total menor (faixa azul mais baixa), mantendo o visual “pill” do Patrimônio.
  final bool dense;

  const ChurchPanelPillTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.dense = false,
  });

  @override
  Size get preferredSize => Size.fromHeight(dense ? 50 : 64);

  @override
  Widget build(BuildContext context) {
    final outer = dense
        ? const EdgeInsets.fromLTRB(10, 2, 10, 6)
        : const EdgeInsets.fromLTRB(12, 0, 12, 10);
    final innerPad = dense ? 3.0 : 4.0;
    final fs = dense ? 12.0 : 13.0;
    final hPadTab = dense ? 10.0 : 12.0;
    final indR = dense ? 9.0 : 10.0;
    return Padding(
      padding: outer,
      child: Container(
        padding: EdgeInsets.all(innerPad),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: Colors.white.withValues(alpha: 0.12),
            highlightColor: Colors.white.withValues(alpha: 0.08),
          ),
          child: TabBar(
            controller: controller,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            splashBorderRadius: BorderRadius.circular(indR),
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(indR),
              boxShadow: [
                BoxShadow(
                  color: ThemeCleanPremium.primary.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            labelColor: ThemeCleanPremium.primary,
            unselectedLabelColor: Colors.white,
            labelStyle: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: fs,
              letterSpacing: 0.2,
            ),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: fs,
              letterSpacing: 0.15,
            ),
            labelPadding: EdgeInsets.symmetric(horizontal: hPadTab),
            tabs: tabs,
          ),
        ),
      ),
    );
  }
}

/// Dois segmentos no mesmo estilo “pill” do [ChurchPanelPillTabBar] (faixa primária + trilho semitransparente).
class ChurchPanelPillPair extends StatelessWidget {
  final bool valueIsA;
  final ValueChanged<bool> onChanged;
  final String labelA;
  final String labelB;
  final IconData iconA;
  final IconData iconB;

  const ChurchPanelPillPair({
    super.key,
    required this.valueIsA,
    required this.onChanged,
    required this.labelA,
    required this.labelB,
    required this.iconA,
    required this.iconB,
  });

  @override
  Widget build(BuildContext context) {
    final p = ThemeCleanPremium.primary;
    Widget seg({
      required bool selected,
      required String label,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: p.withValues(alpha: 0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 19,
                    color: selected ? p : Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        letterSpacing: 0.15,
                        color: selected ? p : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      color: p,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            seg(
              selected: valueIsA,
              label: labelA,
              icon: iconA,
              onTap: () => onChanged(true),
            ),
            const SizedBox(width: 4),
            seg(
              selected: !valueIsA,
              label: labelB,
              icon: iconB,
              onTap: () => onChanged(false),
            ),
          ],
        ),
      ),
    );
  }
}
