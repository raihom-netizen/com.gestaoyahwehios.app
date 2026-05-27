import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/pages/events_manager_page.dart';

/// Legado — redireciona para a Galeria de Eventos no módulo Mural (aba Galeria).
@Deprecated('Use EventsManagerPage(initialTabIndex: 1)')
class GaleriaEventosPage extends StatelessWidget {
  final String tenantId;
  final String role;

  const GaleriaEventosPage({
    super.key,
    required this.tenantId,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return EventsManagerPage(
      tenantId: tenantId,
      role: role,
      initialTabIndex: 1,
    );
  }
}
