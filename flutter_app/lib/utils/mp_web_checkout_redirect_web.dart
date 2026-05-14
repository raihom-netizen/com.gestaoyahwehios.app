// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/foundation.dart' show kIsWeb;

/// iPhone/iPad/iPod no browser: iframe do Mercado Pago falha com frequência;
/// o fluxo fiável é o checkout oficial no **mesmo separador**, com `back_url`
/// a voltar para `/atualizar-plano`.
bool get mpWebCheckoutPrefersSameTabRedirect {
  if (!kIsWeb) return false;
  final ua = html.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod');
}

void mpWebRedirectSameTab(String url) {
  final t = url.trim();
  if (t.isEmpty) return;
  html.window.location.assign(t);
}
