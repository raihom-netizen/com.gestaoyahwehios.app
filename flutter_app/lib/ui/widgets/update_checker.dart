import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/app_navigator.dart';
import 'package:gestao_yahweh/services/version_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/yahweh_wisdom_visual_kit.dart';

/// Prévia moderna de nova versão — Atualizar ou Cancelar.
/// Na web: **nunca** bloqueia o painel; Cancelar deixa o utilizador lançar dados.
Future<void> showPremiumVersionUpdateDialog(
  BuildContext context,
  VersionResult vr,
) async {
  final hasUrl = vr.updateUrl.isNotEmpty;
  // Web: force nunca tranca a UI (lançamentos estáveis).
  final forced = vr.force && !kIsWeb;
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: !forced,
    builder: (ctx) {
      final isAndroidStore = !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          hasUrl;
      final isIosStore = !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          hasUrl;
      final isWebReload = kIsWeb && hasUrl;
      return PopScope(
        canPop: !forced,
        child: Dialog(
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
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF0F766E),
                            Color(0xFF0D9488),
                            Color(0xFF14B8A6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.12),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.system_update_alt_rounded,
                              color: Color(0xFF0D9488),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  forced
                                      ? 'Atualização obrigatória'
                                      : 'Nova versão disponível',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.4,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  vr.installedLabel.isNotEmpty
                                      ? 'Sua versão: v$appVersion+${vr.installedLabel}\nNova: ${vr.current}'
                                      : 'Sua versão: $appVersionLabel\nNova: ${vr.current}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                      child: Text(
                        vr.message.isNotEmpty
                            ? vr.message
                            : (isWebReload
                                ? 'Há uma versão nova do Gestão Yahweh. '
                                    'Atualize agora para melhorias, ou cancele e '
                                    'continue trabalhando — a página só recarrega '
                                    'se você confirmar.'
                                : kDefaultVersionUpdateMessage(vr.current)),
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.45,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isWebReload)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.35),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shield_moon_rounded,
                                  color: Color(0xFF059669), size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Seus lançamentos em curso não são interrompidos '
                                  'até você tocar em Atualizar.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (hasUrl) ...[
                      if (isAndroidStore || isIosStore)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                          child: SelectableText(
                            vr.updateUrl,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      YahwehWisdomVisualKit.tealAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: () async {
                                  Navigator.of(ctx).pop();
                                  if (isWebReload) {
                                    // Um único reload — só após confirmação do utilizador.
                                    VersionService.reloadWeb();
                                    return;
                                  }
                                  await VersionService.instance
                                      .openUpdateUrl(vr.updateUrl);
                                },
                                icon: Icon(
                                  isAndroidStore
                                      ? Icons.shopping_bag_rounded
                                      : isWebReload
                                          ? Icons.refresh_rounded
                                          : Icons.open_in_new_rounded,
                                  size: 22,
                                ),
                                label: Text(
                                  isAndroidStore
                                      ? 'Atualizar na Play Store'
                                      : isIosStore
                                          ? 'Atualizar no iPhone'
                                          : isWebReload
                                              ? 'Atualizar agora'
                                              : 'Atualizar agora',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            if (!forced) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                height: 44,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.grey.shade800,
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text(
                                    'Cancelar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
        ),
      );
    },
  );
}

/// Checagem automática ao abrir o app: aviso conforme `config/appVersion`.
/// Na web **não** recarrega sozinho — só mostra o diálogo.
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
      // Atraso maior: deixa o painel estabilizar auth/Firestore antes do aviso.
      Future<void>.delayed(const Duration(milliseconds: 4500), () {
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
