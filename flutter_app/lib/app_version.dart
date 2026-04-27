/// Single source of app version used everywhere.
/// [appVersion] + [appBuildNumber] must match pubspec `version: X.Y.Z+N`.
/// v11 baseline: web enabled, PIX/Card 10x, grace period, Mercado Pago.
const String appVersion = '11.2.294';
const String appBuildNumber = '1471';

/// Igual ao pubspec sem prefixo (ex.: 11.2.293+1447).
const String appVersionFull = '$appVersion+$appBuildNumber';

/// Labels for footer and installed-version texts.
const String appVersionLabel = 'v$appVersion+$appBuildNumber';


