import 'package:flutter/material.dart';

/// Gradiente «Super Premium · estilo WhatsApp» (teal → azul → roxo → coral).
///
/// Usar no **hub**, no **AppBar do thread**, na **folha de anexos** e molduras do mesmo
/// look — uma única definição evita drift visual entre ecrãs.
const LinearGradient churchChatWhatsPremiumLinearGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF059669),
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
  ],
  stops: [0.0, 0.28, 0.52, 0.78, 1.0],
);

/// Fundo suave do hub/lista (evita branco chapado).
const LinearGradient churchChatHubBackgroundGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFFE0F2FE),
    Color(0xFFF0FDF4),
    Color(0xFFFDF4FF),
  ],
);

/// Fundo da conversa (thread) — gradiente multicolor suave estilo WhatsApp premium.
const LinearGradient churchChatThreadBackgroundGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFFD1FAE5),
    Color(0xFFE0F2FE),
    Color(0xFFEDE9FE),
    Color(0xFFFCE7F3),
  ],
  stops: [0.0, 0.32, 0.68, 1.0],
);

/// Decoração pronta para o corpo do thread.
BoxDecoration get churchChatThreadBackgroundDecoration => const BoxDecoration(
      gradient: churchChatThreadBackgroundGradient,
    );
