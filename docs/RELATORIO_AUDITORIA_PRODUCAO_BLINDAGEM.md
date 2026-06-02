# Relatório de auditoria — Gestão YAHWEH Premium (blindagem produção)

**Data:** 2026-06-01  
**Build referência:** `11.2.295+1728`  
**Pedido:** análise completa **antes** de mudanças massivas — **sem** alterar design, cores, telas, UX ou remover funcionalidades.

Documentos relacionados:
- [PRODUCAO_PREMIUM_MISSAO.md](./PRODUCAO_PREMIUM_MISSAO.md)
- [AUDITORIA_PUBLICACAO_AVISOS_EVENTOS_CHAT.md](./AUDITORIA_PUBLICACAO_AVISOS_CHAT.md)
- [DIAGNOSTIC_CHAT_VS_AVISOS_EVENTOS.md](./DIAGNOSTIC_CHAT_VS_AVISOS_EVENTOS.md)

---

## Resumo executivo

| Área | Veredito | Comentário |
|------|--------|------------|
| Login / sessão / biometria | **Bom** | `PersistentAuthSessionService` — sem Google silencioso no arranque |
| Firestore offline | **Bom (mobile)** / Web diferente | Persistence ON no app nativo; web usa long-polling sem IndexedDB (decisão CT) |
| Publicação avisos/eventos/chat/patrimônio | **Bom** | Firestore-first já no código canónico |
| Dashboard performance | **Parcial** | Existe cache `_panel_cache`; UI ainda tem streams pesados |
| Erros silenciosos (`catch (_)`) | **Risco alto** | Centenas no `lib/` — não adequado para «nenhum erro silenciado» |
| Consultas sem `limit` | **Risco médio** | Vários `.get()` completos em relatórios/admin/PDF |
| Cloud Functions | **Parcial** | Muitas funções; cache painel no servidor — auditoria linha-a-linha pendente |
| Teste de stress 1000/500/50k | **Não executado** | Requer ambiente de carga dedicado |

**Recomendação:** aplicar correções **por módulo e por fase**, com PRs pequenos. **Não** substituir todos os `catch (_) {}` de uma vez com `rethrow` — muitos são recuperação intencional (cache miss, cleanup opcional) e quebrariam UX.

---

## 1. Arquivos já corrigidos (sessões anteriores — não re-auditar à cegas)

| Ficheiro | Alteração |
|----------|-----------|
| `lib/services/feed_media_publish_fast.dart` | Firestore → background upload |
| `lib/services/feed_publish_preflight.dart` | `drainInFlight` máx. ~2s |
| `lib/services/immediate_media_warm.dart` | De ~40s para 2s por defeito |
| `lib/ui/widgets/instagram_mural.dart` | Publicar sem bloquear em warm/upload |
| `lib/ui/pages/events_manager_page.dart` | Agenda `unawaited`; retry Firestore-first |
| `lib/services/patrimonio_publish_service.dart` | Patrimônio Firestore → UI → fotos background |
| `lib/ui/pages/patrimonio_page.dart` | Integração com serviço acima |
| `lib/core/church_publish_flow_log.dart` / `yahweh_flow_log.dart` | Logs diagnóstico |
| `lib/core/yahweh_catch_log.dart` | Padrão log + Crashlytics |
| `lib/services/church_chat_service.dart` | `status`, `fileUrl`, logs chat |
| `lib/services/optimistic_chat_media_upload.dart` | Stub → upload → sent |
| `lib/services/panel_dashboard_snapshot_service.dart` | Leitura 1 doc + alias `dashboard_stats` |
| `.cursor/rules/avisos-eventos-publicacao-sincrona.mdc` | Alinhado Firestore-first |
| `.cursor/rules/gestao-yahweh-producao-premium.mdc` | Regra missão |
| `docs/DIAGNOSTIC_CHAT_VS_AVISOS_EVENTOS.md` | Secção publicação atualizada |

---

## 2. Fase 1 — Erros silenciosos (`catch`)

### Contagem (aproximada)

| Padrão | Ocorrências em `flutter_app/lib` |
|--------|----------------------------------|
| `catch (_) {}` | **~200+ ficheiros**, somando **centenas** de blocos |
| `catch (e) {}` vazio | **0** encontrados (grep) |

### Ficheiros críticos (publicação / login / cartões)

| Ficheiro | `catch (_)` | Risco |
|----------|-------------|-------|
| `church_chat_service.dart` | **25** | Médio — muitos são índice local / cleanup |
| `member_card_page.dart` | **53** | **Alto** — carteirinha PDF/WhatsApp |
| `church_letters_page.dart` | **11** | **Alto** — cartas transferência |
| `events_manager_page.dart` | **26** | Médio — mistura publish + UI |
| `instagram_mural.dart` | **12** | Médio |
| `patrimonio_page.dart` | **12** | Médio |
| `login_page.dart` | **7** | Médio |
| `auth_gate.dart` | **20** | Médio |
| `igreja_dashboard_moderno.dart` | **29** | Médio — painel |
| `main.dart` | **11** | Baixo — bootstrap |

### Erros encontrados (tipo)

1. **Silenciamento genérico** — falhas de rede/cache tratadas como «ok» sem log.
2. **Mistura de intenções** — mesmo ficheiro tem catches legítimos (evitar crash) e catches que escondem falha de gravação.
3. **Pedido «sempre rethrow»** — **não aplicável globalmente** sem regressões (ex.: `readOnce` cache miss, `evictFromCache`, prefs).

### Correção recomendada (faseada)

1. **Camada A (obrigatória):** `YahwehCatchLog.log` em `_save`, `publish`, `sendMessage`, `signOut`, PDF cartão/carta — **sem** rethrow se UX deve continuar.
2. **Camada B:** substituir `catch (_)` por log + fallback explícito documentado.
3. **Camada C:** só `rethrow` onde o caller já mostra erro ao utilizador.

**Não corrigido nesta entrega** — aguardando aprovação por módulo.

---

## 3. Fase 2 — Login definitivo

### Estado: **alinhado ao pedido**

| Requisito | Estado | Evidência |
|-----------|--------|-----------|
| `FirebaseAuth.instance.currentUser` | OK | `PersistentAuthSessionService.currentPersistedUser()` |
| Sem `signInSilently` no arranque | OK | Comentário + implementação em `persistent_auth_session_service.dart` |
| Sem `tryExpressLogin` no arranque | OK | `login_page.dart` usa `_schedulePersistentAutoLoginOnce` → `PersistentAuthSessionService` |
| Biometria se ativa | OK | `canProceedToDashboard()` → `BiometricService` |
| Sem biometria → painel | OK | `if (!enabled) return true` |
| Trocar conta → signOut completo | **Parcial** | `ChurchSignOutNavigation.signOutForAccountSwitch()` → `prepareChurchAccountSwitch` + `appGoogleSignOutForAccountPicker()` + `FirebaseAuth.signOut` |

### Exceções (não são «login ao abrir app»)

| Local | Uso |
|-------|-----|
| `express_login_service.dart` | Botão «login expresso» / renovação plano |
| `express_renew_gate_page.dart` | Fluxo renovação |
| `gestor_oauth_onboarding_service.dart` | Botão Google manual |

### Riscos residuais

- `login_page.dart` ainda tem `_signOutFirebaseIfLoggedIn()` em ramos de erro OAuth — não é arranque automático.
- Web: persistência Auth `LOCAL` em `main.dart` — OK.

---

## 4. Fase 3 — Firestore offline

| Plataforma | `persistenceEnabled` | Ficheiro |
|------------|---------------------|----------|
| Android/iOS | **true** + cache ilimitado | `lib/core/firestore_app_config.dart` |
| Web | **false** + long-polling | Idem (Controle Total — evita IndexedDB/login instável) |

**Conclusão:** pedido «ativar persistence globalmente» **já cumprido no mobile**. Web é **intencionalmente diferente** — mudar exige teste de login Google/Apple na web.

---

## 5. Fase 4 — Consultas sem limite

### Infraestrutura existente

- `ChurchTenantListLimits.defaultPageSize = 20`
- `ChurchDataQuery.recentOrdered` / `getRecentPage` / `watchRecentPage`

### Exemplos de violação (amostra)

| Módulo | Ficheiro | Problema |
|--------|----------|----------|
| Membros | `members_page.dart` | `collection('igrejas').get()` (admin multi-igreja) |
| Patrimônio | `patrimonio_page.dart` | `membros.get()` para lista responsáveis; export PDF `orderBy('nome').get()` **coleção inteira** |
| Dashboard | `igreja_dashboard_moderno.dart` | Vários `.snapshots()` em membros/eventos |
| Escalas | `schedules_page.dart` | Muitos `catch (_)` + streams |
| Financeiro | `finance_page.dart` | Streams + catches |

**Paginação:** implementada no mural/chat em parte; **não** uniformizada em todos os módulos.

---

## 6. Fase 5 — Dashboard

| Pedido | Realidade no código |
|--------|---------------------|
| Coleção `dashboard_stats` | Cliente lê opcionalmente `igrejas/{id}/dashboard_stats/summary` |
| Canónico actual | `igrejas/{id}/_panel_cache/dashboard_summary` (1 documento) |
| CF agregação | `functions/src/panelDashboardCache.ts` — recompute servidor (scan até 800 membros) |
| UI sem contagem RT | **Parcial** — `igreja_dashboard_moderno.dart` ainda documenta «Membros em tempo real via snapshots()» |

**Gargalo:** painel pode disparar streams paralelos mesmo com cache quente.

**Melhoria pendente:** priorizar só `PanelDashboardSnapshotService.readOnce` / `watch` no topo; degradar streams a botão «actualizar».

---

## 7. Fases 6–7 — Eventos e Avisos

### Fluxo pedido vs código

```
Pedido:  Firestore → sucesso → fecha → upload → URL → push
Código:  FeedMediaPublishFast + MuralFastPublishService (OK)
```

| Item | Estado |
|------|--------|
| Firestore primeiro | OK |
| Fecha modal após stub | OK (`instagram_mural`, `events_manager_page`) |
| Upload background | OK |
| Push após `published` | OK (CF `pushNovoConteudo` — não bloqueia cliente) |
| Upload → Firestore legado | **Removido** no retry de eventos; regra Cursor antiga corrigida |
| Anexo foto ao editar | `ImmediateFeedPhotoAttach` — upload opcional ao anexar (não bloqueia >2s) |

---

## 8. Fase 8 — Chat Igreja

| Item | Estado |
|------|--------|
| Path `chats/{chatId}/messages/{messageId}` | OK — `church_chat_firestore_map.dart` |
| Tipos text/image/pdf/audio/video | OK — `ChurchChatService` + `optimistic_chat_media_upload` |
| Status sending/sent | OK — campos `status` + `deliveryStatus` |
| delivered/read | **Parcial** — lógica DM/recibos existe; validar grupos |
| Arquivo: stub → upload → fileUrl | OK |
| Não bloquear UI | OK — `ChurchChatInstantSendService.enqueue*` |

**Risco:** 25× `catch (_)` em `church_chat_service.dart` podem mascarar falhas de entrega.

---

## 9. Fase 9 — Storage

| Item | Estado |
|------|--------|
| Regras Storage (imagens, vídeo, PDF, áudio) | OK (conforme análise utilizador) |
| Logs UPLOAD START/OK/ERROR | OK em mural + chat + `YahwehFlowLog` |
| `UnifiedUploadService` | OK — paridade chat/feed |
| `FirebaseUploadPolicy.firestorePendingQueueEnabled = false` | OK — sem fila fantasma |

---

## 10. Fase 10 — Membros

| Item | Estado |
|------|--------|
| Lista rápida | OK com `_panel_cache/members_directory` |
| Cadastro/edição/foto | Funcional; vários `catch (_)` em `members_page.dart` (**28**) |
| Gravação garantida | **Validar** em rede instável — usar logs `YahwehFlowLog.membros*` (ainda não ligado) |

---

## 11. Fase 11 — Carteirinha

| Item | Estado |
|------|--------|
| PDF + Storage + Firestore + partilha | Implementado em `member_card_page.dart` |
| Erros silenciosos | **53× `catch (_)`** — **principal risco** deste módulo |
| Logs globais | **Pendente** ligar `YahwehFlowLog.cartaoStart/Success` |

---

## 12. Fase 12 — Cartas de transferência

| Item | Estado |
|------|--------|
| `church_letters_page.dart` | PDF + partilha |
| `catch (_)` | **11** — auditar antes de mudar |
| Logs | Pendente `YahwehFlowLog.carta*` |

---

## 13. Fase 13 — Patrimônio

| Item | Estado |
|------|--------|
| Salvar primeiro, upload depois | **OK** (`PatrimonioPublishService`, build 1728) |
| `photoUploadState` uploading/uploaded/error | OK |
| Compressão | `PatrimonioMediaUpload` / pipeline imagem |
| Export PDF lista completa | Ainda lê **toda** a coleção — aceitável para relatório, viola regra 4 se usado na UI principal |

---

## 14. Fase 14 — Relatórios

| Item | Estado |
|------|--------|
| Background + progresso | Parcial — alguns PDFs async (`cert_pdf_worker`, património export) |
| `relatorios_page.dart` | Poucos catches; validar geração pesada |

---

## 15. Fase 15 — Imagens

| Pedido | Realidade |
|--------|-----------|
| `CachedNetworkImage` | Amplamente usado |
| `Image.network` | **~3 usos** no projeto (incl. fallback interno em `safe_network_image.dart`) |
| Regra projeto | Web + Firebase Storage → **`SafeNetworkImage`** (CORS) — **manter** |

**Conclusão:** pedido «proibir Image.network» **quase cumprido**; não forçar troca na web Storage.

---

## 16. Fase 16 — Streams / dispose

| Exemplo | Estado |
|---------|--------|
| `church_chat_thread_page.dart` | **OK** — `dispose` cancela `_prefsSub`, `_deptSub`, timers |
| `igreja_dashboard_moderno.dart` | **Auditar** — múltiplos streams; verificar `dispose` em cada StatefulWidget |
| `patrimonio_page.dart` | `snapshots().listen` — verificar cancel no dispose |

**Pendente:** varredura automática `listen(` sem `cancel` — não executada nesta auditoria.

---

## 17. Fase 17 — Cloud Functions

- **43+** ficheiros TS em `functions/src/`
- Cache painel: `panelDashboardCache.ts`, `membersDirectoryCache.ts`
- Push: `pushNovoConteudo.ts`, `churchChatNotify.ts`
- Migração: `migrateTenantFirestoreCollections.ts`

**Auditoria «return em todos os fluxos»:** **não concluída** linha-a-linha nesta entrega.

**Observação:** funções de cache fazem scan grande **no servidor** (aceitável); cliente deve ler 1 doc.

---

## 18. Fase 18 — Monitoramento

| Serviço | Estado |
|---------|--------|
| Crashlytics | OK — `main.dart` release |
| Analytics | OK — `YahwehObservability` / `AnalyticsService` |
| Performance | OK — `PerformanceService` / `FirebasePerformance` |
| Eventos por módulo | **Parcial** — publicação com logs `print`; falta uniformizar login/upload/relatórios |

---

## 19. Fase 19 — Teste de stress

| Cenário | Executado |
|---------|-----------|
| 1000 membros / 500 eventos / 500 avisos / 100 grupos / 50k mensagens | **Não** |

**Recomendação:** Firebase Emulator Suite + script seed; ou tenant de staging — fora do âmbito desta auditoria estática.

---

## 20. Testes executados nesta auditoria

| Teste | Resultado |
|-------|-----------|
| `dart analyze` (ficheiros publish/log) | Sem `error` nos ficheiros tocados nas sessões 1726–1728 |
| Teste manual stress | Não |
| Teste E2E automatizado | Não |

---

## 21. Gargalos eliminados (já no código)

1. `drainInFlight` 40s → 2s (publicar aviso/evento).
2. Retry eventos «upload → set» → `FeedMediaPublishService.publish`.
3. Agenda eventos após `Navigator.pop` (`unawaited`).
4. Patrimônio bloqueava no upload — agora background.
5. Regra Cursor «publicação síncrona» contradizia o código — corrigida.

---

## 22. Melhorias implementadas vs pendentes

### Implementadas (código actual)

- Firestore-first: avisos, eventos, chat, patrimônio (fotos).
- Login persistente sem OAuth silencioso no cold start.
- Logs: `YahwehFlowLog`, `ChurchPublishFlowLog`, `YahwehCatchLog`.
- Dashboard: leitura 1 doc cache (+ alias `dashboard_stats`).
- Offline Firestore mobile.

### Pendentes (prioridade sugerida)

| P | Item | Esforço |
|---|------|---------|
| P0 | Carteirinha: logs + auditar 53 catches no fluxo PDF | Médio |
| P0 | Dashboard: reduzir streams RT em `igreja_dashboard_moderno` | Médio |
| P1 | Membros: garantir lista só cache+page 20 | Médio |
| P1 | Cartas: logs + catches no fluxo gravação | Baixo |
| P1 | `church_chat_service`: logs em falhas de envio (sem rethrow global) | Médio |
| P2 | Substituir `.get()` sem limit em exports PDF (paginar ou CF) | Alto |
| P2 | Cloud Functions: checklist return/timeout | Alto |
| P3 | Teste stress staging | Alto |
| P3 | `catch (_)` restantes (~200 ficheiros) — **por módulo** | Muito alto |

---

## 23. Mapa «pronto para produção» vs pedido final

| Critério obrigatório | Status |
|---------------------|--------|
| Login automático | Sim |
| Biometria | Sim (nativo) |
| Dashboard rápido | Parcial |
| Membros rápidos | Parcial |
| Eventos gravando | Sim (fluxo canónico) |
| Avisos gravando | Sim |
| Chat estilo WhatsApp | Parcial (entrega/leitura validar) |
| Fotos/vídeos/PDF | Sim (Storage OK; UI depende de publishState) |
| Patrimônio | Sim (build 1728+) |
| Carteirinhas / cartas | Funcional — **risco erros silenciosos** |
| Relatórios | Parcial |
| Android/iOS/Web rápidos | Parcial |
| Sem loading infinito | Melhorado; não garantido 100% |
| Sem erros silenciosos | **Não** — requer fase 1 gradual |
| Sistema blindado | **Em progresso** — base OK, hardening incremental |

---

## 24. Próximo passo recomendado

1. **Aprovar** este relatório e escolher **um** módulo para onda 1 de código: **Carteirinha (P0)** ou **Dashboard streams (P0)**.
2. **Não** executar replace global `catch → rethrow`.
3. Opcional: deploy build 1728 — `.\scripts\deploy_web_hosting.ps1`.

---

*Relatório gerado por auditoria estática do repositório. Nenhuma alteração massiva de código foi aplicada nesta entrega.*
