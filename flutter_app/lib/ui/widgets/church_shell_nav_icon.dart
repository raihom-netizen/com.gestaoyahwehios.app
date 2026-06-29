import 'package:flutter/material.dart';

/// Forma do chip de ícone (menu quadrado arredondado · rodapé circular).
enum ChurchShellIconShape { roundedSquare, circle }

/// Ícone de módulo com gradiente, brilho e sombra — sensação 3D (menu + rodapé).
class ChurchShellNavIcon3D extends StatelessWidget {
  const ChurchShellNavIcon3D({
    super.key,
    required this.icon,
    required this.accent,
    this.selected = false,
    this.shape = ChurchShellIconShape.roundedSquare,
    this.size = 40,
    this.iconSize,
    /// Rodapé mobile — sombras mais leves (WISDOMAPP).
    this.compact = false,
  });

  final IconData icon;
  final Color accent;
  final bool selected;
  final ChurchShellIconShape shape;
  final double size;
  final double? iconSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isCircle = shape == ChurchShellIconShape.circle;
    final radius = isCircle ? size / 2 : size * 0.3;
    final iSz = iconSize ?? (size * (isCircle ? 0.48 : 0.52));
    final top = Color.lerp(accent, Colors.white, selected ? 0.38 : 0.32)!;
    final mid = accent;
    final bottom = Color.lerp(accent, const Color(0xFF0F172A), selected ? 0.45 : 0.35)!;

    final lift = compact ? (selected ? -1.0 : 0.0) : (selected ? -2.5 : 0.0);
    return Transform.translate(
      offset: Offset(0, lift),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isCircle ? null : BorderRadius.circular(radius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [top, mid, bottom],
            stops: const [0.0, 0.42, 1.0],
          ),
          border: Border(
            top: BorderSide(
              color: Colors.white.withValues(alpha: selected ? 0.62 : 0.48),
              width: 1.4,
            ),
            bottom: BorderSide(
              color: bottom.withValues(alpha: 0.95),
              width: isCircle ? 2 : 1.6,
            ),
            left: BorderSide(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.6,
            ),
            right: BorderSide(
              color: bottom.withValues(alpha: 0.7),
              width: 0.6,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(
                alpha: compact
                    ? (selected ? 0.34 : 0.22)
                    : (selected ? 0.58 : 0.36),
              ),
              blurRadius: compact ? (selected ? 8 : 6) : (selected ? 18 : 12),
              spreadRadius: compact ? 0 : (selected ? 0.5 : 0),
              offset: Offset(0, compact ? (selected ? 3 : 2) : (selected ? 7 : 5)),
            ),
            if (!compact)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: isCircle
              ? BorderRadius.circular(radius)
              : BorderRadius.circular(radius),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: size * 0.48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.38),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Icon(
                icon,
                size: iSz,
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: bottom.withValues(alpha: 0.55),
                    offset: const Offset(0, 1.5),
                    blurRadius: 3,
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
