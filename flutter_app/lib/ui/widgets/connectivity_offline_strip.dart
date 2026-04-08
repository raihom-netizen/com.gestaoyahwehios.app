import 'dart:async';

import 'package:flutter/material.dart';

import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Faixa no painel quando não há interface de rede: lembra que o Firestore grava localmente e sincroniza depois.
class ConnectivityOfflineStrip extends StatefulWidget {
  const ConnectivityOfflineStrip({super.key});

  @override
  State<ConnectivityOfflineStrip> createState() =>
      _ConnectivityOfflineStripState();
}

class _ConnectivityOfflineStripState extends State<ConnectivityOfflineStrip> {
  late bool _online;
  StreamSubscription<bool>? _sub;

  @override
  void initState() {
    super.initState();
    _online = AppConnectivityService.instance.isOnline;
    _sub = AppConnectivityService.instance.onlineStream.listen((online) {
      final wasOnline = _online;
      if (!mounted) return;
      setState(() => _online = online);
      if (wasOnline == false && online) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text(
                'Internet restabelecida. Enviando alterações salvas no aparelho…',
              ),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              backgroundColor: ThemeCleanPremium.primary,
            ),
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_online) return const SizedBox.shrink();
    return Material(
      color: const Color(0xFF92400E),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sem conexão. Você pode ver dados já carregados e continuar editando; '
                'o app guarda no aparelho e sincroniza com a nuvem quando a internet voltar.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.98),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
