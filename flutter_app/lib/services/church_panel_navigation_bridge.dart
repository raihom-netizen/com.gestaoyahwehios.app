import 'package:gestao_yahweh/core/church_shell_indices.dart';

/// Pedido de abrir uma conversa concreta (ex.: push FCM ou atalho «Chat igreja»).
class PendingChatThreadOpen {
  final String threadId;
  final String? tenantId;
  /// DM — cria/abre mesmo sem doc prévio em `chat_threads`.
  final String? peerUid;
  final String? displayName;
  final String? initialDraftText;

  const PendingChatThreadOpen({
    required this.threadId,
    this.tenantId,
    this.peerUid,
    this.displayName,
    this.initialDraftText,
  });
}

/// Encaminha toques em notificações push (FCM) para o módulo certo do painel da igreja.
class ChurchPanelNavigationBridge {
  ChurchPanelNavigationBridge._();
  static final ChurchPanelNavigationBridge instance = ChurchPanelNavigationBridge._();

  int? _pendingShellIndex;
  void Function(int index)? _onNavigate;

  PendingChatThreadOpen? _pendingChatOpen;
  final List<void Function()> _chatOpenListeners = <void Function()>[];

  /// Abre o módulo Chat e deixa [threadId] pendente para [ChurchChatHubPage] consumir.
  void requestNavigateToChatThread({
    required String threadId,
    String? tenantId,
    String? peerUid,
    String? displayName,
    String? initialDraftText,
  }) {
    final tid = threadId.trim();
    if (tid.isEmpty) return;
    final tRaw = tenantId?.trim() ?? '';
    final peer = peerUid?.trim() ?? '';
    final name = displayName?.trim() ?? '';
    final draft = initialDraftText?.trim() ?? '';
    _pendingChatOpen = PendingChatThreadOpen(
      threadId: tid,
      tenantId: tRaw.isEmpty ? null : tRaw,
      peerUid: peer.isEmpty ? null : peer,
      displayName: name.isEmpty ? null : name,
      initialDraftText: draft.isEmpty ? null : draft,
    );
    requestNavigateToShellIndex(kChurchShellIndexChat);
    _notifyChatOpenListeners();
  }

  PendingChatThreadOpen? consumePendingChatThreadOpen() {
    final p = _pendingChatOpen;
    _pendingChatOpen = null;
    return p;
  }

  /// Só lê — útil se quiser saber se há conversa pendente sem consumir.
  PendingChatThreadOpen? peekPendingChatThreadOpen() => _pendingChatOpen;

  void registerChatOpenListener(void Function() onPending) {
    if (!_chatOpenListeners.contains(onPending)) {
      _chatOpenListeners.add(onPending);
    }
  }

  void unregisterChatOpenListener(void Function() onPending) {
    _chatOpenListeners.remove(onPending);
  }

  void _notifyChatOpenListeners() {
    for (final cb in List<void Function()>.from(_chatOpenListeners)) {
      cb();
    }
  }

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
      case 'novo_chat':
      case 'chat_message':
      case 'church_chat':
        return kChurchShellIndexChat;
      default:
        return null;
    }
  }
}
