import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/firebase_bootstrap_service.dart';
import 'package:gestao_yahweh/core/firebase_user_facing_error.dart';

/// Ecrã quando [FirebaseBootstrapService.initialize] falha no arranque.
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

  @override
  void initState() {
    super.initState();
    final f = widget.result.failure;
    if (f != null) {
      _detail = formatFirebaseErrorForUser(f, stackTrace: f.stackTrace);
    }
  }

  Future<void> _retry() async {
    setState(() {
      _busy = true;
      _detail = null;
    });
    try {
      await FirebaseBootstrapService.restart();
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
              const Icon(Icons.cloud_off_rounded, size: 56),
              const SizedBox(height: 16),
              Text(
                'Firebase não iniciou',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                _detail ??
                    'Não foi possível ligar aos serviços da nuvem. '
                    'Verifique internet e tente reconectar.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
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
                label: Text(_busy ? 'A reconectar…' : 'Reconectar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
