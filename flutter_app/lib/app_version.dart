/// Single source of app version used everywhere.
/// Política (jun/2026): marketing **fixo** em [appVersion] = 11.2.305 — só incrementar [appBuildNumber].
/// 11.2.305+1856: unificação ChurchRepository, chat engine (hub/thread/presence), cache-first módulos, deploy completo.
/// 11.2.305+1855: sync silenciosa, publish otimista aviso/evento/financeiro, dashboard cache 1 read, chat streams, landing botões.
/// 11.2.305+1854: _panel_cache statistics/public_site, WhatsApp 1 toque, dashboard inteligente, notificações, offline, agenda visual.
/// 11.2.305+1853: P0 Membros — foto perfil strict publish (paths Storage, sem downloadURL no Firestore).
/// 11.2.305+1852: Web — cadastro/chat igreja alinhado ao mobile, chat painel tela cheia, consolidação igrejas/{id}/.
/// 11.2.300+1847: Web — cadastro/chat igreja alinhado ao mobile, chat painel tela cheia, consolidação igrejas/{id}/.
/// 11.2.299+1846: Multi-tenant completo, arranque Android rápido, diagnóstico master, armazenamento/mídias master.
/// 11.2.298+1845: App — arranque rápido mobile, login imediato pós-chat/mídia, cadastro público membro+foto, membros/chat BPC.
/// 11.2.295+1834: Web — Cadastro da Igreja lê perfil completo do cluster (servidor), sem cache vazio.
/// 11.2.295+1833: BPC — cluster ancorado, sync dados/MP servidor, tenant canónico _sistema, fallback irmãos priorizado.
/// 11.2.295+1832: Membros — ícone WhatsApp vetorial, chat abre directo, wa.me/whatsapp:// em todos os atalhos.
/// 11.2.295+1831: Doação MP — migração cluster (O Brasil), contas 323 em docs irmãos, bootstrap tenant-first.
/// 11.2.295+1830: Painel igreja — agenda/cultos tenant operacional + sibling fallback; leituras leves; cartão membro resiliente.
/// 11.2.295+1829: Deploy — licença master, notificações FCM (avisos/eventos/cadastros/aniversários), storage canónico.
/// 11.2.295+1828: Deploy — Pastoral removido, transmissão Chat Igreja, Cargos alinhado FUNCAO, site divulgação ícones.
/// 11.2.295+1823: Paths Firestore/Storage — avisos/eventos sibling fallback, mural tenant operacional, busca global igrejas/, prefetch shell, cartão configDoc.
/// 11.2.295+1822: pending_uploads só em igrejas/{tenantId}/pending_uploads — sem raiz pendingUploads.
/// 11.2.295+1821: Android — checkout MP no navegador (evita crash PlatformView JNI 15/16).
/// 11.2.295+1820: Doação — paths tenant operacional, contas MP sem timeout 16s, config MP irmãos.
/// 11.2.295+1819: Deploy completo — web, AAB Play, ZIP iOS Codemagic.
/// 11.2.295+1818: Eventos — categorias tenant operacional, endereço igreja, publicar rápido.
/// 11.2.295+1817: Avisos — endereço igreja rápido, botão antes do CEP, publicar sem rede off.
/// 11.2.295+1816: Chat igreja — envio sem desligar rede (texto/foto/vídeo WhatsApp-like).
/// 11.2.295+1815: Carteira membro — tenant operacional antes do load, CPF do membro, findByHint resiliente.
/// 11.2.295+1814: Licença — lê expiresAt, free real, carência 3d, sem loop suspended.
/// 11.2.295+1813: Escolha plano — prefetch PIX/cartão, tenant cache, checkout instantâneo.
/// 11.2.295+1812: Fornecedores — cache RAM, FutureBuilder estável, recibo PDF rápido, agenda sem bloqueio.
/// 11.2.295+1811: Patrimônio — bootstrap instantâneo, cache RAM, novo bem sem bloqueio, permissões núcleo financeiro.
/// 11.2.295+1810: Financeiro — bootstrap instantâneo, FutureBuilder estável, strip sem query ilimitada.
/// 11.2.295+1809: Relatórios — cache RAM membros, FutureBuilder financeiro estável, PDF rápido (branding timeout).
/// 11.2.295+1759: Cartão membro — índice signatários, paginação 40, cache foto PDF.
/// 11.2.295+1758: Painel master — paginação users/igrejas, storage amostra 100, limites unificados.
/// 11.2.295+1757: Cadastro público Firestore-first + foto BG; certificados/finance/liderança paginados.
/// 11.2.295+1756: Evolução total prompt mestre — share unificado, lazy load 20, counters, docs §12–19.
/// 11.2.295+1755: Chat retention 90d, lazy lists 20, LWW offline, share_plus WhatsApp.
/// 11.2.295+1754: Upload queue serial, vídeo eventos H.264 720p/480p, dashboard_stats increment, UI retry mídia.
/// 11.2.295+1753: Refactor offline-first — Web putData, eventos 70%, upload 30s imagens, AuthService biometria.
/// 11.2.295+1752: Configuração mestre — StorageService, FIREBASE_RULES_SECURITY.txt, chat page 20, CachedNetworkImage.
/// 11.2.295+1751: Offline-first coordinator — Firestore persistence explícita, sync silenciosa, manual arquitetural, imagem 70%.
/// 11.2.295+1750: Prompt mestre — sync optimista, eventos 10f+2v, financeiro path, upload 30s, biometria estrita.
/// 11.2.295+1749: Upload 1024/75 global, AuthService + biometria auto, Storage com loading/erros claros.
/// 11.2.295+1748: Web publicar/ler directo Firestore (sem fila Hive offline), grupos cache instantâneo, recover Web antes de gravar.
/// 11.2.295+1747: Quota Auth definitivo — nunca getIdToken(true), publicar/ler com sessão em cache.
/// 11.2.295+1746: Chat/avisos instantâneos — abrir DM directo, feed paralelo, grupos com cache, menos token em leituras.
/// 11.2.295+1745: Configurações abre instantâneo — prefs locais primeiro, Firestore em background.
/// 11.2.295+1744: Estabilidade global CT — dept/cargos/escalas/financeiro/fornecedores cache-first Hive; sem getIdToken em leituras.
/// 11.2.295+1743: Chat contatos cache-first — sem membrosRecent(600), stream directory, sem getIdToken no painel.
/// 11.2.295+1739: Web arranque rápido — sem health check bloqueante, preheat em background, Firestore WebChannel.
/// 11.2.295+1737: Sempre painel inicial ao entrar — sem restaurar última aba/chat/módulo.
/// 11.2.295+1736: Firestore bloqueante online, Google silent restore, biometria AuthGate, painel/chat/património.
/// 11.2.295+1735: Deploy completo — guard quota Auth, web+AAB+iOS Codemagic.
/// 11.2.295+1734: Guard quota Auth — menos getIdToken, sem soft-reinit em loop, resume debounced.
/// 11.2.295+1733: Firebase ensureAlwaysOn, chat/eventos/avisos/património/perfil upload rápido (sem OOM), debounce pesquisa.
/// 11.2.295+1732: Fase final QA — multiplataforma, Nunca Perder Dados, health 5min, Modo QA 28 testes, métricas sessão.
/// 11.2.295+1731: Onda 2 — financeiro comprovante BG, cartão/carta Firestore-first, relatórios limit+logs.
/// 11.2.295+1730: Firestore-first foto membro + status creating/uploading/published; regra Cursor módulos críticos.
/// 11.2.295+1729: Cirúrgico — chat texto Firestore imediato, auto-recovery presas, dashboard_stats cache-first, upload 60s/3x.
/// 11.2.295+1728: Produção premium — YahwehFlowLog global, patrimônio Firestore-first background, dashboard_stats alias.
/// 11.2.295+1727: Auditoria publicação — logs AVISO/EVENTO/CHAT, retry evento Firestore-first, regra Cursor alinhada.
/// 11.2.295+1726: Publicar aviso/evento/chat — Firestore primeiro, drain 2s máx, agenda/push em background, logs diagnóstico.
/// 11.2.295+1725: Firestore canónico eventos+chats; migração automática CF noticias/chat_threads.
/// 11.2.295+1724: Login automático — só Firebase+biometria; sem Google silencioso no arranque; trocar conta limpa tudo.
/// 11.2.295+1723: ChurchDataService único — Firestore→sucesso→upload→URL; queries limit 20; logs completos.
/// 11.2.295+1722: Gravação CT — Firestore antes de Storage (avisos/eventos), paths igrejas/, dashboard/home, limit 20.
/// 11.2.295+1721: Firebase/upload CT — core/no-app fix, fila chat sem fantasmas, painel warmup, publicar aviso/evento estável.
/// 11.2.295+1720: Deploy completo — Firestore Web estável (CT), painel/chat/mural/patrimônio resilientes.
/// 11.2.295+1719: Firestore Web estável (CT) — sem terminate automático; patrimônio/doação/cartão/mural resilientes.
/// 11.2.295+1718: Programação painel estável (CT) — disco+RAM, noticias resilientes, sem cartão vermelho na web.
/// 11.2.295+1717: Painel/chat/membros instantâneo — cache-first warmup, contatos sem skeleton, fotos perfil sem getDownloadURL mobile.
/// 11.2.295+1716: Exibição rápida — URL do Firestore directa (sem getDownloadURL); feed/galeria/painel warmup.
/// 11.2.295+1715: Chat — Limpar/Reenviar reais; banner só ficheiros recuperáveis; purge legacy pending_uploads.
/// 11.2.295+1714: Storage imediato (Controle Total) — reconnect core/no-app; chat sem fila fantasma; avisos/eventos/património/perfil.
/// 11.2.295+1713: Deploy completo — foto perfil (membro própria; gestor/secretário/tesoureiro qualquer); regras mural; web/AAB/iOS.
/// 11.2.295+1712: Deploy completo — regras mural (liderança) + chat aberto membros; web, AAB Play, iOS Codemagic.
/// 11.2.295+1711: Firestore Web (Controle Total) — sem mensagens falsas de «rede lenta»; retry + recuperação INTERNAL ASSERTION; publicar avisos/chat estável em 5G.
/// 11.2.295+1710: Estabilidade global (web/iOS/Android) — sessão, master, divulgação, painel, chat.
/// 11.2.295+1709: Chat thread rápido/estável — mensagens cache+retry (padrão Controle Total), stream resiliente.
/// 11.2.295+1708: Sessão estável (web/iOS/Android) — não desloga ao trocar de aba; painel com cache.
/// 11.2.295+1707: Chat igreja — atalhos abrem módulo Chat com conversa (bridge + DM resiliente).
/// 11.2.295+1706: Atalhos Chat (painel, aniversariantes, líderes, membros) — resolve authUid + abre DM automático.
/// 11.2.295+1705: Chat Contatos — pesquisa silenciosa (sem refresh do hub), abrir DM estável.
/// 11.2.295+1704: Avisos/eventos — publicação resiliente (retry Firestore, sem derrubar painel na rede instável).
/// 11.2.295+1703: Membros → Chat igreja — navegação estável (navigator raiz antes de fechar folha, timeout DM).
/// 11.2.295+1702: Chat Igreja web — contatos (membros) resilientes, grupos todos para liderança, sem hang presença/bootstrap.
/// 11.2.295+1701: Património — até 5 fotos/bem (galeria multi + WebP); constante centralizada.
/// 11.2.295+1700: Avisos — até 5 fotos só imagens; vídeo só em eventos; upload rápido partilhado com mural.
/// 11.2.295+1699: Chat Igreja WhatsApp — recibos ✓✓/lido DM, preview câmara, uploads paralelos limitados, entrega em grupos.
/// 11.2.295+1698: Upload rápido — bootstrap Storage em cache 3 min, WebP sem recomprimir, content-type correto, 1 warm/publicar.
/// 11.2.295+1697: Resiliência global — ChurchTenantResilientReads, warmup completo, ResilientPanelQueryFutureBuilder.
/// 11.2.295+1696: Web eventos/avisos — foto automática (sem recorte); Firestore cache+retry no formulário.
/// 11.2.295+1695: Estabilidade Controle Total — leituras cache+retry, feeds offline, streams resilientes, bootstrap 4s.
/// 11.2.295+1694: Painel rápido — AuthGate cache 1.º frame, getUserProfile+igreja no servidor, sem bloquear repair.
/// 11.2.295+1693: Upload/login Controle Total — bootstrap Storage leve, sem reconnect no resume, sessão fixa.
/// 11.2.295+1692: Web arranque — sem splash preso no painel; AuthGate cache/timeout 22s.
/// 11.2.295+1691: Mídia rápida global — chat/avisos/eventos/patrimônio upload directo + bootstrap paralelo.
/// 11.2.295+1690: Patrimônio — upload fotos directo (WebP + putData, sem fila offline dupla).
/// 11.2.295+1689: Velocidade Controle Total — rodapé mobile em IndexedStack, painel cache-first sem skeleton.
/// 11.2.295+1688: iOS CI — SPM off + Crashlytics dSYM no Codemagic; chat/mural web estável.
/// 11.2.295+1687: Fotos painel/chat/perfil — cache web instantâneo, thumbs, painel não bloqueia prefetch.
/// 11.2.295+1686: Avisos/eventos — escolher fotos + Publicar grava tudo na hora (padrão Controle Total).
/// 11.2.295+1685: CI iOS — upload dSYM Crashlytics obrigatório (sem Missing dSYM).
/// 11.2.295+1684: Login fixo — sessão Google/e-mail no arranque; biometria activa após entrar; restore antes do login.
/// 11.2.295+1683: Firebase avisos/eventos — publicar/feed sem core/no-app; bootstrap publish no shell.
/// 11.2.295+1682: Firebase avisos/eventos/chat, Sair no topo, TestFlight config, signatários, full screen módulos.
/// 11.2.295+1681: Deploy completo — Google 1x conta, fotos instantâneas, carteirinha gestor, web/AAB/iOS.
/// 11.2.295+1680: Deploy completo — módulos full screen, chat compacto, purge histórico admin, web/AAB/iOS.
/// 11.2.295+1679: Deploy completo — chat bootstrap leve, painel 6s streams, master token cache, web/AAB/iOS.
/// 11.2.295+1678: iOS — upload automático dSYM Firebase Crashlytics (Xcode + Codemagic).
/// 11.2.295+1673: Firebase padrão CT — putData directo, fila só disco, sem pending_uploads Firestore.
/// 11.2.295+1672: Chat — Limpar apaga pending_uploads Firestore + stubs; web sem fila fantasma.
/// 11.2.295+1671: Sessão permanente (Controle Total) — restore disco + OAuth silencioso; só limpa em Trocar conta.
/// 11.2.295+1670: Velocidade Controle Total — shell otimista, preheat único, painel cache-first, web Firestore estável.
/// 11.2.295+1669: Upload avisos/eventos/chat — init Firebase fiável (padrão Controle Total); sem health FCM lento.
/// 11.2.295+1668: Chat nativo — áudio/foto upload direto; fila pendente com Limpar/Reenviar.
/// 11.2.295+1667: Cadastro igreja — pré-carrega doc Firestore (não pede de novo).
/// 11.2.295+1666: Chat web — envio leve (sem reconexão longa); limpa fila pendente inválida.
/// 11.2.295+1665: Membros — cache offline + queries resilientes (menos erro de rede).
/// 11.2.295+1664: Fix build web (índices shell main + dashboard parallel).
/// 11.2.295+1663: Configurações — links MP/InitPay; menu Config abaixo Cadastro; membro só notif/conta/bio.
/// 11.2.295+1662: Chat Igreja — lista Conversas estável (cache disco + stream único, sem piscar).
/// 11.2.295+1661: Site público — public_feed com URLs resolvidas + prefetch web/iOS/Android.
/// 11.2.295+1660: Cache media_prefetch (logo + fotos painel) — Functions + RAM instantânea.
/// 11.2.295+1659: Login persistente — splash sessão→painel; biometria só no AuthGate; preheat paralelo.
/// 11.2.295+1658: Login — biometria sem seletor Google automático; trocar conta limpa sessão.
/// 11.2.295+1657: FirebaseBootstrap + FirebaseService — paridade Chat/Avisos/Eventos nativo.
/// 11.2.295+1656: Diagnóstico Chat vs Avisos/Eventos — remove Firebase.instance na UI eventos + log Firebase.apps.
/// 11.2.295+1655: Paridade Web/Android/iOS — UnifiedUploadService (chat = feed).
/// 11.2.295+1654: Fix core_no-app — bootstrap antes de publish/upload nativo (avisos/eventos).
/// 11.2.295+1653: Deploy completo produção — web, AAB Play, ZIP iOS Codemagic (pilares finalização).
/// 11.2.295+1652: Pilares finalização — AppFinalizeBootstrap, checklist, sessão+filas no resume.
/// 11.2.295+1651: Saúde do Sistema (uploads global), feed strict + chat outbox → pending_uploads.
/// 11.2.295+1650: Fase 2 — pending_uploads automático, paths tenants/… (avisos/eventos), fila offline.
/// 11.2.295+1649: Chat — audio_waveforms (mobile) + favoritar mensagem + lista de favoritas.
/// 11.2.295+1648: Chat — uploadProgress 0–1 no stub Firestore + bolha local (áudio com barra).
/// 11.2.295+1647: Pipeline uploads unificado; FirebaseBootstrap.instance; analytics upload.
/// 11.2.295+1646: Chat/conversas estáveis; avisos/eventos upload-before-Firestore; logs reais.
/// 11.2.295+1645: Firebase — health Functions/FCM, pending_uploads Firestore, guarda publicação.
/// 11.2.295+1644: Firebase — bootstrap único antes do runApp, health check, reconexão, erros reais.
/// 11.2.295+1643: Avisos — fix publicar 3 fotos (Firebase cache, upload 2 paralelo, sem falso no-app).
/// 11.2.295+1642: Avisos/Eventos — upload Storage antes do Firestore; feed sem posts vazios; 1920px/80%.
/// 11.2.295+1641: Chat Igreja — conversas estáveis (índice nunca apaga com mensagens), entregue ✓✓, mapa Firestore.
/// 11.2.295+1640: Chat Igreja — mídia definitiva (compress 1920, thumb, chat_uploads, retry offline, paths Storage).
/// 11.2.295+1639: Chat — cache local conversas + índice lastMessage + upload foto direto Storage.
/// 11.2.295+1638: Chat — conversas estáveis na lista + mídia (batch Firestore, hasConversation).
/// 11.2.295+1637: Login fixo — biometria ao abrir (Google/Apple), OAuth silencioso se cancelar digital.
/// 11.2.295+1636: Eventos — fotos ao escolher (Storage+Fila), publicar instantâneo, vídeo em background.
/// 11.2.295+1635: Chat/avisos/eventos — regras memberLinked+chatTenantMemberFast, Firebase bootstrap, login OAuth, upload mídia.
/// 11.2.295+1606: iOS «Alterar plano» — Safari abre `/atualizar-plano` (login Google/Apple/e-mail + PIX/cartão).
/// 11.2.295+1605: Chat WhatsApp igreja — fixar/arquivar, typing na lista, gravar áudio,
/// mensagem pastoral e aviso automático de escala no grupo do departamento.
/// 11.2.295+1604: Chat/avisos/eventos — upload sem spinner infinito (cache local mural,
/// outbox reenvio, timeout Storage, preview instantâneo, anexos paralelos no chat).
/// 11.2.295+1603: iOS TestFlight — corrige Binário inválido (Info.plist push/LSApplicationQueriesSchemes).
/// 11.2.295+1602: Chat, avisos e eventos — upload de fotos/vídeos definitivamente mais rápido
/// (turbo mobile release, WebP menor, vídeo 540p/sem transcode até 42MB, uploads em lote limitados,
/// stub chat antes de transcode, menos retries).
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
/// 11.2.295+1608: Chat DM — excluir conversa (⋮ + seleção múltipla); MediaService compressão;
/// upload otimista avisos/eventos/chat; gravação áudio AAC.
/// 11.2.295+1613: Eventos/avisos ultrarrápido — WebP 1024px/75% antes do Storage; cache leitura 800px.
/// 11.2.295+1612: Upload Storage — UploadTask com progresso, anti-paragem, timeout por tamanho;
/// chat stub Firestore (uploading→sent); mensagens de erro amigáveis.
/// 11.2.295+1611: Upload avisos/eventos/chat — token Firebase, timeouts maiores,
/// paralelo no mural; botão «Adicionar foto» na barra inferior (Super Premium).
/// 11.2.295+1620: Chat, avisos e eventos Super Premium — fotos com path válido no iOS
/// (sem OOM no publish), eventos vídeo até 90 s, chat anexos por ficheiro no mobile.
/// 11.2.295+1610: Eventos e avisos restaurados (v1555 — MediaUploadService direto);
/// chat igreja — envio foto/vídeo/arquivo com a mesma lógica (sem stub Firestore).
/// 11.2.295+1609: Mídia rápida — preview imediato avisos/eventos; chat foto auto-envio;
/// vídeo 90s (chat + eventos); FAB novo aviso; vídeo hospedado no mural.
const String appVersion = '11.2.305';
/// 11.2.295+1634: Eventos/avisos v1555 — upload síncrono (1 WebP/foto, URLs no Firestore);
/// chat DM — conversas legadas aparecem na aba Conversas + fallback merge reforçado.
/// 11.2.295+1787: Mobile warmup — tenant operacional + Hive financeiro/contas/despesas fixas.
/// 11.2.295+1786: Painel Master — KPIs RAM/prefs instantâneos, SWR background, BI sem scan lento.
/// 11.2.295+1785: Financeiro — tenant operacional (cluster irmão), cache-first SWR, despesas/receitas fixas resilientes.
/// 11.2.295+1780: Chat — envio texto WebGuard+retry, lista não lidas no topo, badge WhatsApp.
/// 11.2.295+1788: Membros + cartão membro — tenant operacional cluster, membrosRecent sibling fallback.
/// 11.2.295+1789: Membros painel total real (directory); chat tenant operacional unificado; painel inicial resolve tenant cedo.
/// 11.2.295+1790: Financeiro e Patrimônio — tenant operacional + sibling fallback, lista completa com paginação.
/// 11.2.295+1791: Cadastro da Igreja — bootstrap estável, cache cluster, sem piscar/reload no formulário.
/// 11.2.295+1792: Estabilidade global CT — sessão sempre logada web/Android/iOS, keepalive Firestore, rede resume.
/// 11.2.295+1793: Cadastro da Igreja — pintura instantânea cache-first; cluster scan só em background.
/// 11.2.295+1794: Doação — contas MP cache-first, tenant operacional, timeout MP (sem Aguarde preso).
/// 11.2.295+1795: Membros — painel 62/62 ativos (sem orderBy updatedAt); summary directory + lista rápida.
/// 11.2.295+1796: Departamentos — cache-first instantâneo; bootstrap presets só em background.
/// 11.2.295+1797: Visitantes — cache RAM + mem; sem preparePanelRead; plain query se faltar createdAt.
/// 11.2.295+1798: Cargos — cache-first instantâneo; sem resolveEffectiveTenantId bloqueante.
/// 11.2.295+1799: Mural avisos — feed imediato; avisosFeed sem preparePanelRead.
/// 11.2.295+1800: Mural eventos — Feed/Galeria/Fixos/Dashboard cache-first instantâneo.
/// 11.2.295+1801: Pedidos de oração — cache RAM + Hive; sem preparePanelRead.
/// 11.2.295+1802: Agenda inteligente — cache RAM por mês; tenant + Firestore cache-first.
/// 11.2.295+1803: Aprovações rápidas — pendentes cache-first; sem preparePanelRead.
/// 11.2.295+1804: Chat Igreja — grupos instantâneos, layout web WhatsApp, mensagens/upload rápidos.
/// 11.2.295+1805: Minha Escala + Escala Geral — cache-first instantâneo; sem preparePanelRead.
const String appBuildNumber = '1858';

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

/// Rodapé do painel igreja (iPhone/Android/web) — só marketing, sem +build.
const String appVersionPanelLabel = 'v$appVersion';

/// Labels com build (configurações do app, painel admin master, update checker interno).
const String appVersionLabel = 'v$appVersion+$appBuildNumber';


