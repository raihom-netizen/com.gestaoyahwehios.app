/// Single source of app version used everywhere.
/// 11.2.295+1601: Deploy completo produção (regras, functions, índices, web, AAB, push Codemagic).
/// 11.2.295+1600: Membros — lista instantânea via `_panel_cache/members_directory`
/// (sem skeletons falsos; fotos progressivas); aba Painel & números com cache;
/// dashboard igreja — líderes/corpo administrativo do cache sem esperar 1,6s.
/// 11.2.295+1599: Módulo Eventos — publicação instantânea (Firestore primeiro, fotos em
/// segundo plano; push FCM ao concluir mídia; vídeo não bloqueia Publicar).
/// 11.2.295+1598: Mural avisos/eventos — publicação instantânea (Firestore primeiro, fotos em
/// segundo plano; upload direto sem fila offline; push FCM ao concluir mídia).
/// 11.2.295+1597: Chat — envio de foto/vídeo/áudio instantâneo (stub Firestore + upload paralelo,
/// sem fila offline; compressão de vídeo em background; regras patch mediaUrl).
/// 11.2.295+1596: Chat — lista Conversas definitiva (merge query + repair cliente/servidor,
/// lastMessageAt a partir das mensagens, sync ao abrir o hub).
/// 11.2.295+1595: deploy completo — chat conversas estáveis (regras + repair DM threads),
/// mídia Storage nativo, cache painel, reparo sessão membros.
/// 11.2.295+1594: iOS login/planos — sem checkout in-app; cadastro e licença só no site (3.1.1).
/// 11.2.295+1593: App Store 3.1.1 — iOS sem cadastro de igreja no app; só link web (Safari).
/// 11.2.295+1592: deploy completo — web, AAB Play, ZIP iOS Codemagic (push).
/// 11.2.295+1591: Play Store — remove READ_MEDIA_*; Photo Picker (image_picker); AAB conforme política fotos/vídeos.
/// 11.2.295+1590: Firestore — streams broadcast/resilientes (dashboard dept, chat, _panel_cache);
/// menos Crashlytics `permission-denied` e «Stream already listened».
/// 11.2.295+1589: deploy completo — login Controle Total, mídia rápida (fotos/vídeos/chat/membros), web, AAB, iOS.
/// 11.2.295+1588: deploy completo produção — web, AAB Play, ZIP iOS Codemagic (push).
/// 11.2.295+1587: deploy completo — Command Center master, login auto-sessão, chat 2ª entrega.
/// 11.2.295+1586: Painel Master Command Center Super Premium — home unificada, menu 6 grupos,
/// pesquisa global Ctrl+K, ficha igreja, feature flags, cache KPIs 15 min.
/// 11.2.295+1581: painel/membros/avisos expresso; chat WhatsApp-like (envio otimista, prévia mídia, segurar voz).
/// 11.2.295+1580: deploy completo — painel cache, membros/avisos/eventos rápidos, renovação plano web/Android.
/// 11.2.295+1579: bump iOS — build 1578 já enviado à App Store Connect (90189 redundant upload).
/// 11.2.295+1578: deploy completo — web online, doações iOS Safari, chat, AAB Play, ZIP iOS Codemagic (push).
/// 11.2.295+1577: deploy completo — web, regras, functions, AAB Play, ZIP iOS Codemagic (push).
/// 11.2.295+1576: deploy completo — web hosting, regras, functions, AAB Play,
/// ZIP iOS Codemagic (push).
/// 11.2.295+1575: `/igreja/login/apple` — login directo (sem membro/gestor), destino padrão
/// `/atualizar-plano`; parcelas cartão 1–6 enviadas sempre ao `createMpPreapproval`; UI Mensal/Anual.
/// 11.2.295+1574: Configurações «Trocar de conta» — signOut + AuthGate para `/igreja/login`
/// (web/Android/iOS), sem tela presa; limpa prefs locais de login da igreja.
/// 11.2.295+1573: MP igreja — secção Configurações só gestor/admin/master ou permissão
/// `configuracoes_banco`; Firestore: leitura `igrejas/.../config/mercado_pago` restrita.
/// 11.2.295+1572: Planos Master — `PlanPriceService.watchEffectivePlanConfigs()` (Firestore em
/// tempo real) no site divulgação, `/planos`, login e renovação/Apple; removido cache 2 min.
/// 11.2.295+1571: Hub Chat — aba «Conversas»: pull-to-refresh + reanexar stream
/// ao voltar do fundo e ao focar a aba (estilo WhatsApp/Telegram, sem botão extra).
/// 11.2.295+1570: Renovar plano — anual + cartão até 6x (web/Android/iOS/shell),
/// selector de parcelas para todo o fluxo do gestor (não só `from=ios_app`).
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
const String appBuildNumber = '1601';

/// 11.2.295+1569: Web `/igreja/login/apple` (mesmo login + pós-login em planos); «Atualizar plano» iOS
/// abre esse URL; fluxo expresso `from=ios_app` — botões Mensal/Anual nos planos, scroll ao pagamento,
/// cartão anual até 6x + checkout MP embebido na página.
/// 11.2.295+1568: App iOS/Android — abertura direta no painel com sessão Firebase persistida;
/// login da igreja sem escolha «Sou membro / gestor»; bloqueio biométrico com «Usar senha» sem signOut.
/// 11.2.295+1567: Chat hub — abas com keep-alive + resync de grupos ao voltar à app/aba Grupos;
/// fundo suave nas abas; pull-to-refresh em Grupos; folha do grupo — «Adicionar membros» (vínculo
/// departamentos + thread) com permissão alinhada ao módulo Departamentos.
/// 11.2.295+1566: deploy completo — chat (alertas por conversa/departamento/pessoa, push em
/// segundo plano som/vibrar/silêncio Android+iOS), folha «Nova conversa direta» Super Premium com fotos;
/// web hosting + AAB Play + ZIP iOS Codemagic.
/// 11.2.295+1565: Dashboard igreja — banner «Primeiros passos» Super Premium (gradiente nos atalhos).
/// 11.2.295+1564: Alertas do chat — regras `chat_threads` + stream resiliente + tenant resolvido;
/// UI Super Premium (segmentos gradiente, cartões `cardBackground`, sem «vidro» claro).
/// 11.2.295+1563: Chat — aba Grupos: ordem por arrastar (⋮⋮) persistida em `departmentGroupOrderIds`;
/// sem preferência ou com pesquisa → ordem A–Z; botão «Ordem alfabética (A–Z)».
/// 11.2.295+1562: Chat — aba Grupos com cartões em faixa horizontal (pílula + gradiente L→R + barra de cor).
/// 11.2.295+1561: Chat — presença «online» ao abrir o painel da igreja (heartbeat no shell + resume);
/// removido timer duplicado só no hub.
/// 11.2.295+1560: Chat hub — `ChurchChatMemberPrefs.watch` sem `Stream.empty` (evita área cinza);
/// aba Grupos em faixas (`SliverList` + cartão horizontal); `TabBarView` + lista com fundo surface.
/// 11.2.295+1559: deploy completo — web hosting, regras, functions, AAB Play,
/// ZIP iOS Codemagic (push); docs migração iOS Reader Controle Total/Moovaup.
/// 11.2.295+1558: iOS Reader — «Alterar plano» abre `/igreja/login` (login Super Premium)
/// e só depois `/atualizar-plano?from=ios_app`; copy renew/MP embebido «sem site MP».
/// 11.2.295+1557: deploy completo — web, regras, functions, AAB Play, ZIP iOS Codemagic;
/// chat hub stream resiliente + upload mídia; `/atualizar-plano` gate claims; fluxo pagamento iOS.
/// 11.2.295+1556: deploy completo — web hosting, regras/índices, functions, AAB Play,
/// ZIP iOS (Codemagic), chat (envio/cancelar mídia, remoção remetente, cleanup Storage).
/// 11.2.295+1555: deploy completo — regras Firestore chat (lista conversas),
/// cache lista conversas no hub, login biometria nativo; web + AAB + ZIP iOS.
/// 11.2.295+1554: Deploy produção completo (regras, functions, web, AAB, ZIP iOS, push Codemagic).
/// 11.2.295+1553: Chat — alertas em primeiro plano por conversa/DM/grupo + global (Firestore
/// `chat_member_prefs`); página Super Premium com pesquisa; FCM `threadType` na Cloud Function.
/// 11.2.295+1552: Chat — fotos reais em grupos (lista + bolhas), mapa de fotos partilhado;
/// push em lote na Function; índice `chat_threads`; primeiro plano sem SnackBar duplicado no chat.
/// 11.2.295+1551: Painel/mural/site — vídeo Firebase sem extensão no path entra no player inline;
/// [ChurchHostedVideoSurface] com retries + timeout maior, capa no erro, «Tentar de novo», botão Ampliar;
/// warmup de token alinhado.
/// 11.2.295+1550: Web `/atualizar-plano` — slug reservado (evita «Igreja não encontrada»);
/// gate com Apple na web + `getRedirectResult` após OAuth redirect; LoginPage conclui redirect também para esta rota.
/// 11.2.295+1549: Login painel igreja — removida faixa «Login expresso» (só Google, Apple e e-mail/senha).
/// 11.2.295+1548: Painel — cap `finance` 2500; Cloud Function `onChurchFinanceWritePanelSummary`
/// grava `igrejas/{id}/_panel_cache/finance_summary` (throttle 90s); regras `_panel_cache` leitura gestão.
/// 11.2.295+1547: Chat Igreja — AppBar do thread com o mesmo gradiente 3 cores do hub/anexos;
/// gradiente partilhado em `church_chat_premium_gradients.dart`.
/// 11.2.295+1546: Painel — menos docs no stream `finance` (cap centralizado), refresh sem
/// `getIdToken(true)` forçado; warmup pré-carrega `finance` recente; comentários nos limites.
/// 11.2.295+1545: Chat hub — cabeçalho e abas com gradiente Super Premium (teal/azul/roxo),
/// campos de pesquisa com moldura gradiente; thread — `prefer_interpolation` na pesquisa de mensagens.
/// 11.2.295+1544: Chat Igreja — folha de anexos estilo WhatsApp (ícones coloridos + gradiente),
/// bolhas próprias com gradiente Super Premium; foto/vídeo com barra Ampliar/Guardar ou Baixar;
/// vídeo a partir da câmara.
/// 11.2.295+1543: Eventos e avisos (mural) — descrição só com texto multilinha (sem Quill no
/// formulário); grava `text` + `textDelta` mínimo para `ChurchPostRichTextViewer` e feed.
/// 11.2.295+1542: Chat Igreja — lista «Conversas» estável (DM sem segundo stream no thread;
/// foto de perfil + primeiro nome + prévia estilo WhatsApp); grupo mostra «Você» nas suas mensagens.
/// 11.2.295+1541: login nativo painel igreja alinhado ao Controle Total — e-mail antes de
/// Google/Apple/login expresso (sem Face ID pré-OAuth); confirma e-mail pós-conta; biometria
/// opcional só após login (Ativar exige leitura); removida biometria automática ao abrir.
/// 11.2.295+1540: deploy completo — web hosting, regras, functions, AAB Play,
/// ZIP iOS Codemagic, chat/departamentos e correções recentes.

/// Igual ao pubspec sem prefixo (ex.: 11.2.293+1447).
const String appVersionFull = '$appVersion+$appBuildNumber';

/// Labels for footer and installed-version texts.
const String appVersionLabel = 'v$appVersion+$appBuildNumber';


