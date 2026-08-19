import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Plataformas onde o Firestore é acedido por **REST**, não pelo SDK.
///
/// ## Web
///
/// O SDK JS 12.x estoura `INTERNAL ASSERTION FAILED` no `WatchChangeAggregator`
/// e o cliente fica envenenado — todas as leituras e escritas seguintes falham
/// em silêncio. O canal REST não passa por esse agregador.
///
/// ## Desktop nativo — mesmo canal, outro motivo
///
/// No Windows/Linux/macOS o Firestore é o SDK **C++**, linkado estaticamente
/// dentro do executável (há `cloud_firestore_plugin.pdb` entre os plugins, e o
/// crash aparece como sendo «no exe»). Medições no Windows, 2026-08-18:
///
/// ```
/// listeners ao vivo ligados   →  303 threads aos 5s, janela nunca pinta
/// listeners desligados        →   16 threads, responde... e crasha aos 10s
///                                 (0xc0000005 em gestao_yahweh.exe+0x78f814)
/// ```
///
/// Desligar os listeners resolveu o congelamento mas o SDK C++ continuava no
/// caminho de leitura e escrita, e continuava a rebentar. Usando REST ele sai
/// desse caminho: sem threads de watch, sem o código que crasha.
///
/// Foram testadas e **descartadas** as hipóteses de warmup em rajada, FCM sem
/// implementação e ffmpeg/OpenMP — nenhuma explicava a contagem de threads.
///
/// ## Mobile
///
/// Android e iOS continuam no SDK nativo: os SDKs Java/ObjC são estáveis, têm
/// cache offline próprio e não têm nenhum destes problemas.
abstract final class YahwehRestFirst {
  YahwehRestFirst._();

  /// `true` quando as leituras/escritas devem ir por REST em vez do SDK.
  static bool get prefer =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Desktop nativo — usado onde o comportamento difere da web (ex.: a web tem
  /// semáforo de leituras e guardas de sessão que o desktop não precisa).
  static bool get isDesktopNative => !kIsWeb && prefer;
}
