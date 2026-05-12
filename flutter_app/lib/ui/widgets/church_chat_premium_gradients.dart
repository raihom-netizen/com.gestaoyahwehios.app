import 'package:flutter/material.dart';

/// Gradiente «Super Premium · estilo WhatsApp» (teal → azul → roxo).
///
/// Usar no **hub**, no **AppBar do thread**, na **folha de anexos** e molduras do mesmo
/// look — uma única definição evita drift visual entre ecrãs.
const LinearGradient churchChatWhatsPremiumLinearGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    Color(0xFF0D9488),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
  ],
);
