import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Site público: mídia via HTTP / regras Storage — **sem** login anónimo.
///
/// O provedor Anonymous foi desligado no Firebase (só Gmail, Apple, e-mail/senha).
/// Visitantes do site não precisam de sessão Auth para ver conteúdo público.
class PublicSiteMediaAuth {
  PublicSiteMediaAuth._();

  /// No-op — compatível com chamadas existentes antes do upload/leitura de mídia.
  static Future<void> ensurePublicVisitorMediaAccess() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u != null && !u.isAnonymous) return;
    if (u != null && u.isAnonymous) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
  }

  static Future<void> ensureWebAnonymousForStorage() async {
    if (!kIsWeb) return;
    await ensurePublicVisitorMediaAccess();
  }
}
