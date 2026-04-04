import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/services/version_service.dart';

/// Widget que envolve o app e faz a checagem automática de versão ao abrir
/// (web e mobile). Não depende do usuário: busca no Firestore e exibe
/// diálogo ou bloqueia se houver atualização obrigatória.
class UpdateChecker extends StatefulWidget {
  final Widget child;

  const UpdateChecker({super.key, required this.child});

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker> {
  bool _checked = false;
  VersionResult? _result;
  int _checkAttempts = 0;
  static const int _maxVersionCheckAttempts = 4;

  @override
  void initState() {
    super.initState();
    // Web: atrasar checagem para o primeiro frame estabilizar (evita reload que pisca a tela).
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
    // Web: nunca recarrega sozinho (evita tela piscando). Só exibe diálogo para o usuário clicar em Atualizar.
    setState(() => _result = vr);
    if (!mounted) return;
    // Forçar atualização: tela full-screen no build(); não abrir diálogo
    if (vr.force) return;
    await _showDialog(vr);
  }

  Future<void> _showDialog(VersionResult vr) async {
    final isForce = vr.force;
    await showDialog<void>(
      context: context,
      barrierDismissible: !isForce,
      builder: (ctx) => AlertDialog(
        title: const Text('Atualização disponível'),
        content: SingleChildScrollView(
          child: Text(
            vr.message.isNotEmpty
                ? vr.message
                : 'Uma nova versão (${vr.current}) está disponível. '
                    'Você está na v$appVersion. Atualize para continuar.',
          ),
        ),
        actions: [
          if (vr.updateUrl.isNotEmpty)
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await VersionService.instance.openUpdateUrl(vr.updateUrl);
                if (kIsWeb && vr.updateUrl.startsWith(Uri.base.origin)) {
                  VersionService.reloadWeb();
                }
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text('Atualizar'),
            ),
          if (!isForce)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Depois'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Forçar atualização (estilo Controle Total): bloqueia o app até o usuário atualizar
    if (_result != null && _result!.force) {
      return _ForceUpdateScreen(result: _result!);
    }
    return widget.child;
  }
}

/// Tela full-screen que bloqueia o uso do app até atualizar (igual Controle Total no painel ADM).
class _ForceUpdateScreen extends StatelessWidget {
  final VersionResult result;

  const _ForceUpdateScreen({required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.system_update_rounded, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  'Atualização obrigatória',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  result.message.isNotEmpty
                      ? result.message
                      : 'Uma nova versão (${result.current}) está disponível. Atualize para continuar usando o app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                if (result.updateUrl.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () async {
                      await VersionService.instance.openUpdateUrl(result.updateUrl);
                      if (kIsWeb && result.updateUrl.startsWith(Uri.base.origin)) {
                        VersionService.reloadWeb();
                      }
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Atualizar agora'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
