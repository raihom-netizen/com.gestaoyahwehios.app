/// Chaves canónicas — cache Hive local por módulo (banco local obrigatório).
abstract final class TenantModuleKeys {
  TenantModuleKeys._();

  static const dashboard = 'dashboard';
  static const masterPanel = 'master_panel';
  static const membros = 'membros';
  static const eventos = 'eventos';
  static const avisos = 'avisos';
  static const chat = 'chat';
  static const patrimonio = 'patrimonio';
  static const financeiro = 'financeiro';
  static const escalas = 'escalas';
  static const agenda = 'agenda';
  static const departamentos = 'departamentos';
  static const visitantes = 'visitantes';
  static const cargos = 'cargos';
  static const fornecedores = 'fornecedores';
  static const pedidosOracao = 'pedidos_oracao';
  static const eventCategories = 'event_categories';

  static const preloadOrder = <String>[
    dashboard,
    membros,
    departamentos,
    eventos,
    avisos,
    chat,
    escalas,
    agenda,
    visitantes,
    cargos,
    patrimonio,
    financeiro,
    fornecedores,
  ];
}
