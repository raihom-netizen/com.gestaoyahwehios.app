/// Single source of app version used everywhere.
/// [appVersion] + [appBuildNumber] must match pubspec `version: X.Y.Z+N`.
/// v11 baseline: web enabled, PIX/Card 10x, grace period, Mercado Pago.
/// 11.2.295: iOS Reader/SaaS — Remote Config `exibir_pagamento_ios`
/// (Apple Guideline 3.1.1) controla exibicao de checkout no iOS.
/// 11.2.295+1508: faixa flutuante «Login expresso» no login mobile
/// (Google silencioso → Apple iOS → Google UI), igual Controle Total app.
/// 11.2.295+1509: deploy de publicação (web + AAB Play + ZIP iOS).
/// 11.2.295+1510: «Atualizar plano expresso» — rota web `/atualizar-plano`
/// com login simples (identifica igreja), header com plano atual + vencimento
/// e checkout Mercado Pago direto, sem passar pelo painel.
/// 11.2.295+1511: hardening Apple App Store — `IosPaymentUnavailableView` sem
/// preços (CTA topo + rodapé), `_buildPlanosResumoCard` esconde preços em iOS
/// native, gate iOS no `onGenerateRoute` para `/`, `/planos`, `/pagamento`,
/// botões de doação e «Adquirir Sistema» abrem Safari externo (Guideline
/// 3.2.1(viii)), header «Super Premium» na rota web `/atualizar-plano` com
/// botão Login Expresso (Google popup/redirect), Info.plist com
/// `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`,
/// `NSContactsUsageDescription` e `LSApplicationQueriesSchemes`.
/// 11.2.295+1512: revisão profunda iOS App Store —
///   • `Runner.entitlements`: re-adicionado Sign in with Apple (Guideline
///     4.8) + `aps-environment=production` para Firebase Messaging.
///   • `PrivacyInfo.xcprivacy` (obrigatório desde maio/2024) registrado
///     no `project.pbxproj` (Tracking=false, Required Reason APIs).
///   • `_showCheckoutPreviewModal` em `church_donations_page` e
///     `church_public_donation_sheet`: em iOS native abre Safari externo
///     em vez de WebView Mercado Pago embedded (3.2.1(viii)).
///   • Banner de trial expirado / trial ativo no `dashboard_page` com
///     copy neutralizada para iOS (sem termo «pagamento»).
/// 11.2.295+1513: deploy de publicação (regras + functions + web + AAB
/// Play + ZIP iOS + push Codemagic). Documentos de migração em
/// `docs/migracoes/` atualizados com todo o hardening iOS para replicar
/// nos projetos Controle Total e Moova Super Premium.
/// 11.2.295+1514: limpeza de lints (`withOpacity` → `.withValues(alpha:)`
/// em `renew_plan_page.dart`, remoção de `_watchingTenantId` não usado,
/// `curly_braces_in_flow_control_structures` em `main.dart`,
/// `messenger` capturado antes do await async no PIX copy). Otimização
/// do `deploy_completo.ps1`: `flutter clean+pub get` único na etapa 0,
/// sub-scripts com `-SkipPubGet`, skip automático de Cloud Functions
/// quando `/functions` não mudou (use `-ForceFunctions` para forçar).
/// 11.2.295+1515: fix do splatting `$args` → `$invokeArgs` (hashtable)
/// no `deploy_completo.ps1` — `+1514` criou pastas `-CopyTo/` poluindo
/// o repo; este build remove os AAB/ZIP do Git, adiciona ao `.gitignore`
/// e re-publica web/AAB Play/ZIP iOS no destino correto `D:\Temporarios`.
/// 11.2.295+1516: workaround temporário para destravar build iOS na
/// Codemagic — `aps-environment` removido do `Runner.entitlements`
/// (provisioning profile actual não tem Push Notifications). Sign In
/// with Apple mantido (Guideline 4.8 obrigatório). Push iOS volta
/// quando profile for regenerado em developer.apple.com com a
/// capability de Push Notifications activa.
/// 11.2.295+1519: Chat hub — favoritos no topo (máx. 5), grupos e DM em ordem A–Z.
/// 11.2.295+1518: Chat — pesquisa (lista + mensagens), favoritos, silenciar conversa,
/// bloquear DM (`chat_member_prefs`), regras Firestore + FCM respeita mute/block por conversa.
/// 11.2.295+1517: Chat da igreja — visual Clean Premium (hub/thread), preferência
/// `pushChat` + silenciar no hub/thread/configurações, FCM + Cloud Function por mensagem.
const String appVersion = '11.2.295';
const String appBuildNumber = '1519';

/// Igual ao pubspec sem prefixo (ex.: 11.2.293+1447).
const String appVersionFull = '$appVersion+$appBuildNumber';

/// Labels for footer and installed-version texts.
const String appVersionLabel = 'v$appVersion+$appBuildNumber';


