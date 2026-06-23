import 'package:flutter/foundation.dart' show kIsWeb;

/// Timeouts canónicos — leituras do painel igreja (Web = Android = iOS em path).
abstract final class ChurchPanelReadTimeouts {
  ChurchPanelReadTimeouts._();

  /// Timeout por tentativa interna ([FirestoreReadResilience.getQuery]).
  static Duration get attempt =>
      kIsWeb ? const Duration(seconds: 24) : const Duration(seconds: 16);

  /// Cap externo de uma leitura completa (UI / listCacheFirst / SWR).
  static Duration get queryCap =>
      kIsWeb ? const Duration(seconds: 14) : const Duration(seconds: 28);

  /// Pré-aquecimento em background (login / dashboard).
  static Duration get warmCap =>
      kIsWeb ? const Duration(seconds: 60) : const Duration(seconds: 22);

  /// Prefetch completo pós-login (não bloqueia UI).
  static Duration get prefetchCap =>
      kIsWeb ? const Duration(seconds: 100) : const Duration(seconds: 50);

  /// Doc raiz da igreja (cadastro).
  static Duration get churchDocCap =>
      kIsWeb ? const Duration(seconds: 100) : const Duration(seconds: 40);
}
