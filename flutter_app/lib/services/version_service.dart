import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/app_version.dart';

import 'version_service_stub.dart' if (dart.library.html) 'version_service_web.dart' as _reload;

/// Resultado da checagem de versão (web e mobile).
class VersionResult {
  final bool outdated;
  final bool force;
  final String current;
  final String message;
  final String updateUrl;
  /// Firestore/rede indisponível na checagem — o app segue; [UpdateChecker] pode repetir.
  final bool skippedDueToError;
  const VersionResult({
    this.outdated = false,
    this.force = false,
    this.current = '5.0',
    this.message = '',
    this.updateUrl = '',
    this.skippedDueToError = false,
  });
}

/// Compara duas versões no formato "major.minor" ou "major.minor.patch".
/// Retorna: < 0 se current < required, 0 se iguais, > 0 se current > required.
int _compareVersions(String current, String required) {
  final c = _parseVersion(current);
  final r = _parseVersion(required);
  for (var i = 0; i < c.length || i < r.length; i++) {
    final cv = i < c.length ? c[i] : 0;
    final rv = i < r.length ? r[i] : 0;
    if (cv != rv) return cv.compareTo(rv);
  }
  return 0;
}

List<int> _parseVersion(String v) {
  return v
      .split(RegExp(r'[.\-+]'))
      .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();
}

/// Serviço único que busca a versão mínima no Firestore e compara com a atual.
/// Funciona em web e mobile; a checagem é automática ao abrir o app.
class VersionService {
  VersionService._();
  static final VersionService instance = VersionService._();

  static const _configPath = 'config/appVersion';

  /// Busca no Firestore (config/appVersion) a versão mínima e URLs de loja.
  /// Campos do doc: minVersion, forceUpdate (bool), message, storeUrlAndroid, storeUrlIos, webRefresh (bool).
  /// Leitura pública para funcionar antes do login.
  Future<VersionResult> check() async {
    try {
      final doc = await FirebaseFirestore.instance.doc(_configPath).get();
      if (!doc.exists || doc.data() == null) return const VersionResult();

      final data = doc.data()!;
      final minVersion = (data['minVersion'] ?? '').toString().trim();
      if (minVersion.isEmpty) return const VersionResult();

      final forceUpdate = data['forceUpdate'] == true;
      final message = (data['message'] ?? '').toString();
      final storeUrlAndroid = (data['storeUrlAndroid'] ?? '').toString().trim();
      final storeUrlIos = (data['storeUrlIos'] ?? '').toString().trim();
      final webRefresh = data['webRefresh'] == true;

      final outdated = _compareVersions(appVersion, minVersion) < 0;
      if (!outdated) return const VersionResult();

      String updateUrl = '';
      if (kIsWeb) {
        if (webRefresh) {
          updateUrl = Uri.base.origin;
          if (Uri.base.hasPort && Uri.base.port != 80 && Uri.base.port != 443) {
            updateUrl = '${Uri.base.origin}:${Uri.base.port}';
          }
        }
      } else {
        if (defaultTargetPlatform == TargetPlatform.android && storeUrlAndroid.isNotEmpty) {
          updateUrl = storeUrlAndroid;
        } else if (defaultTargetPlatform == TargetPlatform.iOS && storeUrlIos.isNotEmpty) {
          updateUrl = storeUrlIos;
        }
      }

      return VersionResult(
        outdated: true,
        force: forceUpdate,
        current: minVersion,
        message: message.isNotEmpty ? message : 'Uma nova versão ($minVersion) está disponível. Atualize para continuar.',
        updateUrl: updateUrl,
      );
    } catch (_) {
      return const VersionResult(skippedDueToError: true);
    }
  }

  /// Abre a URL de atualização (loja ou mesma origem no web para recarregar).
  Future<void> openUpdateUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (kIsWeb && (url == Uri.base.origin || url.startsWith(Uri.base.origin))) {
      _reload.reloadWeb();
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Para web: recarrega a página (útil quando forceUpdate e updateUrl é a própria origem).
  static void reloadWeb() {
    if (kIsWeb) _reload.reloadWeb();
  }
}
