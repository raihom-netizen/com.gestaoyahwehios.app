import 'package:flutter/material.dart';

/// Cores estáveis por remetente (estilo WhatsApp em grupos).
abstract final class ChurchChatSenderPalette {
  ChurchChatSenderPalette._();

  static const List<Color> _incoming = [
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFFAD1457),
    Color(0xFF00695C),
    Color(0xFF4527A0),
    Color(0xFFC62828),
    Color(0xFF558B2F),
    Color(0xFF0277BD),
    Color(0xFF6D4C41),
  ];

  static int _idx(String uid) {
    if (uid.isEmpty) return 0;
    var h = uid.hashCode;
    if (h < 0) h = -h;
    return h % _incoming.length;
  }

  /// Cor do nome / acento na bolha recebida (grupo).
  static Color nameColorForUid(String senderUid) =>
      _incoming[_idx(senderUid)];

  /// Fundo suave da bolha recebida (grupo).
  static Color bubbleBackgroundForUid(String senderUid) {
    final c = _incoming[_idx(senderUid)];
    return Color.lerp(c, Colors.white, 0.88)!;
  }

  /// Borda suave da bolha recebida (grupo).
  static Color bubbleBorderForUid(String senderUid) {
    final c = _incoming[_idx(senderUid)];
    return c.withValues(alpha: 0.28);
  }
}
