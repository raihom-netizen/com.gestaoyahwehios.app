import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:gestao_yahweh/app_version.dart';

import 'auto_version_loader_stub.dart'
    if (dart.library.html) 'auto_version_loader_web.dart' as _reload;

/// Compara versões "a.b.c" ou "a.b.c+x". Retorna > 0 se server > current.
int _compareVersions(String server, String current) {
  final s = _parseVersion(server);
  final c = _parseVersion(current);
  for (var i = 0; i < s.length || i < c.length; i++) {
    final sv = i < s.length ? s[i] : 0;
    final cv = i < c.length ? c[i] : 0;
    if (sv != cv) return sv.compareTo(cv);
  }
  return 0;
}

List<int> _parseVersion(String v) {
  return v
      .split(RegExp(r'[.\-+]'))
      .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}

/// Verifica se há nova versão no servidor (version.json) e recarrega a página
/// apenas quando a versão do servidor for MAIOR que a atual (evita piscar/reload por version.json desatualizado).
Future<void> checkAndReloadIfNewVersion() async {
  if (!kIsWeb) return;
  try {
    final uri = Uri.parse('${Uri.base.origin}/version.json?t=${DateTime.now().millisecondsSinceEpoch}');
    final res = await http.get(uri).timeout(const Duration(seconds: 5));
    final text = res.body;
    String? serverVersion;
    try {
      final map = _jsonDecode(text);
      final sv = map['version'];
      final sb = map['build_number'];
      if (sv != null &&
          sv.isNotEmpty &&
          sb != null &&
          sb.isNotEmpty) {
        serverVersion = '$sv+$sb';
      } else {
        serverVersion = (sv ?? sb)?.trim();
      }
    } catch (_) {}
    if (serverVersion == null || serverVersion.isEmpty) return;
    final current = appVersionFull.trim();
    if (current.isEmpty) return;
    // Só recarrega se o servidor tiver versão MAIS NOVA (evita reload quando version.json está atrás)
    if (_compareVersions(serverVersion, current) > 0) {
      _reload.reloadToNewVersion();
    }
  } catch (_) {}
}

Map<String, String?> _jsonDecode(String text) {
  final vMatch = RegExp(r'"version"\s*:\s*"([^"]*)"').firstMatch(text);
  final bMatch = RegExp(r'"build_number"\s*:\s*"([^"]*)"').firstMatch(text);
  return <String, String?>{
    'version': vMatch?.group(1),
    'build_number': bMatch?.group(1),
  };
}
