import 'dart:async' show unawaited;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Cliente Telegram Web embutido (Android / iOS / desktop) — mesma velocidade do Telegram.
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
  WebViewController? _controller;
  bool _loading = true;
  double _progress = 0;
  String? _error;
  bool _ready = false;

  /// UA desktop: web.telegram.org funciona melhor (envio de mídia, layout completo).
  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> reload() async {
    await _controller?.reload();
  }

  Future<void> openHome() async {
    await _controller?.loadRequest(
      Uri.parse(ChurchTelegramLauncher.kWebClientHome),
    );
  }

  Future<void> openUrl(String urlOrHandle) async {
    final url = ChurchTelegramLauncher.toWebClientUrl(urlOrHandle);
    await _controller?.loadRequest(Uri.parse(url));
  }

  Future<void> _init() async {
    try {
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      final controller = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0E1621))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) {
              if (!mounted) return;
              setState(() => _progress = p / 100.0);
            },
            onPageStarted: (_) {
              if (!mounted) return;
              setState(() {
                _loading = true;
                _error = null;
              });
            },
            onPageFinished: (url) {
              if (!mounted) return;
              setState(() {
                _loading = false;
                _ready = true;
              });
              widget.onTitleHint?.call(url);
            },
            onWebResourceError: (err) {
              if (!mounted) return;
              if (err.isForMainFrame == true) {
                setState(() {
                  _loading = false;
                  _error = err.description;
                });
              }
            },
            onNavigationRequest: (req) {
              final u = req.url.toLowerCase();
              if (u.startsWith('https://web.telegram.org') ||
                  u.startsWith('https://telegram.org') ||
                  u.startsWith('https://t.me') ||
                  u.startsWith('https://telegram.me') ||
                  u.contains('accounts.google.com') ||
                  u.contains('appleid.apple.com') ||
                  u.startsWith('about:blank')) {
                return NavigationDecision.navigate;
              }
              if (u.startsWith('tg://') || u.startsWith('telegram://')) {
                unawaited(launchUrl(
                  Uri.parse(req.url),
                  mode: LaunchMode.externalApplication,
                ));
                return NavigationDecision.prevent;
              }
              unawaited(launchUrl(
                Uri.parse(req.url),
                mode: LaunchMode.externalApplication,
              ));
              return NavigationDecision.prevent;
            },
          ),
        );

      await controller.setUserAgent(_desktopUa);

      final platform = controller.platform;
      if (platform is AndroidWebViewController) {
        AndroidWebViewController.enableDebugging(kDebugMode);
        await platform.setMediaPlaybackRequiresUserGesture(false);
        await platform.setOnPlatformPermissionRequest((request) {
          request.grant();
        });
        await platform.setOnShowFileSelector((params) async {
          final multi = params.mode == FileSelectorMode.openMultiple;
          final result = await FilePicker.pickFiles(
            allowMultiple: multi,
            type: FileType.any,
            withData: false,
          );
          if (result == null || result.files.isEmpty) return <String>[];
          return result.files
              .where((f) => f.path != null && f.path!.isNotEmpty)
              .map((f) => Uri.file(f.path!).toString())
              .toList();
        });
      } else if (platform is WebKitWebViewController) {
        await platform.setAllowsBackForwardNavigationGestures(true);
      }

      final url = ChurchTelegramLauncher.toWebClientUrl(widget.initialUrl);
      await controller.loadRequest(Uri.parse(url));

      if (!mounted) return;
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ChurchTelegramWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialUrl != widget.initialUrl && _controller != null) {
      unawaited(openUrl(widget.initialUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _controller == null) {
      return _ErrorPane(
        message: _error!,
        onRetry: () {
          setState(() {
            _error = null;
            _loading = true;
          });
          unawaited(_init());
        },
        fallbackUrl: widget.initialUrl,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_controller != null)
          WebViewWidget(controller: _controller!)
        else
          const ColoredBox(color: Color(0xFF0E1621)),
        if (_loading || !_ready)
          const ColoredBox(
            color: Color(0xFF0E1621),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF0D9488),
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Carregando Yahweh Chat…',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_loading && _progress > 0 && _progress < 1)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: const Color(0xFF0D9488),
            ),
          ),
        if (_error != null && _controller != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.black.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Aviso: $_error',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.message,
    required this.onRetry,
    required this.fallbackUrl,
  });

  final String message;
  final VoidCallback onRetry;
  final String fallbackUrl;

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
              const Icon(Icons.forum_rounded, size: 56, color: Color(0xFF0D9488)),
              const SizedBox(height: 16),
              const Text(
                'Não foi possível abrir o Yahweh Chat aqui',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar de novo'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  minimumSize: const Size(0, 48),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => ChurchTelegramLauncher.open(
                  context,
                  urlOrHandle: fallbackUrl,
                ),
                child: Text(
                  'Abrir fora do app',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
