import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/sync_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Escuta [SyncService] e conectividade — SnackBars temporários, sem banner fixo.
class SyncFeedbackListener extends StatefulWidget {
  const SyncFeedbackListener({super.key, required this.child});

  final Widget child;

  @override
  State<SyncFeedbackListener> createState() => _SyncFeedbackListenerState();
}

class _SyncFeedbackListenerState extends State<SyncFeedbackListener> {
  StreamSubscription<bool>? _onlineSub;
  bool _wasOffline = false;
  SyncServiceState _lastState = SyncServiceState.idle;

  @override
  void initState() {
    super.initState();
    _wasOffline = !AppConnectivityService.instance.isOnline;
    SyncService.state.addListener(_onSyncState);
    _onlineSub = AppConnectivityService.instance.onlineStream.listen((online) {
      if (_wasOffline && online) {
        // Reconexão: sync silenciosa; feedback só via SyncService.success.
      } else if (!_wasOffline && !online) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
        _showSnack(
          '⚠ Sem conexão',
          duration: const Duration(seconds: 3),
          background: const Color(0xFFB45309),
        );
        });
      }
      _wasOffline = !online;
    });
  }

  void _onSyncState() {
    final next = SyncService.state.value;
    if (next == _lastState) return;
    _lastState = next;

    if (next == SyncServiceState.success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnack(
          '✔ Atualizado agora',
          duration: const Duration(seconds: 2),
        );
      });
    } else if (next == SyncServiceState.error) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnack(
          'Falha ao sincronizar. Tentando novamente.',
          duration: const Duration(seconds: 4),
          background: ThemeCleanPremium.error,
        );
      });
    }
  }

  void _showSnack(
    String message, {
    Duration duration = const Duration(seconds: 2),
    Color? background,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
      ),
    );
  }

  @override
  void dispose() {
    SyncService.state.removeListener(_onSyncState);
    _onlineSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
