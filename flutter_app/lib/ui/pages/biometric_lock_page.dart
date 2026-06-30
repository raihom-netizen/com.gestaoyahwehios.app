import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/biometric_service.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_saas_visual_shell.dart';

/// Bloqueio biométrico premium — o painel só renderiza após digital/Face ID.
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
    if (ok) {
      BiometricService.markSessionBiometricUnlocked();
    }
    setState(() {
      _unlocking = false;
      _unlocked = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;

    return ChurchWisdomLoginBackdrop(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  YahwehSaasVisualShell.hero(
                    title: 'Desbloqueie com biometria',
                    subtitle: _unlocking
                        ? 'Aguardando digital ou Face ID…'
                        : 'Toque em «Tentar de novo» para autenticar.',
                    logoSize: 80,
                  ),
                  const SizedBox(height: 16),
                  YahwehSaasVisualShell.surfaceCard(
                    child: Column(
                      children: [
                        Icon(Icons.fingerprint_rounded,
                            size: 56, color: kChurchWisdomLoginTeal),
                        if (_unlocking) ...[
                          const SizedBox(height: 16),
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 2.8),
                          ),
                        ],
                        const SizedBox(height: 16),
                        YahwehSaasVisualShell.primaryButton(
                          label: 'Tentar de novo',
                          icon: Icons.lock_open_rounded,
                          onPressed: _unlocking ? null : _tryUnlock,
                          loading: _unlocking,
                        ),
                      ],
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
