/// Carrega futures em paralelo sem que um erro derrubar os demais.
abstract final class IndependentFutures {
  IndependentFutures._();

  /// Par de resultados — `null` quando a respectiva future falhou.
  static Future<(T1?, T2?)> pair<T1, T2>(
    Future<T1> first,
    Future<T2> second,
  ) async {
    T1? a;
    T2? b;
    await Future.wait([
      () async {
        try {
          a = await first;
        } catch (_) {}
      }(),
      () async {
        try {
          b = await second;
        } catch (_) {}
      }(),
    ]);
    return (a, b);
  }
}
