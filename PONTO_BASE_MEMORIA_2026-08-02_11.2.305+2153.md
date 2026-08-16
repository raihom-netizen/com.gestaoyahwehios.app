# Ponto Base de Memória — Gestão YAHWEH (GERAL)

**Data:** 2026-08-02  
**Release de referência:** `11.2.305+2153`  
**Marketing:** `11.2.305`  
**Build / versionCode:** `2153`  
**Git:** `main` — commit `3710feb`  
**Web + forceUpdate:** `config/appVersion` = `11.2.305+2153`, `minBuildNumber=2153`, `forceUpdate=true`, `webRefresh=true`  
**Anterior:** `PONTO_BASE_MEMORIA_2026-07-30_11.2.305+2145.md` (arquivada)

**Firebase:** `gestaoyahweh-21e23`  
**Bucket Storage:** `gs://gestaoyahweh-21e23.firebasestorage.app`  
**Web produção:** https://gestaoyahweh-21e23.web.app

**Este é o único ponto de memória ativo.**

---

## Regra principal

- Toda melhoria parte deste ponto: **somar sem regredir**.
- Não mudar `appVersion` (`11.2.305`) sem ordem explícita; incrementar apenas `appBuildNumber` / `+N`.
- **Paridade obrigatória:** Web + Android + iOS e paths `igrejas/{churchId}/…`.
- Cache-first, paginação 20, sem scans pesados no caminho quente e sem cache vazio apagar dados válidos.
- Deploy/build somente com pedido explícito e ao final.
- Painel pós-login usa `ChurchRepository`; proibidos novos resolvers, `*ServiceV2` e novas escritas em `tenants/{id}`.
- Publicação de mídia: Storage → validar → Firestore uma vez.
- Chat principal de produção: Yahweh Chat (Firestore) + TDLib (Telegram in-app) no Android; iOS com gate/`codemagic_ios_tdlib_auto.sh` e fallback Firebase se o linker nativo falhar.
- Web TDLib: paridade UX via Telegram Web embutido (`TdlibWebParity`) — sem FFI no browser.

---

## Versão oficial confirmada

- `flutter_app/lib/app_version.dart`: `appVersion='11.2.305'`, `appBuildNumber='2153'`
- `flutter_app/pubspec.yaml`: `version: 11.2.305+2153`
- `flutter_app/web/version.json`: `version=11.2.305`, `build_number=2153`
- Web publicada com build `2153` (confirmado em `https://gestaoyahweh-21e23.web.app/version.json`).
- Git `main` sincronizada com `origin/main` no commit `3710feb`.

## Artefatos 2153

- AAB Play: `D:\Temporarios\GestaoYahweh_11.2.305_build2153_play.aab`
  - Tamanho: `244087333` bytes
  - SHA-256: `84C0FF189F0798254CFB010106BD1868993B4E7B8C26081348611CCE6714829A`
- ZIP iOS: `D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2153.zip`
  - Tamanho: `108279323` bytes
  - SHA-256: `8846C5C8B040D225BBC0EEDDC56729BA48A20564030CBD44069917ACE7089D98`

## Android / Play

- `targetSdk=36`, `compileSdk=36`, NDK `28.2.13676358`.
- AGP `8.13.2`.
- R8 otimizado ativo:
  - `isMinifyEnabled=true`
  - `isShrinkResources=true`
  - `android.r8.optimizedResourceShrinking=true`
- AAB release assinado, ofuscado, validado (MainActivity, AD_ID, 16K) e copiado para `D:\Temporarios`.
- TDLib Android no artefato; push background via `tdlibFirebaseMessagingBackgroundHandler` + `TdlibBackgroundPushStore`.
- **Pendente externo:** carregar/processar o AAB `2153` na Play Console.

## Firebase / backend

- Firestore rules: remoto = local, `OK` (preflight deploy 2153).
- Storage rules: remoto = local, `OK`.
- Firestore indexes: remoto = local, `OK`.
- Cloud Functions: deploy completo na passagem inicial do release; republicação posterior sem alterações detectadas.
- Documento remoto `config/appVersion` confirmado em `11.2.305+2153` (`forceUpdate=true`, `webRefresh=true`).
- Se a API Rules retornar 429/503: fluxo simples → completa; nunca deixar bridge como release final.

## Yahweh Chat / TDLib — build 2153

- Hub TDLib: conversas/grupos/contatos, mute/arquivo, filtro igreja, sync, atalhos busca/sessões/dashboard.
- Thread: voz, mídia, retry, rascunhos, typing, pin, forward, reações, presença.
- Push app fechado: isolate FCM + paths de sessão; foreground FCM/APNs.
- Web: banner/CTA Telegram Web (`TdlibWebParity`).
- iOS: `YAHWEH_TDLIB_IOS_ENABLED` + `scripts/codemagic_ios_tdlib_auto.sh` (try-native / auto-fallback).
- Correção crítica no deploy: `tdlib_background_push_io.dart` restabelecido (export recursivo quebrava o AAB).

## Mídia e módulos críticos — build 2153

- Uploads e exibição reforçados em Avisos, Eventos, Chat, Master, site e cadastro público.
- Microfone iOS: permissão nativa sequencial + Ajustes se permanentemente negado.
- Chat preserva conversas/grupos diante de resultados vazios transitórios.
- Patrimônio confirma upload + Firestore antes do sucesso.
- Financeiro e Fornecedores: comprovantes pelo `storagePath` canônico.
- Utilitários / YouTube embed / galeria Instagram: evolução incremental no mesmo release.

## iOS / Codemagic

- Bundle app: `com.gestaoyahwehios.app`
- Widget: `com.gestaoyahwehios.app.GestaoYahwehWidget`
- App Group: `group.com.gestaoyahwehios.app.widget`
- Team: `82RC6YL7KL`
- Branch: `main`; Codemagic somente iOS e início **manual**.
- Preservar Sign in with Apple, Push, App Groups, perfis, entitlements, IPA e validação ASC.
- Soft-fail TDLib nativo: se linker falhar → Yahweh Chat Firebase, sem crash.
- Asset dotenv = `.env.example`; nunca incluir `.env`.
- Nunca gerar AAB Android no Codemagic.
- **Pendente externo:** disparar build Codemagic a partir de `3710feb` e confirmar IPA/TestFlight.

## Preservar crítico

- Offline-first + `FirestoreWebGuard`, sem `terminate()` no hot path.
- `PublicationEngine`, `ChurchRepository`, `ChurchStorageLayout` e chat `igrejas/{id}/chats`.
- Anti-sumiço de patrimônio, financeiro, fornecedores e conversas.
- Mídia path-only/soft-fail e Web sem `putFile`.
- Menus/drawers fora de `SelectableRegion`.
- Asset dotenv = `.env.example`; nunca incluir `.env`.
- Nunca gerar AAB Android no Codemagic.
- Não forçar TDLib iOS nativo em produção sem validar archive e aparelho real.

## Aceite

- Deploy técnico `2153`: **APROVADO** para Web, AAB, ZIP iOS, regras, índices, Git, force update e functions (passagem inicial).
- Build IPA/TestFlight: **INCOMPLETO** até o Codemagic concluir a partir do commit `3710feb`.
- Aceite funcional E2E Web/Android/iOS: **INCOMPLETO** até executar DEBUG CHURCH e testes 1–11 nas três plataformas.
- Play: **INCOMPLETO** até upload e processamento externo do AAB `2153`.

## Referências

- Ponto ativo: `PONTO_BASE_MEMORIA_2026-08-02_11.2.305+2153.md`
- Regra Cursor: `.cursor/rules/ponto-base-memoria-11-2-305-2153.mdc`
- Memórias `2145`, `2143`, `2134`, `2122` e anteriores são históricas.


## Atualização Painel Master — 2026-08-13

Foi modernizado o Command Center Master em lutter_app/lib/ui/master_command_center_page.dart com cabeçalho executivo de operação protegida, identificação visual das contas Master Raíhom e Isabelle, melhor hierarquia visual e compatibilidade responsiva por Wrap. Foi criado backup em lutter_app/lib/ui/master_command_center_page.dart.bak-master-modernize.

Também foi corrigido o logout por inatividade em lutter_app/lib/ui/admin_panel_page.dart, removendo o SnackBar inalcançável após redirecionamento e ajustando guards de contexto assíncrono. A análise estática dos quatro arquivos principais (master_command_center_page.dart, dmin_panel_page.dart, pp_session_stability.dart e pp_constants.dart) terminou sem issues.

As duas contas Master continuam preservadas em AppConstants.productMasterUids: o UID de Raíhom Barbosa (O0qRLmLER2hwBFqvlzqSdtAUC3D3) e o UID de Isabelle (PljAYp6FBuWlGNl69Q2vnRp6gZh2). A lógica existente de claims, e-mails e UIDs permanece como fonte de autorização.

**Pendente para a próxima etapa:** validação visual completa no Web, revisão dos módulos de divulgação/Galeria de Clientes, teste do fluxo de publicação manual de igrejas e eventual deploy; ainda não foi alterada a versão nem executado deploy nesta sessão.



## Atualização visão 360° e plano por membros — 2026-08-13

Foi criada e integrada a ficha MasterPlanUsageCard em lutter_app/lib/ui/widgets/master_plan_usage_card.dart, exibida ao abrir uma igreja no detalhe Master. O cartão mostra o plano atual, membros utilizados, limite, saldo restante, barra de progresso e estados profissionais de plano dentro do limite, upgrade recomendado e limite ultrapassado. A regra de alerta visual considera os últimos 5 membros do limite, conforme solicitado.

A ficha foi integrada em lutter_app/lib/ui/widgets/master_church_detail_sheet.dart e mantém o cálculo de membros já existente no snapshot/cache do painel da igreja. O plano usa SaasPlanLimits, com Bronze até 100 membros, Prata até 500 e Ouro ilimitado, sem criar consultas globais novas.

Validação executada sem issues em: master_plan_usage_card.dart, master_church_detail_sheet.dart, members_limit_service.dart, saas_plan_limits.dart e master_command_center_page.dart.

**Pendente:** concluir os alertas persistentes para a igreja e Masters, ampliar a visão 360° com métricas de cartões, eventos, armazenamento e módulos, validar isolamento de tenant e corrigir o erro de exclusão de Visitantes antes de publicar.



## Atualização Cargos, Departamentos e cadastro público de membro — 2026-08-13

A auditoria confirmou que o cadastro público grava no caminho canônico igrejas/{churchId}/membros, envia status pendente para Aprovações e inclui churchId, PUBLIC_SIGNUP, campos de foto canônicos do Storage e miniatura quando o upload é concluído. O fluxo usa ChurchMediaUploadFacade, MemberProfilePhotoPickService e MemberProfilePhotoSaveService antes do envio à callable pública.

Foi corrigido o uso de BuildContext após operações assíncronas em member_profile_photo_pick_service.dart; o arquivo agora passa no lutter analyze sem issues. A auditoria das páginas cargos_page.dart, departments_page.dart, public_member_signup_page.dart e provar_membros_pendentes_page.dart identificou avisos preexistentes não fatais, mas nenhum erro de compilação.

**Próximo passo:** finalizar a modernização visual e funcional de Cargos/Departamentos, validar em execução o upload da foto e a chegada na fila de Aprovações e limpar os avisos estáticos restantes antes do deploy.



## Visão 360° Master e alertas persistentes — 2026-08-13

Foi criado master_church_360_metrics.dart, integrado à ficha master_church_detail_sheet.dart. Ao abrir uma igreja no Painel Master, o sistema exibe cartões por tenant para Membros, Cartões de membro, Eventos, Visitantes, Orações, Patrimônio, Financeiro e Armazenamento. As contagens usam consultas agregadas limitadas ao caminho igrejas/{tenantId}/{subcoleção}; estados indisponíveis aparecem como —, sem inventar números.

Foi criada a persistência MasterPlanAlertPersistence. Quando uma igreja está a até 5 membros do limite, grava o alerta em igrejas/{tenantId}/administrativo/plan_alerts e em master_alerts/plan_{tenantId} para acompanhamento Master. O alerta registra plano, contagem, limite, saldo, severidade, mensagem, status ativo e timestamp. No limite ultrapassado, a severidade passa para locked; em plano ilimitado, não é gerado alerta de limite.

Validação: lutter analyze sem issues em master_church_360_metrics.dart, master_church_detail_sheet.dart e master_plan_usage_card.dart. Ainda não foi feito deploy nem alteração de versão.



## Navegação detalhada da visão 360° — 2026-08-13

Os cartões da visão 360° agora são clicáveis. Foi criada a tela master_module_detail_page.dart, que abre uma listagem detalhada por módulo para Membros, Cartões de membro, Eventos, Visitantes, Orações, Patrimônio e Financeiro, sempre consultando igrejas/{tenantId}/{subcoleção} e limitando a 80 registros. Cada registro exibe título, subtítulo, foto quando disponível e um painel com os campos detalhados.

master_church_detail_sheet.dart agora encaminha o clique do cartão para a tela correspondente. O componente master_church_360_metrics.dart recebeu callback de navegação e foi validado após correções de sintaxe e formatação.

A análise conjunta dos novos arquivos e dos módulos Cargos, Departamentos, Aprovações e cadastro público não encontrou erros de compilação nos novos componentes. Permanecem avisos estáticos preexistentes em arquivos legados, sem impedir a compilação. Ainda não houve deploy nem alteração de versão.



## Agenda moderna e varredura geral — 2026-08-13

O módulo genda_calendario_page.dart foi modernizado para tornar os cards-resumo de Todos, Reuniões, Eventos e Cultos clicáveis. Cada card abre uma tela de preview em grid responsiva com cards coloridos por tipo, data, horário, local e ícone. A tela possui botão de retorno no AppBar e botão de retorno dentro do detalhe rápido. A Agenda foi formatada e validada com lutter analyze: No issues found.

A varredura ampla de lib/ui/pages, lib/ui/widgets, lib/services e lib/core/data foi concluída. Resultado: 0 erros de compilação, 242 warnings e 241 infos legados. Os avisos estão distribuídos em arquivos antigos e não impedem a compilação; devem ser tratados em uma etapa separada, módulo a módulo, para evitar alterações destrutivas. Relatório salvo em lutter_app/analysis_full_2026-08-13.txt.

Ainda não foi feito deploy nem alteração de versão.



## Calendário maior e auditoria Agenda/Escala — 2026-08-13

O calendário mensal recebeu células maiores, números de dia maiores, badge ampliado para contagem de compromissos e proporção mais alta no mobile e mais confortável no Web. A Agenda foi validada sem issues após a implementação de preview em grid: os cards de Todos, Reuniões, Eventos e Cultos são clicáveis, exibem cards coloridos por tipo, data, horário e local, e possuem botão de retorno.

A auditoria do módulo Escala confirmou que schedules_page.dart já contém estruturas de publicação, confirmações, faltas, trocas e relatórios, incluindo cards de instância, filtros de membros e exportação. A próxima correção deve conectar essas estruturas aos indicadores e notificações finais, em vez de duplicar serviços.

Validação direcionada: Agenda e calendário sem erros; o conjunto Agenda/Fornecedores/Escala apresentou apenas warnings/infos legados, sem erro de compilação. Ainda não houve deploy nem alteração de versão.

