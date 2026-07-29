import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Botões de rodapé compactos — WisdomApp (texto completo, sem quebra).
class PatrimonioWisdomFooterButton extends StatelessWidget {
  const PatrimonioWisdomFooterButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.color,
    this.flex = 1,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final Color? color;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final accent = color ??
        (filled
            ? YahwehDesignSystem.brandPrimary
            : YahwehDesignSystem.wisdomTealAccent);
    final enabled = onPressed != null;
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: filled && enabled
                ? LinearGradient(
                    colors: [
                      accent,
                      Color.lerp(accent, Colors.black, 0.12)!,
                    ],
                  )
                : null,
            color: filled
                ? (enabled ? null : Colors.grey.shade300)
                : (enabled
                    ? accent.withValues(alpha: 0.10)
                    : Colors.grey.shade100),
            border: Border.all(
              color: filled
                  ? Colors.transparent
                  : (enabled
                      ? accent.withValues(alpha: 0.55)
                      : Colors.grey.shade300),
              width: 1.4,
            ),
            boxShadow: filled && enabled
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : ThemeCleanPremium.softUiCardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: filled
                      ? Colors.white
                      : (enabled ? accent : Colors.grey.shade500),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: filled
                          ? Colors.white
                          : (enabled ? accent : Colors.grey.shade500),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Expanded(flex: flex, child: child);
  }
}

/// Linha Cancelar + Salvar (form / editor de fotos).
class PatrimonioWisdomCancelSaveBar extends StatelessWidget {
  const PatrimonioWisdomCancelSaveBar({
    super.key,
    required this.onCancel,
    required this.onSave,
    this.saving = false,
    this.saveEnabled = true,
    this.saveLabel = 'Salvar',
  });

  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final bool saving;
  final bool saveEnabled;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              PatrimonioWisdomFooterButton(
                label: 'Cancelar',
                icon: Icons.close_rounded,
                onPressed: saving ? null : onCancel,
                color: const Color(0xFFE11D48),
              ),
              const SizedBox(width: 10),
              PatrimonioWisdomFooterButton(
                label: saving ? 'Salvando…' : saveLabel,
                icon: saving ? Icons.hourglass_top_rounded : Icons.save_rounded,
                onPressed: (saving || !saveEnabled) ? null : onSave,
                filled: true,
                color: YahwehDesignSystem.brandPrimary,
                flex: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Linha Cancelar + Fotos + Editar (detalhe do bem).
class PatrimonioWisdomDetailActionsBar extends StatelessWidget {
  const PatrimonioWisdomDetailActionsBar({
    super.key,
    required this.onCancel,
    this.onFotos,
    this.onEditar,
  });

  final VoidCallback onCancel;
  final VoidCallback? onFotos;
  final VoidCallback? onEditar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 8,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              PatrimonioWisdomFooterButton(
                label: 'Cancelar',
                icon: Icons.close_rounded,
                onPressed: onCancel,
                color: const Color(0xFFE11D48),
              ),
              if (onFotos != null) ...[
                const SizedBox(width: 8),
                PatrimonioWisdomFooterButton(
                  label: 'Fotos',
                  icon: Icons.photo_library_rounded,
                  onPressed: onFotos,
                  color: YahwehDesignSystem.wisdomTealAccent,
                ),
              ],
              if (onEditar != null) ...[
                const SizedBox(width: 8),
                PatrimonioWisdomFooterButton(
                  label: 'Editar',
                  icon: Icons.edit_rounded,
                  onPressed: onEditar,
                  filled: true,
                  color: YahwehDesignSystem.brandPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
