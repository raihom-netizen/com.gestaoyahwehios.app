import 'package:flutter/material.dart';

/// Rótulos padronizados — atalhos Yahweh Chat e WhatsApp (painel, membros, pastoral).
/// Motor interno pode ser embutido; na UI o utilizador só vê a marca Yahweh Chat.
abstract final class YahwehContactButtonLabels {
  YahwehContactButtonLabels._();

  static const String yahwehChat = 'Yahweh Chat';
  static const String whatsApp = 'WhatsApp';

  /// Menu lateral / módulo shell.
  static const String yahwehChatModule = 'Yahweh Chat';

  /// Cor de marca do módulo Chat (não usar azul de terceiros).
  static const Color accent = Color(0xFF0D9488);

  static const IconData icon = Icons.forum_rounded;
}
