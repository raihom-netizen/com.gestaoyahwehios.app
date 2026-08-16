import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/core/church_panel_modules_removed.dart';

/// Pedido de abrir uma conversa concreta (ex.: push FCM ou atalho ?Yahweh Chat?).
/// O hub nativo consome [threadId] / [peerUid] (DM Firestore `dm_?`).
class PendingChatThreadOpen {
  final String threadId;
  final String? tenantId;

  /// DM — cria/abre mesmo sem doc prévio em `chat_threads`.
  final String? peerUid;
  final String? displayName;
  final String? initialDraftText;

  /// Telefone do membro (=10 dígitos) ? opcional (atalhos externos).
  final String? phoneDigits;

  const PendingChatThreadOpen({
    required this.threadId,
    this.tenantId,
    this.peerUid,
    this.displayName,
    this.initialDraftText,
    this.phoneDigits,
  });
}

/// Encaminha toques em notificações push (FCM) para o módulo certo do painel da igreja.
class ChurchPanelNavigationBridge {
  ChurchPanelNavigationBridge._();
  static final ChurchPanelNavigationBridge instance =
      ChurchPanelNavigationBridge._();

  int? _pendingShellIndex;
  void Function(int index)? _onNavigate;

  PendingChatThreadOpen? _pendingChatOpen;
  final List<void Function()> _chatOpenListeners = <void Function()>[];

  /// Abre o módulo Yahweh Chat e deixa [threadId] pendente para o hub consumir.
  void requestNavigateToChatThread({
    required String threadId,
    String? tenantId,
    String? peerUid,
    String? displayName,
    String? initialDraftText,
    String? phoneDigits,
  }) {
    // Módulo Yahweh Chat removido — não abre mais nenhuma conversa interna.
    if (!kChurchChatModuleEnabled) return;
    final tid = threadId.trim();
    if (tid.isEmpty) return;
    final tRaw = tenantId?.trim() ?? '';
    final peer = peerUid?.trim() ?? '';
    final name = displayName?.trim() ?? '';
    final draft = initialDraftText?.trim() ?? '';
    final phone = (phoneDigits ?? '').replaceAll(RegExp(r'\D'), '');
    _pendingChatOpen = PendingChatThreadOpen(
      threadId: tid,
      tenantId: tRaw.isEmpty ? null : tRaw,
      peerUid: peer.isEmpty ? null : peer,
      displayName: name.isEmpty ? null : name,
      initialDraftText: draft.isEmpty ? null : draft,
      phoneDigits: phone.length >= 10 ? phone : null,
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

  /// Re-dispara consumo da conversa pendente (hub ainda não montado ou tenant a resolver).
  void renotifyPendingChatThreadOpen() {
    if (_pendingChatOpen == null) return;
    _notifyChatOpenListeners();
  }

  String? _pendingOpenEventDocId;
  String? _pendingOpenMemberDocId;

  String? consumePendingOpenEventDocId() {
    final id = _pendingOpenEventDocId;
    _pendingOpenEventDocId = null;
    return id;
  }

  String? consumePendingOpenMemberDocId() {
    final id = _pendingOpenMemberDocId;
    _pendingOpenMemberDocId = null;
    return id;
  }

  void requestOpenEventDocId(String eventoId) {
    final id = eventoId.trim();
    if (id.isEmpty) return;
    _pendingOpenEventDocId = id;
    requestNavigateToShellIndex(kChurchShellIndexEvents);
  }

  void requestOpenMemberDocId(String memberId, {bool publicSignup = false}) {
    final id = memberId.trim();
    if (id.isEmpty) return;
    _pendingOpenMemberDocId = id;
    requestNavigateToShellIndex(
      publicSignup ? kChurchShellIndexAprovacoes : kChurchShellIndexMembers,
    );
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
        return kChurchShellIndexMySchedules;
      case 'escala_publicada':
      case 'escala_lembrete_24h':
      case 'escala_lembrete_1h':
      case 'escala_troca_convite':
      case 'escala_troca_recusada':
        return kChurchShellIndexMySchedules;
      case 'escala_impedimento':
      case 'escala_troca_concluida':
      case 'escala':
        return kChurchShellIndexMySchedules;
      case 'fornecedor_agenda_reminder':
        return kChurchShellIndexFornecedores;
      case 'novo_pedido_oracao':
        return ChurchShellIndices.pedidosOracao;
      case 'new_member':
        return kChurchShellIndexMembers;
      case 'birthday_daily':
        return kChurchShellIndexPainel;
      case 'financeiro_vencimento_digest':
      case 'financeiro_vencimento_24h':
        return kChurchShellIndexFinanceiro;
      case 'novo_chat':
      case 'chat_message':
      case 'church_chat':
        return kChurchShellIndexPainel;
      default:
        return null;
    }
  }
}
