import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/public_member_signup_navigation.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_embedded_module_bar.dart';
import 'package:gestao_yahweh/services/church_repository.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_skeleton_loading.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre link público: no app nativo prioriza rota in-app (instantâneo); senão Safari/Chrome.
Future<void> openHttpsUrlInBrowser(BuildContext context, String rawUrl) async {
  var t = rawUrl.trim();
  if (t.isEmpty) return;
  if (!kIsWeb &&
      PublicMemberSignupNavigation.tryOpenInAppFromUrl(context, t)) {
    return;
  }
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
    final launched = launchUrl(uri, mode: LaunchMode.externalApplication);
    final ok = await launched;
    if (!ok && context.mounted) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
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

/// Faixa quando a lista vem do cache / última leitura boa (rede instável).
class ChurchPanelOfflineStaleBanner extends StatelessWidget {
  const ChurchPanelOfflineStaleBanner({
    super.key,
    this.message =
        'Modo offline — a mostrar os últimos dados guardados. Puxe para atualizar.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 20, color: Colors.orange.shade800),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [FutureBuilder] com fallback à última query bem-sucedida (sistema completo).
class ResilientPanelQueryFutureBuilder extends StatefulWidget {
  const ResilientPanelQueryFutureBuilder({
    super.key,
    required this.future,
    required this.errorTitle,
    required this.onRetry,
    required this.builder,
    this.offlineMessage,
  });

  final Future<QuerySnapshot<Map<String, dynamic>>> future;
  final String errorTitle;
  final VoidCallback onRetry;
  final Widget Function(
    BuildContext context,
    QuerySnapshot<Map<String, dynamic>> snap, {
    required bool showingStaleCache,
  }) builder;
  final String? offlineMessage;

  @override
  State<ResilientPanelQueryFutureBuilder> createState() =>
      _ResilientPanelQueryFutureBuilderState();
}

class _ResilientPanelQueryFutureBuilderState
    extends State<ResilientPanelQueryFutureBuilder> {
  QuerySnapshot<Map<String, dynamic>>? _lastGood;
  bool _stale = false;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: widget.future,
      builder: (context, snap) {
        if (snap.hasError) {
          final fallback = _lastGood;
          if (fallback != null && fallback.docs.isNotEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ChurchPanelOfflineStaleBanner(
                    message: widget.offlineMessage ??
                        'Modo offline — a mostrar os últimos dados guardados.',
                  ),
                ),
                Expanded(child: widget.builder(context, fallback, showingStaleCache: true)),
              ],
            );
          }
          return ChurchPanelErrorBody(
            title: widget.errorTitle,
            error: snap.error,
            onRetry: widget.onRetry,
          );
        }
        if (snap.connectionState != ConnectionState.done || !snap.hasData) {
          final fallback = _lastGood;
          if (fallback != null && fallback.docs.isNotEmpty) {
            return widget.builder(context, fallback, showingStaleCache: _stale);
          }
          return const ChurchPanelLoadingBody();
        }
        _lastGood = snap.data;
        _stale = false;
        return widget.builder(context, snap.data!, showingStaleCache: false);
      },
    );
  }
}

/// Carregamento inicial do painel — skeleton (não spinner isolado).
class ChurchPanelLoadingBody extends StatelessWidget {
  const ChurchPanelLoadingBody({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return YahwehSkeletonLoading.panelList(itemCount: itemCount);
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

/// Onde a faixa de abas “pill” se assenta: azul (AppBar) vs branco (corpo / shell).
enum ChurchPanelPillTabBarStyle {
  /// Trilho semitransparente em faixa **primária** — rótulos brancos, selecionado = branco + texto primário.
  onPrimary,
  /// Trilho cinza-claro em **fundo claro** (Mural, etc.) — rótulos slate, selecionado = branco + sombra.
  onLight,
}

/// Abas de módulo no painel da igreja — mesmo visual “pill” do Patrimônio (fundo primário + indicador branco).
///
/// Usar em mobile dentro do [IgrejaCleanShell] com [embeddedInShell] para alinhar ao cabeçalho do shell sem
/// duplicar AppBar. [tabs] devem ser [Tab] com texto (e opcionalmente ícone).
/// Fundo suave do corpo dos módulos Financeiro / Patrimônio / Fornecedores.
BoxDecoration churchModuleBodyGradient(Color accent) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.lerp(accent, Colors.white, 0.72)!,
        ThemeCleanPremium.surfaceVariant,
        const Color(0xFFF8FAFC),
      ],
      stops: const [0.0, 0.22, 1.0],
    ),
  );
}

/// Faixa superior no shell: voltar + abas coloridas do módulo.
class ChurchModuleShellChrome extends StatelessWidget {
  const ChurchModuleShellChrome({
    super.key,
    required this.onBack,
    required this.title,
    required this.icon,
    required this.accent,
    required this.tabController,
    required this.tabs,
    this.subtitle,
    this.denseTabs = true,
    this.actions = const [],
  });

  final VoidCallback onBack;
  final String title;
  final IconData icon;
  final Color accent;
  final String? subtitle;
  final TabController tabController;
  final List<Widget> tabs;
  final bool denseTabs;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ChurchEmbeddedModuleBar(
          title: title,
          icon: icon,
          accent: accent,
          onBack: onBack,
          subtitle: subtitle,
          actions: actions,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent,
                Color.lerp(accent, Colors.white, 0.18)!,
              ],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: ChurchPanelPillTabBar(
            controller: tabController,
            tabs: tabs,
            dense: denseTabs,
            accentColor: accent,
          ),
        ),
      ],
    );
  }
}

class ChurchPanelPillTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<Widget> tabs;
  /// Altura total menor (faixa azul mais baixa), mantendo o visual “pill” do Patrimônio.
  final bool dense;
  final ChurchPanelPillTabBarStyle style;
  /// Cor do módulo (Financeiro verde, Patrimônio âmbar, etc.) — substitui o azul primário.
  final Color? accentColor;

  const ChurchPanelPillTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.dense = false,
    this.style = ChurchPanelPillTabBarStyle.onPrimary,
    this.accentColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(dense ? 50 : 64);

  @override
  Widget build(BuildContext context) {
    final onLight = style == ChurchPanelPillTabBarStyle.onLight;
    final p = accentColor ?? ThemeCleanPremium.primary;
    final outer = dense
        ? EdgeInsets.fromLTRB(10, onLight ? 6 : 2, 10, onLight ? 8 : 6)
        : EdgeInsets.fromLTRB(12, onLight ? 4 : 0, 12, onLight ? 12 : 10);
    final innerPad = dense ? 3.0 : 4.0;
    final fs = dense ? 12.0 : 13.0;
    final hPadTab = dense ? 10.0 : 12.0;
    final indR = dense ? 9.0 : 10.0;
    final trackColor = onLight
        ? const Color(0xFFE8EDF4)
        : Colors.white.withValues(alpha: 0.14);
    final trackBorder = onLight
        ? const Color(0xFFCAD3E0)
        : Colors.white.withValues(alpha: 0.24);
    return Padding(
      padding: outer,
      child: Container(
        padding: EdgeInsets.all(innerPad),
        decoration: BoxDecoration(
          color: trackColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: trackBorder),
          boxShadow: onLight
              ? [
                  BoxShadow(
                    color: p.withValues(alpha: 0.07),
                    blurRadius: 16,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Theme(
          data: Theme.of(context).copyWith(
            splashColor: onLight
                ? p.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.12),
            highlightColor: onLight
                ? p.withValues(alpha: 0.06)
                : Colors.white.withValues(alpha: 0.08),
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
                  color: p.withValues(alpha: onLight ? 0.20 : 0.28),
                  blurRadius: onLight ? 12 : 10,
                  offset: Offset(0, onLight ? 2 : 3),
                ),
              ],
            ),
            labelColor: p,
            unselectedLabelColor: onLight
                ? const Color(0xFF64748B)
                : const Color(0xFFDBEAFE),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: fs,
              letterSpacing: 0.2,
            ),
            unselectedLabelStyle: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: fs,
              letterSpacing: 0.15,
              shadows: onLight
                  ? null
                  : [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 2,
                        offset: const Offset(0, 0.5),
                      ),
                    ],
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
                color: selected
                    ? Colors.white
                    : const Color(0xFF0F172A).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.45),
                  width: 1.2,
                ),
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
                    color: selected ? p : const Color(0xFFFFFBEB),
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
                        color: selected ? p : const Color(0xFFFFFBEB),
                        shadows: selected
                            ? null
                            : [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 2,
                                ),
                              ],
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

/// FutureBuilder com timeout Web (10s) — nunca skeleton infinito.
class ChurchPanelTimedFutureBuilder<T> extends StatefulWidget {
  const ChurchPanelTimedFutureBuilder({
    super.key,
    required this.future,
    required this.builder,
    this.loading,
    required this.errorTitle,
    this.onRetry,
    this.timeout,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final Widget? loading;
  final String errorTitle;
  final VoidCallback? onRetry;
  final Duration? timeout;

  @override
  State<ChurchPanelTimedFutureBuilder<T>> createState() =>
      _ChurchPanelTimedFutureBuilderState<T>();
}

class _ChurchPanelTimedFutureBuilderState<T>
    extends State<ChurchPanelTimedFutureBuilder<T>> {
  late Future<T> _future;

  @override
  void initState() {
    super.initState();
    _future = _wrap(widget.future);
  }

  @override
  void didUpdateWidget(ChurchPanelTimedFutureBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.future != widget.future) {
      _future = _wrap(widget.future);
    }
  }

  Future<T> _wrap(Future<T> raw) {
    final cap = widget.timeout ?? ChurchRepository.panelQueryTimeout;
    if (!kIsWeb) return raw;
    return raw.timeout(
      cap,
      onTimeout: () => throw TimeoutException(
        'Tempo esgotado (${cap.inSeconds}s).',
        cap,
      ),
    );
  }

  void _retry() {
    setState(() => _future = _wrap(widget.future));
    widget.onRetry?.call();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return widget.loading ??
              Center(child: YahwehSkeletonLoading.membrosList(itemCount: 4));
        }
        if (snap.hasError) {
          return ChurchPanelErrorBody(
            title: widget.errorTitle,
            error: snap.error,
            onRetry: _retry,
          );
        }
        if (!snap.hasData) {
          return ChurchPanelErrorBody(
            title: widget.errorTitle,
            onRetry: _retry,
          );
        }
        return widget.builder(context, snap.data as T);
      },
    );
  }
}
