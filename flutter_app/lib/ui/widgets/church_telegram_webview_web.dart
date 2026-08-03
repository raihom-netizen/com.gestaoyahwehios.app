// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';

/// Web: `web.telegram.org` responde `X-Frame-Options: deny` — o navegador
/// **sempre** recusa embutir isso num `<iframe>` (não há contorno possível
/// no cliente). Por isso não tentamos iframe aqui: mostramos um painel claro
/// e abrimos o Telegram Web numa nova aba (mesma conta, mesma conversa).
class ChurchTelegramWebView extends StatefulWidget {
  const ChurchTelegramWebView({
    super.key,
    required this.initialUrl,
    this.onTitleHint,
  });

  final String initialUrl;
  final ValueChanged<String>? onTitleHint;

  @override
  State<ChurchTelegramWebView> createState() => ChurchTelegramWebViewState();
}

class ChurchTelegramWebViewState extends State<ChurchTelegramWebView> {
  late String _src;

  @override
  void initState() {
    super.initState();
    _src = ChurchTelegramLauncher.toWebClientUrl(widget.initialUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onTitleHint?.call(_src);
    });
  }

  Future<void> reload() async => _openNewTab();

  Future<void> openHome() async {
    _src = ChurchTelegramLauncher.kWebClientHome;
    if (mounted) setState(() {});
  }

  Future<void> openUrl(String urlOrHandle) async {
    _src = ChurchTelegramLauncher.toWebClientUrl(urlOrHandle);
    if (mounted) setState(() {});
  }

  void _openNewTab() {
    html.window.open(_src, '_blank', 'noopener,noreferrer');
  }

  @override
  void didUpdateWidget(covariant ChurchTelegramWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl != widget.initialUrl) {
      openUrl(widget.initialUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0E1621),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send_rounded, color: Colors.white70, size: 44),
              const SizedBox(height: 16),
              const Text(
                'O navegador não permite embutir o Telegram Web aqui dentro.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Toque no botão abaixo para abrir numa nova aba — mesma conta, '
                'mesma conversa, fotos e vídeos funcionam normalmente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.35),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _openNewTab,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Abrir Telegram Web'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
