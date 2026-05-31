import 'package:gestao_yahweh/core/firebase_bootstrap.dart';

/// Repete operações Firestore após falha (rede/token) — reduz ecrã de «erro de conexão»
/// em [Future.wait] no resumo financeiro.
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
      await Future<void>.delayed(Duration(milliseconds: 240 + i * 200));
      try {
        await firebaseDefaultAuth.currentUser?.getIdToken(true);
      } catch (_) {}
    }
  }
  throw lastError!;
}
