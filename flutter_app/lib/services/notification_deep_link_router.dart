import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:gestao_yahweh/services/church_panel_navigation_bridge.dart';

/// Roteador de deep links vindos de notificações push (FCM) ou de
/// Android App Links / iOS Universal Links.
///
/// Formatos suportados:
///   https://gestaoyahweh.com.br/igreja/{tenantId}/chat/{threadId}
///   https://gestaoyahweh.com.br/igreja/{tenantId}/evento/{eventoId}
///   https://gestaoyahweh.com.br/igreja/{tenantId}/membro/{memberId}
///   https://gestaoyahweh.com.br/igreja/{tenantId}/aprovacoes?memberId={id}
///   https://gestaoyahweh.com.br/igreja/{tenantId}/aniversariantes
///   gestaoyahweh://igreja/{tenantId}/...
abstract final class NotificationDeepLinkRouter {
  NotificationDeepLinkRouter._();

  static final _pathRe = RegExp(
    r'^/igreja/([^/]+)(?:/(chat|evento|membro|aprovacoes|aniversariantes)(?:/([^/?#]+))?)?',
    caseSensitive: false,
  );

  /// Tenta rotear uma URL de notificação. Retorna `true` se houve match.
  static bool route(String? rawUrl) {
    final url = _normalize(rawUrl);
    if (url == null) return false;

    final path = _extractPath(url);
    if (path == null || path.isEmpty) return false;

    final m = _pathRe.firstMatch(path);
    if (m == null) return false;

    final tenantId = m.group(1)?.trim() ?? '';
    final screen = (m.group(2) ?? '').trim().toLowerCase();
    final resourceId = (m.group(3) ?? '').trim();
    final query = _parseQuery(url);

    if (tenantId.isEmpty) return false;

    switch (screen) {
      case 'chat':
        // Módulo Yahweh Chat removido — links antigos de chat caem no Painel.
        ChurchPanelNavigationBridge.instance
            .requestNavigateToShellIndex(kChurchShellIndexPainel);
        return true;
      case 'evento':
        final eventoId = resourceId.isNotEmpty ? resourceId : query['eventoId'];
        if (eventoId != null && eventoId.isNotEmpty) {
          ChurchPanelNavigationBridge.instance.requestOpenEventDocId(eventoId);
        } else {
          ChurchPanelNavigationBridge.instance
              .requestNavigateToShellIndex(kChurchShellIndexEvents);
        }
        return true;
      case 'membro':
        final memberId = resourceId.isNotEmpty ? resourceId : query['memberId'];
        if (memberId != null && memberId.isNotEmpty) {
          ChurchPanelNavigationBridge.instance.requestOpenMemberDocId(memberId);
        } else {
          ChurchPanelNavigationBridge.instance
              .requestNavigateToShellIndex(kChurchShellIndexMembers);
        }
        return true;
      case 'aprovacoes':
        final memberId = query['memberId'];
        if (memberId != null && memberId.isNotEmpty) {
          ChurchPanelNavigationBridge.instance.requestOpenMemberDocId(
            memberId,
            publicSignup: true,
          );
        } else {
          ChurchPanelNavigationBridge.instance
              .requestNavigateToShellIndex(kChurchShellIndexAprovacoes);
        }
        return true;
      case 'aniversariantes':
        ChurchPanelNavigationBridge.instance
            .requestNavigateToShellIndex(kChurchShellIndexPainel);
        return true;
      default:
        return false;
    }
  }

  static String? _normalize(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;

    // Custom scheme
    if (s.toLowerCase().startsWith('gestaoyahweh://')) {
      return s;
    }

    // HTTP(S)
    if (!s.toLowerCase().startsWith('http://') &&
        !s.toLowerCase().startsWith('https://')) {
      if (s.startsWith('//')) {
        s = 'https:$s';
      } else {
        s = 'https://$s';
      }
    }
    return s;
  }

  static String? _extractPath(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.path;
    } catch (e) {
      debugPrint('NotificationDeepLinkRouter: invalid URL $url — $e');
      return null;
    }
  }

  static Map<String, String> _parseQuery(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.queryParameters;
    } catch (e) {
      return {};
    }
  }
}
