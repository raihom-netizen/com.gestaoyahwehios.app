import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/yahweh_contact_button_labels.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';
import 'package:gestao_yahweh/ui/widgets/church_telegram_webview.dart';

/// Tela cheia do Yahweh Chat (motor embutido — UI só marca Yahweh).
class ChurchTelegramInAppPage extends StatefulWidget {
  const ChurchTelegramInAppPage({
    super.key,
    required this.initialUrl,
    this.title = YahwehContactButtonLabels.yahwehChat,
    this.subtitle,
  });

  final String initialUrl;
  final String title;
  final String? subtitle;

  /// Abre o cliente embutido no root navigator (fora do shell apertado).
  static Future<void> open(
    BuildContext context, {
    required String urlOrHandle,
    String title = YahwehContactButtonLabels.yahwehChat,
    String? subtitle,
  }) {
    final url = ChurchTelegramLauncher.toWebClientUrl(urlOrHandle);
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChurchTelegramInAppPage(
          initialUrl: url,
          title: title,
          subtitle: subtitle,
        ),
      ),
    );
  }

  @override
  State<ChurchTelegramInAppPage> createState() =>
      _ChurchTelegramInAppPageState();
}

class _ChurchTelegramInAppPageState extends State<ChurchTelegramInAppPage> {
  final GlobalKey<ChurchTelegramWebViewState> _webKey =
      GlobalKey<ChurchTelegramWebViewState>();

  static const _accent = YahwehContactButtonLabels.accent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            if ((widget.subtitle ?? '').trim().isNotEmpty)
              Text(
                widget.subtitle!.trim(),
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Início do chat',
            onPressed: () => _webKey.currentState?.openHome(),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => _webKey.currentState?.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) async {
              if (v == 'external') {
                await ChurchTelegramLauncher.open(
                  context,
                  urlOrHandle: widget.initialUrl,
                );
              } else if (v == 'home') {
                await _webKey.currentState?.openHome();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'home',
                child: Text('Lista de conversas'),
              ),
              PopupMenuItem(
                value: 'external',
                child: Text('Abrir fora do app'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: _accent.withValues(alpha: 0.22),
              child: const Text(
                'Motor Telegram · fotos, vídeos, áudios e arquivos. '
                'Na 1ª vez, entre com o número do seu Telegram.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: ChurchTelegramWebView(
                key: _webKey,
                initialUrl: widget.initialUrl,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
