import 'package:flutter/foundation.dart' show kIsWeb;

/// Timeouts canónicos — leituras do painel igreja (Web = Android = iOS em path).
abstract final class ChurchPanelReadTimeouts {
  ChurchPanelReadTimeouts._();

  /// Timeout por tentativa interna ([FirestoreReadResilience.getQuery]).
  static Duration get attempt =>
      kIsWeb ? const Duration(seconds: 8) : const Duration(seconds: 16);

  /// [FirestoreWebGuard.ensurePanelReadReady] — nunca bloquear UI além disto.
  static Duration get readReadyCap =>
      kIsWeb ? const Duration(seconds: 3) : const Duration(seconds: 6);

  /// Cap externo de uma leitura completa (UI / listCacheFirst / SWR).
  static Duration get queryCap =>
      kIsWeb ? const Duration(seconds: 14) : const Duration(seconds: 28);

  /// 1.º carregamento de módulo na Web — alinhado ao [queryCap] (sem esperar callable 32s).
  static Duration get webModuleFirstLoadCap =>
      kIsWeb ? const Duration(seconds: 14) : const Duration(seconds: 90);

  /// Pré-aquecimento em background (login / dashboard).
  static Duration get warmCap =>
      kIsWeb ? const Duration(seconds: 22) : const Duration(seconds: 22);

  /// Prefetch pós-login (não bloqueia UI) — cap curto para não enfileirar reads.
  static Duration get prefetchCap =>
      kIsWeb ? const Duration(seconds: 16) : const Duration(seconds: 22);

  /// Doc raiz da igreja (cadastro).
  static Duration get churchDocCap =>
      kIsWeb ? const Duration(seconds: 14) : const Duration(seconds: 40);

  /// Web: polling periódico em vez de `snapshots()` — paridade com mobile.
  static Duration get webPollInterval =>
      kIsWeb ? const Duration(seconds: 12) : const Duration(seconds: 8);
}
