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
  static const agenda = 'agenda';

  static const preloadOrder = <String>[
    dashboard,
    membros,
    eventos,
    avisos,
    chat,
    agenda,
    patrimonio,
    financeiro,
  ];
}
