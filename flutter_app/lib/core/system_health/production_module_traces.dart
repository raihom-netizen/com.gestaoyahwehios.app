/// Nomes canónicos — Firebase Performance Monitoring.
abstract final class ProductionModuleTraces {
  ProductionModuleTraces._();

  static const dashboard = 'time_dashboard';
  static const chat = 'time_chat';
  static const avisos = 'time_avisos';
  static const eventos = 'time_eventos';
  static const patrimonio = 'time_patrimonio';
  static const financeiro = 'time_financeiro';
  static const membros = 'time_membros';
  static const upload = 'time_upload';
  static const firestoreWrite = 'time_firestore_write';
  static const storageWrite = 'time_storage_write';
  static const syncFlush = 'time_sync_flush';
  static const login = 'time_login';
}
