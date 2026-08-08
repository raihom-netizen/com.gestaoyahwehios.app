import 'package:flutter/foundation.dart' show kIsWeb;

/// Timeouts canónicos — leituras do painel igreja (Web = Android = iOS em path).
abstract final class ChurchPanelReadTimeouts {
  ChurchPanelReadTimeouts._();

  /// Timeout por tentativa interna ([FirestoreReadResilience.getQuery]).
  static Duration get attempt =>
      kIsWeb ? const Duration(seconds: 9) : const Duration(seconds: 14);

  /// [FirestoreWebGuard.ensurePanelReadReady] — nunca bloquear UI além disto.
  static Duration get readReadyCap =>
      kIsWeb ? const Duration(seconds: 3) : const Duration(seconds: 6);

  /// Cap externo de uma leitura completa (UI / listCacheFirst / SWR).
  static Duration get queryCap =>
      kIsWeb ? const Duration(seconds: 16) : const Duration(seconds: 24);

  /// 1.º carregamento de módulo na Web — alinhado ao [queryCap] (sem esperar callable 32s).
  static Duration get webModuleFirstLoadCap =>
      kIsWeb ? const Duration(seconds: 16) : const Duration(seconds: 60);

  /// Pré-aquecimento em background (login / dashboard).
  static Duration get warmCap =>
      kIsWeb ? const Duration(seconds: 14) : const Duration(seconds: 18);

  /// Prefetch pós-login (não bloqueia UI) — cap curto para não enfileirar reads.
  static Duration get prefetchCap =>
      kIsWeb ? const Duration(seconds: 10) : const Duration(seconds: 16);

  /// Doc raiz da igreja (cadastro).
  static Duration get churchDocCap =>
      kIsWeb ? const Duration(seconds: 10) : const Duration(seconds: 25);

  /// Web: polling periódico em vez de `snapshots()` — paridade com mobile.
  ///
  /// ⚠️ CHURN DE TARGETS: no SDK JS cada `.get()` na Web abre+fecha um alvo do
  /// Watch stream. Com ~10-15 streams de módulos ativos, um intervalo curto (6s)
  /// gerava ~150 alvos/min → o contador de targetId disparava (1300+) e batia no
  /// `INTERNAL ASSERTION FAILED / WatchChangeAggregator` do SDK, derrubando o
  /// Financeiro e outros módulos. 45s corta o churn ~8x sem prejuízo real
  /// (gestão de igreja não precisa de tempo-real de segundos; mutações do próprio
  /// usuário já reemitem na hora via reload debounced pós-mutação).
  static Duration get webPollInterval =>
      kIsWeb ? const Duration(seconds: 45) : const Duration(seconds: 8);
}
