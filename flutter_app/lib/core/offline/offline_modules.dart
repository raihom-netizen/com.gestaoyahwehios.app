/// Chaves de módulo na fila Hive ([SyncTask.module]).
abstract final class OfflineModules {
  OfflineModules._();

  static const membros = 'membros';
  static const eventos = 'eventos';
  static const avisos = 'avisos';
  static const patrimonio = 'patrimonio';
  static const financeiro = 'financeiro';
  static const escalas = 'escalas';
  static const visitantes = 'visitantes';
  static const pedidosOracao = 'pedidos_oracao';
  static const departamentos = 'departamentos';
  static const chat = 'chat';
  static const mural = 'mural';
  static const tenant = 'tenant';

  /// Resolve módulo a partir da coleção sob `igrejas/{tenantId}/`.
  static String forCollection(String collection) {
    final c = collection.trim().toLowerCase();
    switch (c) {
      case 'membros':
      case 'membro':
        return membros;
      case 'eventos':
      case 'evento':
      case 'noticias':
      case 'noticia':
        return eventos;
      case 'avisos':
      case 'aviso':
        return avisos;
      case 'patrimonio':
        return patrimonio;
      case 'finance':
      case 'financeiro':
        return financeiro;
      case 'escalas':
      case 'escala':
        return escalas;
      case 'visitantes':
      case 'visitante':
        return visitantes;
      case 'pedidosoracao':
      case 'pedidos_oracao':
        return pedidosOracao;
      case 'departamentos':
      case 'departamento':
        return departamentos;
      case 'chats':
      case 'chat':
      case 'chat_threads':
        return chat;
      default:
        return tenant;
    }
  }

  static String tenantIdFromPath(String fullPath) {
    final parts = fullPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2 && parts[0] == 'igrejas') return parts[1];
    return '';
  }
}
