import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:google_fonts/google_fonts.dart';

/// Barra inferior fixa **Cancelar | Confirmar** — avisos/eventos (mobile + web).
/// Não mover confirmar para o topo sem pedido explícito do utilizador.
class FeedPhotoBottomActions extends StatelessWidget {
  const FeedPhotoBottomActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.confirmLabel = 'Confirmar',
    this.center,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E).withValues(alpha: 0.97),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onPressed: onCancel,
                  child: Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w400,
                      color: primary.withValues(alpha: 0.95),
                    ),
                  ),
                ),
              ),
              if (center != null) center!,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: FilledButton(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      confirmLabel,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
