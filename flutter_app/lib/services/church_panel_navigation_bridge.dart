import 'package:gestao_yahweh/ui/widgets/church_global_search_dialog.dart'
    show
        kChurchShellIndexMySchedules,
        kChurchShellIndexMural,
        kChurchShellIndexEvents;

/// Índice do item "Escala Geral" em [IgrejaCleanShell] (`_items`).
const int kChurchShellIndexEscalaGeral = 11;

/// Índice do item "Fornecedores" em [IgrejaCleanShell] (`_items`).
const int kChurchShellIndexFornecedores = 22;

/// Índice do item "Cartas e transferências" em [IgrejaCleanShell] (`_items`).
const int kChurchShellIndexChurchLetters = 14;

/// Encaminha toques em notificações push (FCM) para o módulo certo do painel da igreja.
class ChurchPanelNavigationBridge {
  ChurchPanelNavigationBridge._();
  static final ChurchPanelNavigationBridge instance = ChurchPanelNavigationBridge._();

  int? _pendingShellIndex;
  void Function(int index)? _onNavigate;

  void registerShellNavigator(void Function(int index) onNavigate) {
    _onNavigate = onNavigate;
    final p = _pendingShellIndex;
    if (p != null) {
      _pendingShellIndex = null;
      onNavigate(p);
    }
  }

  void unregisterShellNavigator() {
    _onNavigate = null;
  }

  void requestNavigateToShellIndex(int shellIndex) {
    final cb = _onNavigate;
    if (cb != null) {
      cb(shellIndex);
    } else {
      _pendingShellIndex = shellIndex;
    }
  }

  /// Mapeia [data.type] das Cloud Functions (`pastoralComms`, `onScheduleCreate`, etc.).
  static int? shellIndexForNotificationType(String? type) {
    final t = (type ?? '').trim();
    switch (t) {
      case 'novo_aviso':
        return kChurchShellIndexMural;
      case 'novo_evento':
        return kChurchShellIndexEvents;
      case 'nova_escala':
        return kChurchShellIndexEscalaGeral;
      case 'escala_publicada':
      case 'escala_lembrete_24h':
      case 'escala_lembrete_1h':
      case 'escala_troca_convite':
      case 'escala_troca_recusada':
        return kChurchShellIndexMySchedules;
      case 'escala_impedimento':
      case 'escala_troca_concluida':
      case 'escala':
        return kChurchShellIndexEscalaGeral;
      case 'fornecedor_agenda_reminder':
        return kChurchShellIndexFornecedores;
      default:
        return null;
    }
  }
}
