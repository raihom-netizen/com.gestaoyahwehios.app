import 'package:gestao_yahweh/firebase_options.dart';

/// Configuração central do Firebase Storage — **mesmo conceito do EcoFire** (`EcoFireStorage`).
/// Uma única fonte de bucket e URLs públicas `alt=media` evita fotos/vídeos quebrados por host errado.
class YahwehStorage {
  YahwehStorage._();

  /// Bucket do projeto (ex.: `gestaoyahweh-21e23.firebasestorage.app`).
  static String get bucket {
    try {
      final b = DefaultFirebaseOptions.web.storageBucket;
      if (b != null && b.isNotEmpty) return b;
    } catch (_) {}
    return 'gestaoyahweh-21e23.firebasestorage.app';
  }

  /// URL HTTP de download direto (`?alt=media`) para um **caminho de objeto** no bucket.
  /// Útil para vídeos/imagens públicas (regras `read: if true`) — padrão usado no hero do EcoFire.
  static String downloadUrlForObjectPath(String storagePath) {
    var p = storagePath.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    final encoded = p.contains('%') ? p : Uri.encodeComponent(p);
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded?alt=media';
  }
}
