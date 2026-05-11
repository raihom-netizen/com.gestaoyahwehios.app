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
/// 11.2.295+1537: barra de atalhos mobile — Painel, Membros, Eventos, Avisos, Chat (menu
/// só pelo ícone no topo); cabeçalho azul com nome completo na saudação.
/// 11.2.295+1536: Login expresso — fase Google silenciosa sem spinner na faixa; só depois
/// `skipSilentPhase` + UI nativa (igual fluxo leve Controle Total). Mesmo padrão em
/// `ExpressRenewGatePage` nativo.
/// 11.2.295+1535: Configurações — secção destacada «Conta Google / e-mail», ajuda passo a passo e cartão separado
/// «Estado e licença da igreja»; diálogo de troca de conta menciona Apple.
/// 11.2.295+1534: modo offline — pré-aquecimento Firestore (membros, avisos, notícias/eventos, património, users)
/// ao abrir o painel; persistência + fila de escritas já existentes; faixa «sem conexão» inalterada.
/// 11.2.295+1533: Quill eventos/avisos — blindagem tela cinza (RepaintBoundary + doc); ListView do formulário
/// de evento com «arrastar fecha teclado» (igual mural).
/// 11.2.295+1532: login mobile — sem overlay Flutter durante picker Apple/Google (`onBeforeNativeOAuthUi`);
/// reconexão Google silenciosa sem spinner na faixa; entrada no painel mais rápida (cache de perfil).
/// 11.2.295+1531: menu lateral — «Chat - Igreja» na secção Comunicação (`forum_rounded`);
/// índice 24 incluído na grelha (antes não aparecia no drawer).
/// 11.2.295+1530: Chat — legenda opcional (`label`) na grelha da biblioteca de figurinhas;
/// campo de mensagem com autocorreção, sugestões e capitalização de frases.
/// 11.2.295+1529: Hub Chat — abas Conversas | Membros | Grupos (filtros por aba),
/// grupos premium + folha com membros do departamento e DM rápida.
/// 11.2.295+1528: Chat — painel unificado «Expressar» (Emojis + Figurinhas), recentes locais,
/// nome opcional ao importar figurinha; nova DM com filtro por nome.
/// 11.2.295+1527: Chat — figurinhas (logo da igreja + importar imagens, biblioteca `chat_stickers`),
/// tipo mensagem `sticker`, Storage/Regras + push «Figurinha».
/// 11.2.295+1526: Chat — paginação do histórico, responder/citar (`replyTo`), indicador «a digitar…»
/// (subcoleção `typing`), regras Firestore alinhadas.
/// 11.2.295+1525: Chat — apagar para mim / para todos; grupo só moderadores apagam para todos;
/// DM autor apaga para todos; ocultar conversa só DM; regras Firestore `hiddenForUids`.
/// 11.2.295+1524: Site divulgação + login — copy Super Premium e Chat Igreja (membros/departamentos);
/// Master «Mídias Divulgação» com nota alinhada.
/// 11.2.295+1523: Chat — líder do departamento, ADM, gestor e pastor podem remover mensagens
/// (DM e grupo); autor remove a sua; regras Firestore + long press na bolha.
/// 11.2.295+1522: Chat — presença offline visível (lista + novo contacto), recibos ✓✓ na DM,
/// picker de emojis, avatares de grupo com gradiente + ícone FA (igual departamentos).
/// 11.2.295+1521: Chat — gravar e enviar mensagem de voz; anexos (foto, vídeo, PDF/Office, áudio ficheiro).
/// 11.2.295+1520: Editor Quill em eventos/avisos — sem scroll aninhado no ListView (fix tela cinza iOS).
/// 11.2.295+1519: Chat hub — favoritos no topo (máx. 5), grupos e DM em ordem A–Z.
/// 11.2.295+1518: Chat — pesquisa (lista + mensagens), favoritos, silenciar conversa,
/// bloquear DM (`chat_member_prefs`), regras Firestore + FCM respeita mute/block por conversa.
/// 11.2.295+1517: Chat da igreja — visual Clean Premium (hub/thread), preferência
/// `pushChat` + silenciar no hub/thread/configurações, FCM + Cloud Function por mensagem.
const String appVersion = '11.2.295';
const String appBuildNumber = '1539';

/// 11.2.295+1539: deploy produção — tenant resolver (avisos/eventos/chat/módulos),
/// login biométrico (skip lock), bump build Play/iOS/Codemagic.

/// Igual ao pubspec sem prefixo (ex.: 11.2.293+1447).
const String appVersionFull = '$appVersion+$appBuildNumber';

/// Labels for footer and installed-version texts.
const String appVersionLabel = 'v$appVersion+$appBuildNumber';


