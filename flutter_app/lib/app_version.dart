/// Única fonte da versão do app. Usado em: app, web, painel ADM, igrejas, rodapé.
/// [appVersion] + [appBuildNumber] devem coincidir com `version:` em pubspec.yaml (X.Y.Z+N).
/// 11.0 = Versão 11 completa — Web autorizada, PIX/Cartão 10x, carência 3 dias, Mercado Pago.
const String appVersion = '11.2.293';
const String appBuildNumber = '1452';

/// Igual ao pubspec sem prefixo (ex.: 11.2.293+1447).
const String appVersionFull = '$appVersion+$appBuildNumber';

/// Rodapés e textos “versão instalada” (ex.: v11.2.293+1447).
const String appVersionLabel = 'v$appVersion+$appBuildNumber';
