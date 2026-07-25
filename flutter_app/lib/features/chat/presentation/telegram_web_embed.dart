import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/design_system/app_theme.dart';
import 'package:gestao_yahweh/services/church_telegram_launcher.dart';

/// Embed do Telegram Web Client — fallback para plataformas sem TDLib (Web).
///
/// Usa `HtmlElementView` / `IFrameElement` (web) para carregar
/// `https://web.telegram.org/a/` dentro do app.
///
/// No mobile (Android/iOS), usa [WebViewWidget] ou abre o app nativo.
class TelegramWebEmbed extends StatelessWidget {
  const TelegramWebEmbed({
    super.key,
    this.urlOrHandle,
  });

  /// Link opcional do grupo/canal. Se nulo, abre home do Telegram Web.
  final String? urlOrHandle;

  @override
  Widget build(BuildContext context) {
    final webUrl = ChurchTelegramLauncher.toWebClientUrl(urlOrHandle);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('YAHWEH Chat'),
        actions: [
          IconButton(
            tooltip: 'Abrir Telegram Web',
            icon: const Icon(Icons.open_in_browser_rounded),
            onPressed: () {
              ChurchTelegramLauncher.open(
                context,
                urlOrHandle: urlOrHandle ?? '',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.9),
                  AppColors.primaryLight.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.telegram, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Motor Telegram — Chat rápido para fotos, vídeos e arquivos',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildWebContent(context, webUrl),
          ),
        ],
      ),
    );
  }

  Widget _buildWebContent(BuildContext context, String url) {
    // Na Web: usar iframe
    // No Mobile: usar url_launcher para abrir Telegram app/web
    // Aqui mostramos um botão para abrir o Telegram Web
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.telegram,
              size: 80,
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'YAHWEH Chat via Telegram',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use o motor do Telegram para enviar fotos, vídeos, '
              'arquivos e mensagens de forma ultra-rápida.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir Telegram Web'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              onPressed: () {
                ChurchTelegramLauncher.open(
                  context,
                  urlOrHandle: urlOrHandle ?? '',
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Ou conecte-se via TDLib no Android/iOS para chat integrado.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
