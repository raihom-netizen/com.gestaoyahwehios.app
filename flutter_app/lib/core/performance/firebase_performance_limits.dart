/// Limites canónicos de performance — **única fonte** para paginação e scans Firestore.
///
/// Telas devem consumir via [ChurchFirestoreAccess] / repositórios — não paths soltos.
abstract final class FirebasePerformanceLimits {
  FirebasePerformanceLimits._();

  // ─── Paginação por módulo ─────────────────────────────────────────────────
  static const int membrosPage = 50;
  static const int eventosPage = 32;
  static const int avisosPage = 32;
  static const int chatThreadsPage = 40;
  static const int chatMessagesPage = 30;
  static const int patrimonioPage = 40;
  static const int financeiroPage = 80;
  static const int fornecedoresPage = 40;
  static const int departamentosPage = 60;
  static const int cargosPage = 60;
  static const int escalasPage = 40;
  static const int agendaPage = 40;

  /// Teto absoluto — proíbe `collection.get()` sem limite na camada de dados.
  static const int absoluteMaxList = 200;

  /// Dashboard: **nunca** scan de coleção — só `_dashboard_cache` + `_panel_cache`.
  static const int dashboardMaxDirectQuery = 32;

  static int maxListForSubcollection(String sub) {
    switch (sub.trim()) {
      case 'membros':
        return membrosPage;
      case 'eventos':
      case 'noticias':
        return eventosPage;
      case 'avisos':
        return avisosPage;
      case 'chats':
        return chatThreadsPage;
      case 'patrimonio':
        return patrimonioPage;
      case 'finance':
        return financeiroPage;
      case 'fornecedores':
        return fornecedoresPage;
      case 'departamentos':
        return departamentosPage;
      case 'cargos':
        return cargosPage;
      case 'escalas':
        return escalasPage;
      case 'agenda':
        return agendaPage;
      default:
        return 80;
    }
  }

  static int capListLimit(String subcollection, int requested) {
    final max = maxListForSubcollection(subcollection);
    final capped = requested.clamp(1, absoluteMaxList);
    return capped > max ? max : capped;
  }

  // ─── Storage / mídia (espelha media_upload_limits.dart) ───────────────────
  static const int webpQuality = 75;
  static const int eventosMaxPhotos = 5;
  static const int eventosMaxVideos = 1;
  static const int eventosMaxVideoSeconds = 90;
  static const int avisosMaxPhotos = 5;
  static const int patrimonioMaxPhotos = 5;

  // ─── Streams ──────────────────────────────────────────────────────────────
  /// 1 listener por chave (`watchKey`) — ver [StreamListenerRegistry].
  static const int maxConcurrentFirestoreListeners = 12;
}
