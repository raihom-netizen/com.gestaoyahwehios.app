import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Site público (Flutter Web): visitantes sem login precisam de uma sessão Firebase
/// para o SDK do Storage (`putData` / `getData` / `getDownloadURL`) carregar e enviar
/// logo, fotos e vídeos de forma estável. Sem isso, o pipeline cai em CORS/`Image.network` e quebra.
///
/// No Console Firebase, habilite **Authentication → Sign-in method → Anonymous**
/// (obrigatório: site da igreja, cadastro público de membro, mural e vídeo institucional na web).
class PublicSiteMediaAuth {
  PublicSiteMediaAuth._();

  static Future<void>? _ongoing;

  /// Idempotente; seguro chamar antes de cada download de mídia na web.
  static Future<void> ensureWebAnonymousForStorage() async {
    if (!kIsWeb) return;
    final u = FirebaseAuth.instance.currentUser;
    if (u != null && !u.isAnonymous) return;
    if (u != null && u.isAnonymous) return;

    if (_ongoing != null) {
      await _ongoing;
      return;
    }
    _ongoing = _signInAnonymously();
    try {
      await _ongoing;
    } finally {
      _ongoing = null;
    }
  }

  static Future<void> _signInAnonymously() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 10));
        return;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }
    // Provedor anônimo desligado ou falha de rede: Storage público ainda pode responder via HTTP.
  }
}
