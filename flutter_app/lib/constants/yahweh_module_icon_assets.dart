import 'package:flutter/material.dart';

/// Ícones PNG de módulo — padrão Controle Total (emblema YAHWEH + badge premium).
///
/// Gerados por `tool/generate_yahweh_module_icons.py` em [assets/icon/].
abstract final class YahwehModuleIconAssets {
  YahwehModuleIconAssets._();

  static const String _base = 'assets/icon';

  static const String avisos = '$_base/icon_avisos.png';
  static const String eventos = '$_base/icon_eventos.png';
  static const String escalas = '$_base/icon_escalas.png';
  static const String contasPagar = '$_base/icon_contas_pagar.png';
  static const String novoMembro = '$_base/icon_novo_membro.png';
  static const String aniversariantes = '$_base/icon_aniversariantes.png';
  static const String emblemaTransparent = '$_base/emblema_yahweh_transparent.png';
  static const String appIcon = '$_base/app_icon.png';

  /// Resolve asset por chave `gy_module` / notificação.
  static String? forModuleKey(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'aviso':
      case 'avisos':
        return avisos;
      case 'evento':
      case 'eventos':
        return eventos;
      case 'escala':
      case 'escalas':
        return escalas;
      case 'financeiro':
      case 'contas_pagar':
        return contasPagar;
      case 'membro':
      case 'novo_membro':
      case 'cadastro':
        return novoMembro;
      case 'aniversario':
      case 'aniversariantes':
        return aniversariantes;
      default:
        return null;
    }
  }

  /// Fallback Material quando PNG indisponível.
  static IconData materialFallback(String? raw) {
    switch ((raw ?? '').toLowerCase().trim()) {
      case 'aviso':
        return Icons.campaign_rounded;
      case 'evento':
        return Icons.event_rounded;
      case 'escala':
        return Icons.calendar_month_rounded;
      case 'financeiro':
      case 'contas_pagar':
        return Icons.receipt_long_rounded;
      case 'membro':
        return Icons.person_add_alt_1_rounded;
      case 'aniversario':
        return Icons.cake_rounded;
      case 'chat':
        return Icons.forum_rounded;
      case 'pastoral':
        return Icons.volunteer_activism_rounded;
      case 'visitante':
      case 'visitantes':
        return Icons.emoji_people_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }
}
