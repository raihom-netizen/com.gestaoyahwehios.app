import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

/// Abre / embute o Telegram — velocidade oficial para fotos/vídeos/arquivos.
abstract final class ChurchTelegramLauncher {
  ChurchTelegramLauncher._();

  /// Cliente Web oficial (embutido no módulo Chat).
  static const String kWebClientHome = 'https://web.telegram.org/a/';

  /// Converte link `t.me` / `tg://` para URL do Telegram Web (dentro do app).
  static String toWebClientUrl(String? urlOrHandle) {
    final raw = (urlOrHandle ?? '').trim();
    if (raw.isEmpty) return kWebClientHome;

    // Já é o cliente web.
    final lower = raw.toLowerCase();
    if (lower.startsWith('https://web.telegram.org') ||
        lower.startsWith('http://web.telegram.org')) {
      return raw;
    }

    final normalized = normalizeInviteOrGroupUrl(raw) ?? raw;
    final uri = Uri.tryParse(normalized);
    if (uri == null) return kWebClientHome;

    if (uri.scheme == 'tg') {
      return '$kWebClientHome#?tgaddr=${Uri.encodeComponent(normalized)}';
    }

    final path = uri.path;
    // Convite privado: t.me/+HASH  (HASH não é só telefone)
    if (path.startsWith('/+')) {
      final invite = path.substring(2).split('/').first;
      if (invite.isNotEmpty) {
        final onlyDigits = RegExp(r'^\d{10,15}$').hasMatch(invite);
        if (onlyDigits) {
          final tg = 'tg://resolve?phone=$invite';
          return '$kWebClientHome#?tgaddr=${Uri.encodeComponent(tg)}';
        }
        final tg = 'tg://join?invite=$invite';
        return '$kWebClientHome#?tgaddr=${Uri.encodeComponent(tg)}';
      }
    }
    // t.me/joinchat/HASH
    if (path.contains('joinchat/')) {
      final invite = path.split('joinchat/').last.split('/').first;
      if (invite.isNotEmpty) {
        final tg = 'tg://join?invite=$invite';
        return '$kWebClientHome#?tgaddr=${Uri.encodeComponent(tg)}';
      }
    }
    // Query start= / phone=
    final phone = uri.queryParameters['phone'];
    if (phone != null && phone.trim().isNotEmpty) {
      final tg = 'tg://resolve?phone=${phone.replaceAll(RegExp(r'\D'), '')}';
      return '$kWebClientHome#?tgaddr=${Uri.encodeComponent(tg)}';
    }

    // Canal/grupo público: t.me/username
    final user = path.replaceAll('/', '').trim();
    if (user.isNotEmpty &&
        !user.contains('+') &&
        RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(user)) {
      return '$kWebClientHome#$user';
    }

    // Fallback: tgaddr genérico
    if (normalized.startsWith('http')) {
      final tgFallback = 'tg://resolve?domain=${Uri.encodeComponent(user)}';
      if (user.isNotEmpty) {
        return '$kWebClientHome#?tgaddr=${Uri.encodeComponent(tgFallback)}';
      }
    }
    return kWebClientHome;
  }

  /// Normaliza convite/grupo: `t.me/...`, `telegram.me/...`, `tg://...`.
  static String? normalizeInviteOrGroupUrl(String? raw) {
    var s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    if (s.startsWith('@')) {
      final user = s.substring(1).trim();
      if (user.isEmpty) return null;
      return 'https://t.me/$user';
    }
    if (s.startsWith('tg://')) return s;
    if (!s.contains('://')) {
      if (s.toLowerCase().startsWith('t.me/') ||
          s.toLowerCase().startsWith('telegram.me/')) {
        s = 'https://$s';
      } else if (RegExp(r'^[a-zA-Z0-9_+-]+$').hasMatch(s)) {
        s = 'https://t.me/$s';
      } else {
        return null;
      }
    }
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host.contains('t.me') ||
        host.contains('telegram.me') ||
        host.contains('telegram.org') ||
        uri.scheme == 'tg') {
      return uri.toString();
    }
    return null;
  }

  /// Chat direto por telefone (Brasil) — resolve no Telegram Web / app.
  static String? dmUrlFromPhone(String? phoneRaw) {
    final digits = (phoneRaw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) return null;
    var full = digits;
    if (!full.startsWith('55') && full.length <= 11) {
      full = '55$full';
    }
    return 'tg://resolve?phone=$full';
  }

  static Uri? _preferAppUri(String httpsUrl) {
    final u = Uri.tryParse(httpsUrl);
    if (u == null) return null;
    final path = u.path;
    if (path.startsWith('/+')) {
      return Uri.parse('tg://resolve?phone=${path.substring(2)}');
    }
    if (path.startsWith('/joinchat/') || path.contains('+')) {
      // Convites privados: preferir https (app resolve).
      return null;
    }
    final user = path.replaceAll('/', '').trim();
    if (user.isNotEmpty && !user.contains('+') && !user.contains('joinchat')) {
      return Uri.parse('tg://resolve?domain=$user');
    }
    return null;
  }

  /// Abre Telegram. Mobile tenta app primeiro; Web usa https.
  static Future<bool> open(
    BuildContext context, {
    required String urlOrHandle,
    String? fallbackSnack,
  }) async {
    final normalized = normalizeInviteOrGroupUrl(urlOrHandle);
    if (normalized == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            fallbackSnack ??
                'Link do grupo inválido. Cole o link de convite completo.',
          ),
        );
      }
      return false;
    }

    try {
      if (!kIsWeb) {
        final appUri = _preferAppUri(normalized);
        if (appUri != null) {
          final okApp = await launchUrl(
            appUri,
            mode: LaunchMode.externalApplication,
          );
          if (okApp) return true;
        }
      }
      final web = Uri.parse(normalized);
      final ok = await launchUrl(
        web,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar(
            'Não foi possível abrir o Yahweh Chat. Tente de novo ou use o navegador.',
          ),
        );
      }
      return ok;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          ThemeCleanPremium.feedbackSnackBar('Erro ao abrir o Yahweh Chat: $e'),
        );
      }
      return false;
    }
  }

  static String? inviteFromDeptData(Map<String, dynamic>? data) {
    if (data == null) return null;
    for (final k in [
      'telegramInviteUrl',
      'telegramGroupUrl',
      'telegramLink',
      'telegramUrl',
      'linkTelegram',
      'telegram',
    ]) {
      final n = normalizeInviteOrGroupUrl(data[k]?.toString());
      if (n != null) return n;
    }
    return null;
  }
}
