import 'package:flutter/material.dart';

import 'package:gestao_yahweh/core/design_system/app_theme.dart';

/// Barra inferior padrão — Cancelar + Publicar (Avisos, Eventos, formulários ERP).
class AppPublishActionRow extends StatelessWidget {
  const AppPublishActionRow({
    super.key,
    required this.publishLabel,
    required this.onPublish,
    this.onCancel,
    this.saving = false,
    this.disabled = false,
    this.savingLabel = 'A guardar…',
    this.accentColor,
  });

  final String publishLabel;
  final String savingLabel;
  final VoidCallback? onPublish;
  final VoidCallback? onCancel;
  final bool saving;
  final bool disabled;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.primary;
    final blocked = saving || disabled;

    return SizedBox(
      height: AppComponentStyles.minTouch + 8,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: blocked ? null : onCancel,
              style: AppComponentStyles.secondaryOutlined.copyWith(
                foregroundColor: WidgetStatePropertyAll(accent),
                side: WidgetStatePropertyAll(
                  BorderSide(color: accent.withValues(alpha: 0.45)),
                ),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: blocked ? null : onPublish,
              icon: saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded, size: 22),
              label: Text(
                saving ? savingLabel : publishLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              style: AppComponentStyles.primaryFilled.copyWith(
                backgroundColor: WidgetStatePropertyAll(accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// SnackBar amigável — substitui pop-ups técnicos de Firebase na UI.
void showAppPublishError(
  BuildContext context,
  String message, {
  VoidCallback? onRetry,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    AppComponentStyles.errorSnack(message, onRetry: onRetry),
  );
}
