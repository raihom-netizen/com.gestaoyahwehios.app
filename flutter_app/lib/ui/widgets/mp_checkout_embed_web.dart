// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

/// Checkout Mercado Pago na mesma página (iframe). Se o MP bloquear iframe, use o botão de fallback.
class MpCheckoutEmbed extends StatefulWidget {
  final String checkoutUrl;
  final String returnUrlHint;
  final ValueChanged<String>? onLikelyFinished;
  /// Texto abaixo do iframe (ex.: doação vs licença). Se nulo, usa mensagem padrão.
  final String? footerHint;

  const MpCheckoutEmbed({
    super.key,
    required this.checkoutUrl,
    this.returnUrlHint = '',
    this.onLikelyFinished,
    this.footerHint,
  });

  @override
  State<MpCheckoutEmbed> createState() => _MpCheckoutEmbedState();
}

class _MpCheckoutEmbedState extends State<MpCheckoutEmbed> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'mp-checkout-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    final iframe = html.IFrameElement()
      ..src = widget.checkoutUrl
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'payment';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) => iframe);
  }

  /// Abre em **nova aba** para não sair do app Flutter (substituir `location.href` derrubava o painel inteiro).
  Future<void> _openInNewTab() async {
    html.window.open(widget.checkoutUrl, '_blank', 'noopener,noreferrer');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: HtmlElementView(viewType: _viewType),
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: Colors.blue.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.footerHint ??
                            'PIX ou cartão acima. Ao finalizar, a licença libera em segundos (webhook).',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.35),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _openInNewTab,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text(
                    'Se a área acima estiver em branco, abrir checkout em nova aba',
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
