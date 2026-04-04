import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:gestao_yahweh/jimsabores_frota/core/app_version.dart';
import 'version_check_service_stub.dart'
    if (dart.library.html) 'version_check_service_web.dart' as reload_impl;

/// Retorna a versão publicada no servidor (version.json), com cache-bust.
Future<String?> fetchServerVersion() async {
  try {
    final path = Uri.base.path;
    final base = path.endsWith('/') ? path : '$path/';
    final uri = Uri.parse('${base}version.json?b=${DateTime.now().millisecondsSinceEpoch}');
    final response = await http.get(uri).timeout(
      const Duration(seconds: 8),
      onTimeout: () => http.Response('', 408),
    );
    if (response.statusCode == 200 && response.body.isNotEmpty) {
      final json = jsonDecode(response.body) as Map<String, dynamic>?;
      final v = json?['version']?.toString().trim();
      return v != null && v.isNotEmpty ? v : null;
    }
  } catch (_) {}
  return null;
}

/// Retorna a versão do servidor se for diferente da atual (nova versão disponível). Null se igual ou falha.
Future<String?> getNewVersionIfAvailable() async {
  final serverVersion = await fetchServerVersion();
  if (serverVersion == null) return null;
  final current = kAppVersion.trim();
  if (serverVersion == current) return null;
  return serverVersion;
}

/// Aplica a atualização (reload com cache-bust). Só web.
Future<void> applyUpdate(String serverVersion) async {
  if (!kIsWeb) return;
  await reload_impl.reloadWithCacheBust(serverVersion);
}
