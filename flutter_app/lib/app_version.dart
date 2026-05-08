/// Single source of app version used everywhere.
/// [appVersion] + [appBuildNumber] must match pubspec `version: X.Y.Z+N`.
/// v11 baseline: web enabled, PIX/Card 10x, grace period, Mercado Pago.
/// 11.2.295: iOS Reader/SaaS — Remote Config `exibir_pagamento_ios`
/// (Apple Guideline 3.1.1) controla exibicao de checkout no iOS.
/// 11.2.295+1508: faixa flutuante «Login expresso» no login mobile
/// (Google silencioso → Apple iOS → Google UI), igual Controle Total app.
/// 11.2.295+1509: deploy de publicação (web + AAB Play + ZIP iOS).
const String appVersion = '11.2.295';
const String appBuildNumber = '1509';

/// Igual ao pubspec sem prefixo (ex.: 11.2.293+1447).
const String appVersionFull = '$appVersion+$appBuildNumber';

/// Labels for footer and installed-version texts.
const String appVersionLabel = 'v$appVersion+$appBuildNumber';


