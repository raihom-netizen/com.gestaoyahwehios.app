import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_chat_member_prefs.dart';
import 'package:gestao_yahweh/services/church_chat_notification_prefs.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Folha «alerta em primeiro plano» para uma conversa (override em `threadNotifModes`).
Future<void> showChurchChatThreadForegroundNotifSheet({
  required BuildContext context,
  required String tenantId,
  required String threadId,
  required String title,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: ThemeCleanPremium.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ThemeCleanPremium.radiusLg),
      ),
    ),
    builder: (ctx) {
      Future<void> apply(String? mode) async {
        Navigator.pop(ctx);
        final ok = await ChurchChatMemberPrefs.setThreadNotificationOverride(
          tenantId: tenantId,
          threadId: threadId,
          mode: mode,
        );
        if (!context.mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Máximo de ${ChurchChatMemberPrefs.maxThreadNotifOverrides} conversas '
                'com alerta personalizado.',
              ),
            ),
          );
          return;
        }
        final label = mode == null
            ? 'Padrão (DM/grupo/global)'
            : (mode == ChurchChatNotificationPrefs.alertModeVibrate
                ? 'Só vibrar'
                : mode == ChurchChatNotificationPrefs.alertModeSilent
                    ? 'Silencioso'
                    : 'Som + vibrar');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Alerta: $label')),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Primeiro plano (app aberto). Push em segundo plano segue o sistema.',
                  style: TextStyle(fontSize: 12, height: 1.35),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.restore_rounded),
                title: const Text('Seguir padrão'),
                subtitle: const Text('DM, grupo ou global da conta'),
                onTap: () => apply(null),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_active_rounded),
                title: const Text('Som + vibrar'),
                onTap: () => apply(ChurchChatNotificationPrefs.alertModeSound),
              ),
              ListTile(
                leading: const Icon(Icons.vibration_rounded),
                title: const Text('Só vibrar'),
                onTap: () => apply(ChurchChatNotificationPrefs.alertModeVibrate),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_off_rounded),
                title: const Text('Silencioso'),
                onTap: () => apply(ChurchChatNotificationPrefs.alertModeSilent),
              ),
            ],
          ),
        ),
      );
    },
  );
}
