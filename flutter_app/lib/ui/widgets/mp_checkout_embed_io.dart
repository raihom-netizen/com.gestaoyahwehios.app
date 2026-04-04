import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Checkout Mercado Pago embutido (Android / iOS / macOS). Outras plataformas: abrir no navegador.
class MpCheckoutEmbed extends StatefulWidget {
  final String checkoutUrl;
  /// Prefixo da `back_url` do backend — ao navegar para fora do domínio MP, dispara [onLikelyFinished].
  final String returnUrlHint;
  final ValueChanged<String>? onLikelyFinished;

  const MpCheckoutEmbed({
    super.key,
    required this.checkoutUrl,
    this.returnUrlHint = '',
    this.onLikelyFinished,
  });

  @override
  State<MpCheckoutEmbed> createState() => _MpCheckoutEmbedState();
}

class _MpCheckoutEmbedState extends State<MpCheckoutEmbed> {
  WebViewController? _controller;
  var _ready = false;

  static bool _supportsEmbeddedWebView(BuildContext context) {
    if (kIsWeb) return false;
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  bool _isReturnOrAppUrl(String url) {
    if (url.isEmpty) return false;
    final low = url.toLowerCase();
    if (low.contains('mercadopago.com') ||
        low.contains('mercadolibre.com') ||
        low.contains('mercadolivre.com')) {
      return false;
    }
    final hint = widget.returnUrlHint.trim();
    if (hint.isNotEmpty) {
      if (url.startsWith(hint)) return true;
      try {
        final h = Uri.parse(hint);
        final u = Uri.parse(url);
        if (h.host.isNotEmpty && u.host == h.host) {
          if (u.path.contains('/planos') ||
              u.path.contains('/painel') ||
              u.path.contains('/renew')) {
            return true;
          }
        }
      } catch (_) {}
    }
    try {
      final u = Uri.parse(url);
      final path = u.path.toLowerCase();
      if (path.contains('/planos') ||
          path.contains('/painel') ||
          path.contains('/renew')) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_supportsEmbeddedWebView(context)) return;
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              if (_isReturnOrAppUrl(request.url)) {
                widget.onLikelyFinished?.call(request.url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onUrlChange: (UrlChange change) {
              final u = change.url;
              if (u != null && _isReturnOrAppUrl(u)) {
                widget.onLikelyFinished?.call(u);
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.checkoutUrl));
      setState(() {
        _controller = c;
        _ready = true;
      });
    });
  }

  Future<void> _openExternal() async {
    final u = Uri.tryParse(widget.checkoutUrl);
    if (u == null) return;
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportsEmbeddedWebView(context)) {
      return _ExternalCheckoutPrompt(
        onOpen: _openExternal,
        checkoutUrl: widget.checkoutUrl,
      );
    }
    if (!_ready || _controller == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Carregando checkout seguro…'),
            ],
          ),
        ),
      );
    }
    return WebViewWidget(controller: _controller!);
  }
}

class _ExternalCheckoutPrompt extends StatelessWidget {
  final VoidCallback onOpen;
  final String checkoutUrl;

  const _ExternalCheckoutPrompt({
    required this.onOpen,
    required this.checkoutUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_browser_rounded,
                      size: 48, color: Colors.blue.shade700),
                  const SizedBox(height: 16),
                  const Text(
                    'Checkout do Mercado Pago',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nesta plataforma o pagamento abre no navegador. Depois de concluir, volte ao app — a licença atualiza automaticamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.payment_rounded),
                    label: const Text('Abrir pagamento PIX / cartão'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    checkoutUrl,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
