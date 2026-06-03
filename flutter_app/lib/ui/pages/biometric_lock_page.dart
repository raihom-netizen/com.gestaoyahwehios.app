import 'package:flutter/material.dart';
import '../../services/biometric_service.dart';

/// Bloqueio biométrico premium — o painel só renderiza após digital/Face ID.
/// Falha ou cancelamento mantém este ecrã (sem `signOut`). Saída: Configurações → Trocar de conta.
class BiometricLockPage extends StatefulWidget {
  final Widget child;
  const BiometricLockPage({super.key, required this.child});

  @override
  State<BiometricLockPage> createState() => _BiometricLockPageState();
}

class _BiometricLockPageState extends State<BiometricLockPage> {
  bool _unlocking = true;
  bool _unlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryUnlock());
  }

  Future<void> _tryUnlock() async {
    setState(() => _unlocking = true);
    final ok = await BiometricService().authenticate();
    if (!mounted) return;
    setState(() {
      _unlocking = false;
      _unlocked = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.fingerprint, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Desbloqueie com biometria',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _unlocking
                        ? 'Aguardando sua digital ou Face ID…'
                        : 'Não foi possível autenticar. Toque em «Tentar de novo».',
                    textAlign: TextAlign.center,
                  ),
                  if (_unlocking) ...[
                    const SizedBox(height: 16),
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(strokeWidth: 2.8),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _unlocking ? null : _tryUnlock,
                      child: Text(
                        _unlocking ? 'A aguardar biometria…' : 'Tentar de novo',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Para sair desta conta: Configurações → Trocar de conta.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
