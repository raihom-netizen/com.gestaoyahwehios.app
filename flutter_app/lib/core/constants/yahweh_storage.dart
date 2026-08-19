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

  /// URL pública imediata para mídia da igreja, sem ida à rede.
  ///
  /// Tudo sob `igrejas/` é de leitura pública nas regras do Storage
  /// (`allow read: if true`), por isso a URL `?alt=media` funciona **sem
  /// token** — verificado em produção (HTTP 200).
  ///
  /// Existe para matar a espera pelo `getDownloadURL` depois do upload: os
  /// bytes já estão no bucket e essa chamada custava até 5 s por ficheiro num
  /// caminho e até 16 s no outro (8 s × 2 tentativas). Num evento com 5 fotos
  /// e 1 vídeo dava quase um minuto e meio de espera à toa — era esta a
  /// lentidão sentida ao publicar avisos, eventos, comprovantes, património,
  /// logo da igreja e foto de perfil.
  static String? publicChurchMediaUrlOrNull(String storagePath) {
    final p = storagePath.trim().replaceAll('\\', '/').replaceFirst(
      RegExp(r'^/+'),
      '',
    );
    if (!p.startsWith('igrejas/')) return null;
    return downloadUrlForObjectPath(p);
  }

  /// URL HTTP de download direto (`?alt=media`) para um **caminho de objeto** no bucket.
  /// Útil para vídeos/imagens públicas (regras `read: if true`) — padrão usado no hero do EcoFire.
  static String downloadUrlForObjectPath(String storagePath) {
    var p = storagePath.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');
    final encoded = p.contains('%') ? p : Uri.encodeComponent(p);
    return 'https://firebasestorage.googleapis.com/v0/b/$bucket/o/$encoded?alt=media';
  }
}
