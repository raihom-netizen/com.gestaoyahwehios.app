import 'package:flutter/material.dart';

/// Ícones dos módulos Compromissos e Audiências (navegação + faixa premium).
abstract final class AgendaModuleIcons {
  /// Legado — módulo combinado (migração).
  static const IconData nav = Icons.calendar_month_rounded;

  static const IconData compromissoNav = Icons.event_available_rounded;
  static const IconData compromissoBanner = Icons.push_pin_rounded;

  static const IconData audienciaNav = Icons.gavel_rounded;
  static const IconData audienciaBanner = Icons.balance_rounded;
}
