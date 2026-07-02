import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_contact_button_labels.dart';
import 'package:gestao_yahweh/services/fcm_service.dart';
import 'package:gestao_yahweh/ui/widgets/gestao_bank_notification_tile.dart';

/// Cor por módulo — alinhado a Cloud Functions `gy_module` e menu do painel.
Color gyModuleAccentColor(String? raw) {
  switch ((raw ?? '').toLowerCase().trim()) {
    case 'aviso':
      return const Color(0xFF0EA5E9);
    case 'evento':
      return const Color(0xFFF97316);
    case 'escala':
      return const Color(0xFF14B8A6);
    case 'financeiro':
    case 'contas_pagar':
      return const Color(0xFFDC2626);
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
    case 'financeiro':
    case 'contas_pagar':
      return 'Contas a pagar';
    case 'aniversario':
      return 'Aniversário';
    case 'membro':
      return 'Cadastro';
    case 'chat':
      return YahwehContactButtonLabels.yahwehChat;
    case 'devocional':
      return 'Devocional';
    case 'pastoral':
      return 'Pastoral';
    default:
      return 'Gestão YAHWEH';
  }
}

/// Banner em primeiro plano — padrão banco (cartão flutuante + escudo oficial).
void showGestaoForegroundNotificationSnackBar(
  BuildContext context,
  RemoteMessage msg,
) {
  if (!context.mounted) return;
  final title = (msg.notification?.title ?? msg.data['title'] ?? '').trim();
  final body = (msg.notification?.body ?? msg.data['body'] ?? '').trim();
  final isChatMention = (msg.data['chatMention'] ?? '').toString() == '1';
  final displayTitle = title.isNotEmpty
      ? title
      : (body.isNotEmpty ? body : 'Nova notificação');
  final displayBody = title.isNotEmpty && body.isNotEmpty ? body : '';
  final moduleRaw = msg.data['gy_module']?.toString();

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: EdgeInsets.zero,
      duration: const Duration(seconds: 7),
      backgroundColor: Colors.transparent,
      elevation: 0,
      content: GestaoBankNotificationTile(
        title: displayTitle,
        body: displayBody,
        module: moduleRaw,
        isChatMention: isChatMention,
        isRead: false,
        compact: true,
        dateLabel: 'Toque para abrir',
        onTap: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          FcmService.instance.routeNotificationTap(msg);
        },
      ),
    ),
  );
}
