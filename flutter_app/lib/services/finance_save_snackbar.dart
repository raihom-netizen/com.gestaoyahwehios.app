import 'package:flutter/material.dart';

import 'package:gestao_yahweh/services/sync_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Feedback breve após gravação no financeiro (via [SyncService]).
void showFinanceSaveSnackBar(
  BuildContext context, {
  required String message,
  bool isError = false,
  Color? backgroundColor,
}) {
  if (!context.mounted) return;
  if (isError) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: backgroundColor ?? ThemeCleanPremium.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  SyncService.notifyUserActionSaved();
}
