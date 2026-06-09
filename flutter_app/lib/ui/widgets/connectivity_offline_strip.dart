import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_offline_status_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Faixa explícita no painel: **Modo offline** / **Sincronizando…** / cache local.
class ConnectivityOfflineStrip extends StatefulWidget {
  const ConnectivityOfflineStrip({super.key});

  @override
  State<ConnectivityOfflineStrip> createState() =>
      _ConnectivityOfflineStripState();
}

class _ConnectivityOfflineStripState extends State<ConnectivityOfflineStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  bool _wasOffline = false;
  StreamSubscription<bool>? _onlineSub;

  @override
  void initState() {
    super.initState();
    _wasOffline = !AppConnectivityService.instance.isOnline;
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _onlineSub = AppConnectivityService.instance.onlineStream.listen((online) {
      if (_wasOffline && online) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: const Text(
                'Internet restabelecida. Sincronizando alterações…',
              ),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              backgroundColor: ThemeCleanPremium.primary,
            ),
          );
        });
      }
      _wasOffline = !online;
    });
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChurchOfflineStatusScope(
      builder: (context, snap) {
        if (!snap.isVisible) {
          if (_spinCtrl.isAnimating) _spinCtrl.stop();
          return const SizedBox.shrink();
        }

        if (snap.phase == ChurchOfflineUiPhase.syncing ||
            snap.phase == ChurchOfflineUiPhase.caching) {
          if (!_spinCtrl.isAnimating) _spinCtrl.repeat();
        } else {
          if (_spinCtrl.isAnimating) _spinCtrl.stop();
        }

        return _OfflineStatusBanner(snapshot: snap, spin: _spinCtrl);
      },
    );
  }
}

class _OfflineStatusBanner extends StatelessWidget {
  const _OfflineStatusBanner({
    required this.snapshot,
    required this.spin,
  });

  final ChurchOfflineStatusSnapshot snapshot;
  final AnimationController spin;

  Color get _background {
    switch (snapshot.phase) {
      case ChurchOfflineUiPhase.offline:
        return const Color(0xFFB45309);
      case ChurchOfflineUiPhase.syncing:
        return ThemeCleanPremium.primary;
      case ChurchOfflineUiPhase.caching:
        return const Color(0xFF0E7490);
      case ChurchOfflineUiPhase.hidden:
        return Colors.transparent;
    }
  }

  IconData get _icon {
    switch (snapshot.phase) {
      case ChurchOfflineUiPhase.offline:
        return Icons.cloud_off_rounded;
      case ChurchOfflineUiPhase.syncing:
        return Icons.sync_rounded;
      case ChurchOfflineUiPhase.caching:
        return Icons.downloading_rounded;
      case ChurchOfflineUiPhase.hidden:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    final showProgress = snapshot.phase == ChurchOfflineUiPhase.syncing ||
        snapshot.phase == ChurchOfflineUiPhase.caching;

    return Material(
      color: _background,
      elevation: 0,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 7 : 9,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showProgress)
                    RotationTransition(
                      turns: spin,
                      child: Icon(_icon, color: Colors.white, size: 20),
                    )
                  else
                    Icon(_icon, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          snapshot.subtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.94),
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (snapshot.pendingQueueCount > 0 &&
                      snapshot.phase != ChurchOfflineUiPhase.offline)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${snapshot.pendingQueueCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              if (showProgress) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    backgroundColor: Colors.white.withValues(alpha: 0.22),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
