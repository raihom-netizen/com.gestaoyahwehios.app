import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';

/// Ecrã **só** quando [FirebaseBootstrapService.initialize] falha no arranque frio.
/// Tenta recuperação automática (Controle Total) antes de pedir ação manual.
class FirebaseBootstrapRecoveryPage extends StatefulWidget {
  const FirebaseBootstrapRecoveryPage({
    super.key,
    required this.result,
    required this.onRecovered,
  });

  final FirebaseBootstrapResult result;
  final Future<void> Function() onRecovered;

  @override
  State<FirebaseBootstrapRecoveryPage> createState() =>
      _FirebaseBootstrapRecoveryPageState();
}

class _FirebaseBootstrapRecoveryPageState
    extends State<FirebaseBootstrapRecoveryPage> {
  bool _busy = false;
  String? _detail;
  int _autoAttempts = 0;

  @override
  void initState() {
    super.initState();
    final f = widget.result.failure;
    if (f != null) {
      _detail = formatFirebaseErrorForUser(f, stackTrace: f.stackTrace);
    }
    unawaited(_autoRecoverSilently());
  }

  Future<void> _autoRecoverSilently() async {
    for (var i = 0; i < 6; i++) {
      if (!mounted) return;
      _autoAttempts = i + 1;
      try {
        await FirebaseBootstrapService.ensureAlwaysOn(
          refreshAuthToken: false,
          maxAttempts: 3,
        );
        final r = await FirebaseBootstrapService.initialize();
        if (r.isReady) {
          await widget.onRecovered();
          return;
        }
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: 400 + i * 350));
    }
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _detail = null;
    });
    try {
      await FirebaseBootstrapService.ensureAlwaysOn(refreshAuthToken: true);
      final r = await FirebaseBootstrapService.initialize();
      if (!r.isReady && r.failure != null) {
        throw r.failure!;
      }
      await widget.onRecovered();
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _detail = formatFirebaseErrorForUser(e, stackTrace: st);
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.cloud_sync_rounded, size: 56),
              const SizedBox(height: 16),
              Text(
                'A ligar aos serviços…',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _detail ??
                    'A app está a restabelecer a ligação. '
                    'Verifique a internet; a sincronização continua em segundo plano.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              if (_busy || _autoAttempts > 0) ...[
                const SizedBox(height: 24),
                const LinearProgressIndicator(),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy ? null : _retry,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(_busy ? 'A ligar…' : 'Tentar de novo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
