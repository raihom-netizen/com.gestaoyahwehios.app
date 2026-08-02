import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/features/chat/presentation/tdlib_chat_thread_page.dart';

/// Busca global de mensagens no Telegram (TDLib).
class TdlibGlobalSearchPage extends StatefulWidget {
  const TdlibGlobalSearchPage({
    super.key,
    required this.churchId,
  });

  final String churchId;

  @override
  State<TdlibGlobalSearchPage> createState() => _TdlibGlobalSearchPageState();
}

class _TdlibGlobalSearchPageState extends State<TdlibGlobalSearchPage> {
  static const _accent = Color(0xFF0D9488);
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<TdlibSearchHit> _hits = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      unawaited(_search(v));
    });
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    setState(() => _loading = true);
    final hits = await TdLibService.instance.searchMessagesGlobal(query);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            hintText: 'Buscar em todas as conversas…',
            hintStyle: TextStyle(color: Colors.white70),
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _hits.isEmpty
                ? Center(
                    child: Text(
                      _ctrl.text.trim().isEmpty
                          ? 'Digite para buscar mensagens no Telegram'
                          : 'Nenhum resultado',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _hits.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final h = _hits[i];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Text(
                            h.chatTitle,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            h.message.text.isNotEmpty
                                ? h.message.text
                                : h.message.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            var isGroup = false;
                            for (final c
                                in TdLibService.instance.cachedChats) {
                              if (c.id == h.chatId) {
                                isGroup = c.isGroup;
                                break;
                              }
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TdlibChatThreadPage(
                                  chatId: h.chatId,
                                  title: h.chatTitle,
                                  churchId: widget.churchId,
                                  isGroup: isGroup,
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
