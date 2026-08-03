import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/design_system/app_theme.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_user_facing_error.dart';

/// Sessões / aparelhos ligados à conta Telegram (TDLib).
class TdlibSessionsPage extends StatefulWidget {
  const TdlibSessionsPage({super.key});

  @override
  State<TdlibSessionsPage> createState() => _TdlibSessionsPageState();
}

class _TdlibSessionsPageState extends State<TdlibSessionsPage> {
  static const _accent = Color(0xFF0D9488);
  bool _loading = true;
  List<TdlibSessionInfo> _sessions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await TdLibService.instance.getActiveSessions();
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  Future<void> _terminate(TdlibSessionInfo s) async {
    try {
      await TdLibService.instance.terminateSession(s.id);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Sessão encerrada'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<void> _terminateOthers() async {
    try {
      await TdLibService.instance.terminateAllOtherSessions();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Outras sessões encerradas'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  Future<void> _disconnectThisDevice() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar o Telegram?'),
        content: const Text(
          'Este aparelho sai da conta conectada. Para usar o chat de novo, '
          'informe o telefone e confirme o código outra vez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await TdLibService.instance.logOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.successSnackBar('Telegram desconectado.'),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.errorSnackBarWithRetry(formatTdlibErrorForUser(e)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: const Text('Aparelhos ligados'),
        actions: [
          TextButton(
            onPressed: _loading ? null : _terminateOthers,
            child: const Text(
              'Encerrar outros',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                itemCount: _sessions.isEmpty ? 1 : _sessions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (_sessions.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nenhuma sessão listada.\nConecte o chat e atualize.',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final s = _sessions[i];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: s.isCurrent
                              ? _accent.withValues(alpha: 0.45)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      leading: Icon(
                        Icons.devices_rounded,
                        color: s.isCurrent ? _accent : Colors.grey,
                      ),
                      title: Text(
                        s.deviceModel,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          s.appName,
                          s.platform,
                          if ((s.ipAddress ?? '').isNotEmpty) s.ipAddress!,
                          if ((s.country ?? '').isNotEmpty) s.country!,
                          if (s.isCurrent) 'Este aparelho',
                        ].where((e) => e.trim().isNotEmpty).join(' · '),
                      ),
                      trailing: s.isCurrent
                          ? IconButton(
                              tooltip: 'Desconectar este aparelho',
                              onPressed: _disconnectThisDevice,
                              icon: const Icon(
                                Icons.link_off_rounded,
                                color: Color(0xFFB91C1C),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Encerrar',
                              onPressed: () => _terminate(s),
                              icon: const Icon(
                                Icons.logout_rounded,
                                color: Color(0xFFB91C1C),
                              ),
                            ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
