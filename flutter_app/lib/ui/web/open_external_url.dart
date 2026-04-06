import 'open_external_url_stub.dart'
    if (dart.library.html) 'open_external_url_web.dart' as impl;

/// Abre [uri] no navegador/app externo. Na web usa nova aba e fallback [window.open]
/// quando `url_launcher` retorna false (comum em SPA).
Future<bool> openExternalApplicationUrl(Uri uri) =>
    impl.openExternalApplicationUrl(uri);
