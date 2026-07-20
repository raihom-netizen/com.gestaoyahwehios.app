import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/design_system/app_theme.dart';

/// Botão verde «voltar ao topo» — mesmo visual do Controle Total (Android, iOS e Web).
class ShellScrollToTopFab extends StatefulWidget {
  const ShellScrollToTopFab({
    super.key,
    required this.controller,
    this.showAfter = 100,
  });

  final ScrollController controller;

  /// Exibe o botão após rolar esta distância (px).
  final double showAfter;

  @override
  State<ShellScrollToTopFab> createState() => _ShellScrollToTopFabState();
}

class _ShellScrollToTopFabState extends State<ShellScrollToTopFab> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(ShellScrollToTopFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!widget.controller.hasClients) {
      if (_visible && mounted) setState(() => _visible = false);
      return;
    }
    final show = widget.controller.offset > widget.showAfter;
    if (show != _visible && mounted) {
      setState(() => _visible = show);
    }
  }

  Future<void> _scrollToTop() async {
    if (!widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    if (offset <= 0) return;
    if (offset > 2200) {
      widget.controller.jumpTo(0);
      return;
    }
    await widget.controller.animateTo(
      0,
      duration: Duration(milliseconds: offset > 900 ? 200 : 160),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _ShellScrollToTopFabVisual(
      visible: _visible,
      onTap: _scrollToTop,
    );
  }
}

/// Camada que escuta [ScrollNotification] vertical de qualquer módulo
/// e sobrepõe o FAB verde — cobre Painel + todos os módulos sem wiring por página.
class ShellScrollToTopLayer extends StatefulWidget {
  const ShellScrollToTopLayer({
    super.key,
    required this.child,
    this.resetToken,
    this.showAfter = 100,
    this.right = 12,
    this.bottom = 12,
  });

  final Widget child;

  /// Ao mudar (ex.: índice do módulo), esconde o FAB até nova rolagem.
  final Object? resetToken;

  final double showAfter;
  final double right;
  final double bottom;

  @override
  State<ShellScrollToTopLayer> createState() => _ShellScrollToTopLayerState();
}

class _ShellScrollToTopLayerState extends State<ShellScrollToTopLayer> {
  bool _visible = false;
  double _offset = 0;
  BuildContext? _scrollableContext;

  @override
  void didUpdateWidget(ShellScrollToTopLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken) {
      _visible = false;
      _offset = 0;
      _scrollableContext = null;
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    // Ignora overscroll / métricas sem conteúdo rolável.
    if (n.metrics.maxScrollExtent <= 0) return false;
    if (n is! ScrollUpdateNotification &&
        n is! ScrollEndNotification &&
        n is! UserScrollNotification) {
      return false;
    }
    final pixels = n.metrics.pixels;
    final show = pixels > widget.showAfter;
    final ctx = n.context;
    if (ctx != null) _scrollableContext = ctx;
    if (show != _visible || (show && (pixels - _offset).abs() > 8)) {
      _offset = pixels;
      if (mounted) setState(() => _visible = show);
    } else {
      _offset = pixels;
    }
    return false;
  }

  Future<void> _scrollToTop() async {
    final ctx = _scrollableContext;
    if (ctx == null || !ctx.mounted) return;
    final position = Scrollable.maybeOf(ctx)?.position;
    if (position == null || !position.hasPixels) return;
    final offset = position.pixels;
    if (offset <= 0) return;
    if (offset > 2200) {
      position.jumpTo(0);
    } else {
      await position.animateTo(
        0,
        duration: Duration(milliseconds: offset > 900 ? 200 : 160),
        curve: Curves.easeOutCubic,
      );
    }
    if (mounted) {
      setState(() {
        _visible = false;
        _offset = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            right: widget.right,
            bottom: widget.bottom,
            child: _ShellScrollToTopFabVisual(
              key: ValueKey(widget.resetToken),
              visible: _visible,
              onTap: _scrollToTop,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellScrollToTopFabVisual extends StatelessWidget {
  const _ShellScrollToTopFabVisual({
    super.key,
    required this.visible,
    required this.onTap,
  });

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Voltar ao topo',
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: AnimatedScale(
            scale: visible ? 1 : 0.88,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Material(
              color: Colors.transparent,
              elevation: visible ? 8 : 0,
              shadowColor: AppColors.success.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              child: InkWell(
                onTap: visible ? onTap : null,
                customBorder: const CircleBorder(),
                child: Ink(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF4ADE80),
                        AppColors.success,
                        Color(0xFF16A34A),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.48),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.55),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
