import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/app_constants.dart';
import 'package:gestao_yahweh/services/fcm_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Cor por módulo — alinhado a Cloud Functions `gy_module` e menu do painel.
Color gyModuleAccentColor(String? raw) {
  switch ((raw ?? '').toLowerCase().trim()) {
    case 'aviso':
      return const Color(0xFF0EA5E9);
    case 'evento':
      return const Color(0xFFF97316);
    case 'escala':
      return const Color(0xFF14B8A6);
    case 'fornecedor_agenda':
      return const Color(0xFF475569);
    case 'pastoral':
      return const Color(0xFFEAB308);
    case 'devocional':
      return const Color(0xFF6366F1);
    case 'aniversario':
      return const Color(0xFFE11D48);
    case 'membro':
      return const Color(0xFF2563EB);
    case 'generico':
      return const Color(0xFF3B82F6);
    case 'chat':
      return const Color(0xFF8B5CF6);
    default:
      return const Color(0xFF0F172A);
  }
}

String gyModuleLabel(String? raw) {
  switch ((raw ?? '').toLowerCase().trim()) {
    case 'aviso':
      return 'Aviso';
    case 'evento':
      return 'Evento';
    case 'escala':
      return 'Escala';
    case 'aniversario':
      return 'Aniversário';
    case 'membro':
      return 'Cadastro';
    case 'chat':
      return 'Chat';
    case 'devocional':
      return 'Devocional';
    case 'pastoral':
      return 'Pastoral';
    default:
      return 'Gestão YAHWEH';
  }
}

/// SnackBar Super Premium (primeiro plano): logo + borda colorida por módulo.
void showGestaoForegroundNotificationSnackBar(
  BuildContext context,
  RemoteMessage msg,
) {
  if (!context.mounted) return;
  final title = (msg.notification?.title ?? '').trim();
  final body = (msg.notification?.body ?? '').trim();
  final isChatMention = (msg.data['chatMention'] ?? '').toString() == '1';
  final text = title.isNotEmpty
      ? '$title${body.isNotEmpty ? '\n$body' : ''}'
      : (body.isNotEmpty ? body : 'Nova notificação');
  final moduleRaw = msg.data['gy_module']?.toString();
  final accent = gyModuleAccentColor(moduleRaw);
  final moduleLabel = gyModuleLabel(moduleRaw);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      duration: const Duration(seconds: 6),
      backgroundColor: Colors.white,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent, width: 2),
      ),
      content: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          FcmService.instance.routeNotificationTap(msg);
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: AppConstants.gestaoBrandLogoUrl,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _logoFallback(accent),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isChatMention ? 'Menção no chat' : moduleLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.06,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: ThemeCleanPremium.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Toque para abrir',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _logoFallback(Color accent) {
  return Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: accent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
    ),
    alignment: Alignment.center,
    child: Icon(Icons.church_rounded, color: accent, size: 26),
  );
}
