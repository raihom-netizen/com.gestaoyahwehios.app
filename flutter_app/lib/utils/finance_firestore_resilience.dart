/// Repete operações Firestore após falha de rede — sem `getIdToken(true)` (quota Auth).
Future<T> financeFirestoreOpWithRetry<T>(
  Future<T> Function() op, {
  int maxAttempts = 3,
}) async {
  Object? lastError;
  for (var i = 0; i < maxAttempts; i++) {
    try {
      return await op();
    } catch (e) {
      lastError = e;
      if (i >= maxAttempts - 1) break;
      await Future<void>.delayed(Duration(milliseconds: 320 + i * 280));
    }
  }
  throw lastError!;
}
