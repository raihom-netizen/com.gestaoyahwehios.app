import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:gestao_yahweh/core/app_constants.dart';

import 'version_service_stub.dart' if (dart.library.html) 'version_service_web.dart' as _reload;

/// URL padrão da app na Google Play — [AppConstants.gestaoYahwehPlayStoreUrl].
const String kDefaultPlayStoreUrl = AppConstants.gestaoYahwehPlayStoreUrl;

/// Dados para o banner “nova versão” no painel da igreja (Android).
class PanelUpdateHint {
  final String targetVersion;
  final String message;
  final String storeUrl;

  const PanelUpdateHint({
    required this.targetVersion,
    required this.message,
    required this.storeUrl,
  });
}

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

/// Mensagem padrão quando `config/appVersion` não define [message].
String kDefaultVersionUpdateMessage(String targetLabel) {
  return 'Nova versão disponível ($targetLabel). Toque em Atualizar para instalar '
      'o build mais recente — melhorias, correções e experiência premium.';
}

/// `true` se a versão instalada está abaixo de [minVersion] ou do [minBuildNumber] (mesmo X.Y.Z).
bool isAppBelowRequiredVersion({
  required String minVersion,
  int? minBuildNumber,
}) {
  final min = minVersion.trim();
  if (min.isEmpty) return false;
  final cmp = _compareVersions(appVersion, min);
  if (cmp < 0) return true;
  if (cmp > 0) return false;
  final minB = minBuildNumber ?? 0;
  if (minB <= 0) return false;
  final currentB = int.tryParse(appBuildNumber) ?? 0;
  return currentB < minB;
}

String _targetVersionLabel(String minVersion, int? minBuildNumber) {
  final b = minBuildNumber ?? 0;
  if (b > 0) return '$minVersion+$b';
  return minVersion;
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

  /// Interpreta [data] de `config/appVersion` para o banner do painel.
  /// Usa `latestVersion` se existir; senão `minVersion`. Só retorna hint se o app estiver mais antigo.
  /// [storeUrlAndroid] vazio → [kDefaultPlayStoreUrl].
  PanelUpdateHint? panelUpdateHintFromConfigData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final minVer = (data['minVersion'] ?? '').toString().trim();
    final minBuildRaw = data['minBuildNumber'];
    final minBuild = minBuildRaw is num
        ? minBuildRaw.toInt()
        : int.tryParse('$minBuildRaw') ?? 0;

    var target = (data['latestVersion'] ?? '').toString().trim();
    if (target.isEmpty) {
      target = _targetVersionLabel(minVer, minBuild > 0 ? minBuild : null);
    }
    if (minVer.isEmpty && target.isEmpty) return null;

    var compareVer = minVer;
    var compareBuild = minBuild > 0 ? minBuild : null;
    if (compareVer.isEmpty && target.contains('+')) {
      final parts = target.split('+');
      compareVer = parts.first.trim();
      if (parts.length > 1) {
        compareBuild = int.tryParse(parts[1].trim());
      }
    } else if (compareVer.isEmpty) {
      compareVer = target;
    }
    if (!isAppBelowRequiredVersion(
      minVersion: compareVer,
      minBuildNumber: compareBuild,
    )) {
      return null;
    }

    final androidUrl = (data['storeUrlAndroid'] ?? '').toString().trim();
    final iosUrl = (data['storeUrlIos'] ?? '').toString().trim();
    String storeUrl;
    if (kIsWeb) {
      storeUrl = androidUrl.isNotEmpty ? androidUrl : kDefaultPlayStoreUrl;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      storeUrl = iosUrl.isNotEmpty
          ? iosUrl
          : AppConstants.gestaoYahwehTestFlightUrl;
    } else {
      storeUrl = androidUrl.isNotEmpty ? androidUrl : kDefaultPlayStoreUrl;
    }

    var msg = (data['panelUpdateMessage'] ?? data['message'] ?? '').toString().trim();
    if (msg.isEmpty) {
      msg =
          'Está disponível uma nova versão ($target). Atualize na loja para melhorias e correções.';
    }
    return PanelUpdateHint(
      targetVersion: target,
      message: msg,
      storeUrl: storeUrl,
    );
  }

  /// Busca no Firestore (config/appVersion) a versão mínima e URLs de loja.
  /// Campos do doc: minVersion, message, storeUrlAndroid, storeUrlIos, webRefresh (bool).
  /// Campos: minVersion, minBuildNumber, forceUpdate, message, storeUrlAndroid, storeUrlIos, webRefresh.
  /// Leitura pública para funcionar antes do login.
  Future<VersionResult> check() async {
    try {
      final doc = await FirebaseFirestore.instance.doc(_configPath).get();
      if (!doc.exists || doc.data() == null) return const VersionResult();

      final data = doc.data()!;
      final minVersion = (data['minVersion'] ?? '').toString().trim();
      if (minVersion.isEmpty) return const VersionResult();

      final minBuildRaw = data['minBuildNumber'];
      final minBuildNumber = minBuildRaw is num
          ? minBuildRaw.toInt()
          : int.tryParse('$minBuildRaw');
      final forceUpdate = data['forceUpdate'] == true;
      final message = (data['message'] ?? '').toString();
      final storeUrlAndroid = (data['storeUrlAndroid'] ?? '').toString().trim();
      final storeUrlIos = (data['storeUrlIos'] ?? '').toString().trim();
      final webRefresh = data['webRefresh'] == true;

      final outdated = isAppBelowRequiredVersion(
        minVersion: minVersion,
        minBuildNumber: minBuildNumber,
      );
      if (!outdated) return const VersionResult();

      final targetLabel = _targetVersionLabel(
        minVersion,
        minBuildNumber,
      );

      String updateUrl = '';
      if (kIsWeb) {
        if (webRefresh) {
          updateUrl = Uri.base.origin;
          if (Uri.base.hasPort && Uri.base.port != 80 && Uri.base.port != 443) {
            updateUrl = '${Uri.base.origin}:${Uri.base.port}';
          }
        }
      } else {
        if (defaultTargetPlatform == TargetPlatform.android) {
          updateUrl =
              storeUrlAndroid.isNotEmpty ? storeUrlAndroid : kDefaultPlayStoreUrl;
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          updateUrl = storeUrlIos.isNotEmpty
              ? storeUrlIos
              : AppConstants.gestaoYahwehTestFlightUrl;
        }
      }

      return VersionResult(
        outdated: true,
        force: forceUpdate,
        current: targetLabel,
        message: message.trim().isNotEmpty
            ? message.trim()
            : kDefaultVersionUpdateMessage(targetLabel),
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
