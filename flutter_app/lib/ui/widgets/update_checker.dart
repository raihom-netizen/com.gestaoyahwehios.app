import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/app_navigator.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Diálogo premium (não bloqueante): nova versão + Play Store / atualizar.
Future<void> showPremiumVersionUpdateDialog(
  BuildContext context,
  VersionResult vr,
) async {
  final hasUrl = vr.updateUrl.isNotEmpty;
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) {
      final isAndroidStore = !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          hasUrl;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(ThemeCleanPremium.radiusLg),
            child: Material(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ThemeCleanPremium.primary.withValues(alpha: 0.16),
                          const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border(
                        bottom: BorderSide(
                          color: ThemeCleanPremium.primary
                              .withValues(alpha: 0.12),
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: ThemeCleanPremium.softUiCardShadow,
                            border: Border.all(
                              color: const Color(0xFFE8EEF5),
                            ),
                          ),
                          child: Icon(
                            Icons.rocket_launch_rounded,
                            color: ThemeCleanPremium.primary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nova versão disponível',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                  color: Colors.grey.shade900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Sua versão: v$appVersion · Loja: v${vr.current}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  height: 1.3,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                    child: Text(
                      vr.message.isNotEmpty
                          ? vr.message
                          : kDefaultVersionUpdateMessage(vr.current),
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (hasUrl) ...[
                    if (isAndroidStore)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                        child: SelectableText(
                          kDefaultPlayStoreUrl,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              onPressed: () async {
                                Navigator.of(ctx).pop();
                                await VersionService.instance
                                    .openUpdateUrl(vr.updateUrl);
                                if (kIsWeb &&
                                    vr.updateUrl
                                        .startsWith(Uri.base.origin)) {
                                  VersionService.reloadWeb();
                                }
                              },
                              icon: Icon(
                                isAndroidStore
                                    ? Icons.shopping_bag_rounded
                                    : Icons.open_in_new_rounded,
                                size: 22,
                              ),
                              label: Text(
                                isAndroidStore
                                    ? 'Atualizar na Play Store'
                                    : 'Atualizar agora',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(
                              'Depois',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('OK'),
                        ),
                      ),
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

/// Checagem automática ao abrir o app: aviso **dismissível** com link para a loja (sem bloquear uso).
class UpdateChecker extends StatefulWidget {
  final Widget child;

  const UpdateChecker({super.key, required this.child});

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  bool _checked = false;
  int _checkAttempts = 0;
  static const int _maxVersionCheckAttempts = 4;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      Future<void>.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) _check();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    if (_checked) return;
    if (_checkAttempts >= _maxVersionCheckAttempts) {
      _checked = true;
      return;
    }
    _checkAttempts++;
    final vr = await VersionService.instance.check();
    if (!mounted) return;
    if (vr.skippedDueToError) {
      final delaySec = 6 + _checkAttempts * 5;
      await Future<void>.delayed(Duration(seconds: delaySec));
      if (!mounted) return;
      _check();
      return;
    }
    _checked = true;
    if (!vr.outdated) return;
    if (!mounted) return;
    // Contexto do [UpdateChecker] fica *acima* do [Navigator] do [MaterialApp]:
    // usar a chave raiz evita barrier escuro + diálogo em branco no mobile.
    final navCtx = appRootNavigatorKey.currentContext;
    if (navCtx != null && navCtx.mounted) {
      await showPremiumVersionUpdateDialog(navCtx, vr);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final ctx2 = appRootNavigatorKey.currentContext;
      if (ctx2 == null || !ctx2.mounted) return;
      await showPremiumVersionUpdateDialog(ctx2, vr);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
