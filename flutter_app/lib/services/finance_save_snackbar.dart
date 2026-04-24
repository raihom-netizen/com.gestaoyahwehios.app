import 'package:flutter/material.dart';

import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Uma SnackBar coerente após gravação no financeiro (incl. lotes de importação).
void showFinanceSaveSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
  Color? backgroundColor,
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError
          ? (backgroundColor ?? ThemeCleanPremium.error)
          : (backgroundColor ?? ThemeCleanPremium.success),
    ),
  );
}
