import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Regras de arranque para **desktop nativo** (Windows/Linux/macOS).
///
/// ## Porquê
///
/// No desktop o Firestore é o SDK **C++**, e cada operação deixa threads para
/// trás. Medido no Windows (2026-08-18), com o app parado na tela de carregar:
///
/// ```
///  5s ...  137 threads
/// 20s ...  164 threads
/// 40s ...  258 threads   ← 181 delas em ExecutionDelay (a dormir)
/// CPU  ...  ~0,02s por 5s   → não é lentidão, é bloqueio
/// ```
///
/// A thread de plataforma ficava presa e a janela nunca pintava — tela branca
/// com «Não está respondendo» —, embora o lado Dart terminasse todos os
/// módulos com SUCCESS. Ou seja: o Dart estava bem; quem afogava era a camada
/// nativa, alimentada pela rajada de leituras do arranque.
///
/// ## O que fazemos
///
/// No desktop o arranque passa a fazer o mínimo: sem warmup de coleções e sem
/// o flush de filas do cold start. Cada tela continua a carregar o que precisa
/// quando é aberta — o utilizador não perde nada, só deixa de haver ~20
/// consultas simultâneas antes de a janela existir.
///
/// Web e mobile não são afetados: lá o warmup ajuda e não há este custo.
abstract final class YahwehDesktopMode {
  YahwehDesktopMode._();

  /// Desktop **nativo** — não confundir com largura de janela (um tablet
  /// deitado também é «desktop» para efeitos de layout).
  static bool get isDesktopNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Pré-carregar coleções no arranque? Não no desktop.
  static bool get allowStartupWarmup => !isDesktopNative;

  /// Drenar filas offline logo no arranque? Não no desktop — corre quando o
  /// utilizador publica algo, ou ao voltar a ficar online.
  static bool get allowColdStartFlush => !isDesktopNative;
}
