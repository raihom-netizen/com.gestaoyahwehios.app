import 'package:flutter/foundation.dart';
import 'package:gestao_yahweh/app_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// No iOS (Codemagic), o [CFBundleVersion] pode ser um número grande (ASC + timestamp),
/// enquanto o controlo de «forçar atualização» no Firestore usa o `+N` de [appBuildNumber].
const int kIosAscStyleBuildThreshold = 500000;

/// `true` quando o build nativo parece número da App Store Connect, não o `+N` lógico.
bool isIosAscStyleBuildNumber(int n) => n >= kIosAscStyleBuildThreshold;

/// Build usado na comparação com `config/appVersion.minBuildNumber` (+N partilhado Android/iOS).
Future<int> resolveInstalledBuildForUpdateCheck() async {
  final logical = int.tryParse(appBuildNumber) ?? 0;
  if (kIsWeb) return logical;
  try {
    final info = await PackageInfo.fromPlatform();
    final platform = int.tryParse(info.buildNumber) ?? 0;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      if (isIosAscStyleBuildNumber(platform)) return logical;
      return platform > logical ? platform : logical;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return platform > 0 ? platform : logical;
    }
    return platform > 0 ? platform : logical;
  } catch (_) {
    return logical;
  }
}

/// Versão de marketing instalada (CFBundleShortVersionString / versionName).
Future<String> resolveInstalledMarketingVersionForUpdateCheck() async {
  if (kIsWeb) return appVersion;
  try {
    final info = await PackageInfo.fromPlatform();
    final v = info.version.trim();
    if (v.isNotEmpty) return v;
  } catch (_) {}
  return appVersion;
}

/// Rótulo para diálogos (mostra +N lógico e, no iOS, o número ASC se for diferente).
Future<String> installedBuildLabelForUi() async {
  final logical = appBuildNumber;
  if (kIsWeb) return logical;
  try {
    final info = await PackageInfo.fromPlatform();
    final platform = info.buildNumber.trim();
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        platform.isNotEmpty &&
        platform != logical &&
        isIosAscStyleBuildNumber(int.tryParse(platform) ?? 0)) {
      return '$logical (App Store $platform)';
    }
    if (platform.isNotEmpty && platform != logical) {
      return '$logical (nativo $platform)';
    }
  } catch (_) {}
  return logical;
}
