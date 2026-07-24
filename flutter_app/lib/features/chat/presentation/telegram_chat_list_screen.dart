import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/design_system/app_theme.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';

/// Lista de chats após autorização TDLib.
class TelegramChatListScreen extends StatefulWidget {
  const TelegramChatListScreen({super.key});

  @override
  State<TelegramChatListScreen> createState() => _TelegramChatListScreenState();
}

class _TelegramChatListScreenState extends State<TelegramChatListScreen> {
  StreamSubscription<List<TdlibChatPreview>>? _chatsSub;
  StreamSubscription<TdlibAuthSnapshot>? _authSub;
  List<TdlibChatPreview> _chats = const [];
  TdlibAuthSnapshot _auth = TdlibAuthSnapshot.idle;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final svc = TdLibService.instance;
    _auth = svc.currentAuth;
    _chatsSub = svc.chatsStream.listen((list) {
      if (!mounted) return;
      setState(() {
        _chats = list;
        _loading = false;
      });
    });
    _authSub = svc.authorizationStateStream.listen((snap) {
      if (!mounted) return;
      setState(() => _auth = snap);
    });
    unawaited(svc.refreshChats().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    }));
  }

  @override
  void dispose() {
    _chatsSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('YAHWEH Chat'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () async {
              setState(() => _loading = true);
              await TdLibService.instance.refreshChats();
              if (mounted) setState(() => _loading = false);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.92),
                  AppColors.primaryLight.withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _auth.phase == TdlibAuthPhase.ready
                        ? 'Conectado ao Motor YAHWEH…'
                        : (_auth.message ?? 'Sessão TDLib'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: _chats.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _loading
                            ? 'Carregando conversas…'
                            : 'Nenhuma conversa ainda.\n'
                                'Abra o chat uma vez para sincronizar, '
                                'depois toque em atualizar.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _chats.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final c = _chats[i];
                      return Material(
                        color: theme.colorScheme.surface,
                        elevation: 0.5,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          minVerticalPadding: 12,
                          leading: CircleAvatar(
                            backgroundColor:
                                AppColors.primary.withValues(alpha: 0.15),
                            child: Text(
                              c.title.isNotEmpty
                                  ? c.title.substring(0, 1).toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: c.lastMessagePreview == null
                              ? null
                              : Text(
                                  c.lastMessagePreview!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: c.unreadCount > 0
                              ? Badge(
                                  label: Text('${c.unreadCount}'),
                                  child: const SizedBox(width: 8, height: 8),
                                )
                              : null,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Chat ${c.id} — sala de mensagens em breve',
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
