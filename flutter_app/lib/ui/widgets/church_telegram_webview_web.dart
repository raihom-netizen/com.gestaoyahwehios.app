// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';

/// Telegram Web embutido no painel web (iframe). Sessão/cookies do browser.
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
  late final String _viewType;
  late String _src;
  html.IFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    _src = ChurchTelegramLauncher.toWebClientUrl(widget.initialUrl);
    _viewType =
        'tg-web-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    _iframe = html.IFrameElement()
      ..src = _src
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'microphone; camera; clipboard-read; clipboard-write; autoplay'
      ..allowFullscreen = true;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _iframe!,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onTitleHint?.call(_src);
    });
  }

  Future<void> reload() async {
    _iframe?.src = _src;
  }

  Future<void> openHome() async {
    _src = ChurchTelegramLauncher.kWebClientHome;
    _iframe?.src = _src;
  }

  Future<void> openUrl(String urlOrHandle) async {
    _src = ChurchTelegramLauncher.toWebClientUrl(urlOrHandle);
    _iframe?.src = _src;
  }

  Future<void> _openNewTab() async {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ColoredBox(
            color: const Color(0xFF0E1621),
            child: HtmlElementView(viewType: _viewType),
          ),
        ),
        Material(
          color: const Color(0xFF17212B),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Yahweh Chat (Telegram). Se a área ficar em branco, abra em nova aba — mídia funciona igual.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
                  ),
                ),
                TextButton(
                  onPressed: _openNewTab,
                  child: const Text(
                    'Nova aba',
                    style: TextStyle(color: Color(0xFF0D9488)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
