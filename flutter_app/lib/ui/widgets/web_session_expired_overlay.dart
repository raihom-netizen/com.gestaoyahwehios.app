import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/web_panel_stability.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Web: quando a sessão Firebase expira, mostra «Entrar novamente» — **sem** recovery automático.
class WebSessionExpiredOverlay extends StatefulWidget {
  const WebSessionExpiredOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<WebSessionExpiredOverlay> createState() =>
      _WebSessionExpiredOverlayState();
}

class _WebSessionExpiredOverlayState extends State<WebSessionExpiredOverlay> {
  @override
  void initState() {
    super.initState();
    WebPanelStability.sessionExpiredNotifier.addListener(_onExpiredChanged);
  }

  @override
  void dispose() {
    WebPanelStability.sessionExpiredNotifier.removeListener(_onExpiredChanged);
    super.dispose();
  }

  void _onExpiredChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _signInAgain() async {
    WebPanelStability.clearOnSignOut();
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/igreja/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !WebPanelStability.isSessionExpired) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.42),
          dismissible: false,
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_clock_rounded,
                      size: 52,
                      color: ThemeCleanPremium.primary.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Sessão expirada',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Saia e entre de novo no painel para continuar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _signInAgain,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Entrar novamente'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
