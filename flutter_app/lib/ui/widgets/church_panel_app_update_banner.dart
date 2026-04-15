import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chave: última versão-alvo para a qual o utilizador pediu para ocultar o banner.
const _kPrefsDismissedTarget = 'church_panel_update_dismissed_target_v1';

/// Faixa no topo do painel da igreja quando `config/appVersion` indica versão mais nova (Android → Play Store).
class ChurchPanelAppUpdateBanner extends StatefulWidget {
  const ChurchPanelAppUpdateBanner({super.key});

  @override
  State<ChurchPanelAppUpdateBanner> createState() =>
      _ChurchPanelAppUpdateBannerState();
}

class _ChurchPanelAppUpdateBannerState extends State<ChurchPanelAppUpdateBanner> {
  String? _dismissedTarget;
  bool _prefsReady = false;

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_kPrefsDismissedTarget);
    if (mounted) {
      setState(() {
        _dismissedTarget = v;
        _prefsReady = true;
      });
    }
  }

  Future<void> _dismissForTarget(String targetVersion) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPrefsDismissedTarget, targetVersion);
    if (mounted) setState(() => _dismissedTarget = targetVersion);
  }

  @override
  Widget build(BuildContext context) {
    // Painel web: aviso para recarregar (nova build). Android: Play Store.
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    if (!_prefsReady) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.doc('config/appVersion').snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final hint = VersionService.instance.panelUpdateHintFromConfigData(data);
        if (hint == null) return const SizedBox.shrink();
        if (_dismissedTarget != null && _dismissedTarget == hint.targetVersion) {
          return const SizedBox.shrink();
        }

        return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Material(
                elevation: 0,
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeCleanPremium.primary.withOpacity(0.12),
                        const Color(0xFFFFF7ED),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
                    border: Border.all(
                      color: ThemeCleanPremium.primary.withOpacity(0.35),
                    ),
                    boxShadow: ThemeCleanPremium.softUiCardShadow,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: ThemeCleanPremium.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.system_update_rounded,
                                color: ThemeCleanPremium.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    kIsWeb
                                        ? 'Nova versão do painel disponível'
                                        : 'Nova versão disponível',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey.shade900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    hint.message,
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Versão instalada: v$appVersion · Loja: v${hint.targetVersion}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ocultar até a próxima versão',
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                unawaited(_dismissForTarget(hint.targetVersion));
                              },
                              icon: Icon(Icons.close_rounded,
                                  color: Colors.grey.shade600, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                unawaited(_dismissForTarget(hint.targetVersion));
                              },
                              child: const Text('Agora não'),
                            ),
                            if (kIsWeb) ...[
                              OutlinedButton.icon(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  unawaited(
                                    VersionService.instance
                                        .openUpdateUrl(kDefaultPlayStoreUrl),
                                  );
                                },
                                icon: const Icon(Icons.android_rounded, size: 18),
                                label: const Text('App na Play Store'),
                              ),
                              FilledButton.icon(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  VersionService.reloadWeb();
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Recarregar painel'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ] else
                              FilledButton.icon(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  final url = hint.storeUrl.isNotEmpty
                                      ? hint.storeUrl
                                      : kDefaultPlayStoreUrl;
                                  unawaited(
                                    VersionService.instance.openUpdateUrl(url),
                                  );
                                },
                                icon: const Icon(Icons.shopping_bag_rounded,
                                    size: 18),
                                label: const Text('Atualizar na Play Store'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ThemeCleanPremium.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
      },
    );
  }
}
