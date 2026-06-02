# Missão — Gestão YAHWEH Produção Premium

**Objetivo:** sistema rápido, estável e confiável **sem** alterar design, layout ou telas.

Regra Cursor: `.cursor/rules/gestao-yahweh-producao-premium.mdc`

---

## Estado por regra (2026-06-02, build 1731+)

| # | Regra | Estado | Notas |
|---|--------|--------|--------|
| 1 | Listas `limit(20)` + paginação | Parcial | `ChurchDataQuery` + `ChurchTenantListLimits`; auditar ecrãs legados (`patrimonio` export PDF ainda lê coleção inteira — relatório) |
| 2 | Cache local primeiro | Parcial | Firestore persistence mobile; `_panel_cache`, `members_directory`; Hive não global |
| 3 | Firestore → UI → upload | **Avisos/Eventos/Chat/Patrimônio/Foto membro/Financeiro comprovante** | `FeedMediaPublishFast`, `PatrimonioPublishService`, `MemberProfilePhotoUpdateService`, `FinanceComprovantePublishService` |
| 4 | Upload `uploading/uploaded/error` | Parcial | Patrimônio: `photoUploadState`; mural: `publishState` |
| 5 | Chat `chats/.../messages` | OK | `ChurchChatService` + status `sending/sent` |
| 6 | Foto chat stub primeiro | OK | `optimistic_chat_media_upload.dart` |
| 7–8 | Aviso/evento Firestore primeiro | OK | Ver `AUDITORIA_PUBLICACAO_AVISOS_EVENTOS_CHAT.md` |
| 9 | Logs START/SUCCESS/ERROR | OK | `YahwehFlowLog`, `ChurchPublishFlowLog` |
| 10 | `catch` com log | Em curso | `YahwehCatchLog`; substituir silenciosos incrementalmente |
| 11 | Crashlytics/Analytics/Perf | OK | `YahwehObservability`, `main.dart` |
| 12 | CachedNetworkImage | Parcial | Web Storage: `SafeNetworkImage` (regra projeto) |
| 13 | dispose streams | Auditar | Por módulo |
| 14 | Dashboard 1 doc | OK | `_panel_cache/dashboard_summary`; leitura opcional `dashboard_stats/summary` |
| 15 | Cartão PDF | **OK onda 2** | Firestore assinatura antes do PDF; `YahwehFlowLog` CARTAO |
| 16 | Carta transferência | **OK onda 2** | Histórico Firestore antes de gerar PDF; `YahwehFlowLog` CARTA |
| 17 | Patrimônio Firestore primeiro | **OK** | `PatrimonioPublishService` |
| 18 | Relatórios background | **Parcial+** | PDF em UI com log; membros `ChurchDataQuery` limitado |
| 19 | Offline Firestore | OK mobile / web long-polling | `firestore_app_config.dart` |
| 20 | Fluxos duplicados Auth/feed | Parcial | login consolidado; evitar novo `Firebase.instance` |

---

## Metas de tempo (alvo)

| Módulo | Meta | Mecanismo principal |
|--------|------|---------------------|
| Dashboard | < 1s | `PanelDashboardSnapshotService.readOnce` (cache) |
| Membros | < 1s | `_panel_cache/members_directory` |
| Eventos/Avisos | < 1s | Firestore stub + lista `limit(20)` |
| Chat | instantâneo | stub + stream mensagens |
| Patrimônio | < 2s | Firestore primeiro + fotos background |
| Relatórios | < 3s | gerar em background |

---

## Ficheiros base (novos)

- `lib/core/yahweh_flow_log.dart`
- `lib/core/yahweh_catch_log.dart`
- `lib/services/patrimonio_publish_service.dart`
- `lib/services/church_data_query.dart`
- `lib/services/church_data_service.dart`

---

## Onda 2 concluída (1731)

- **Membros:** foto perfil Firestore-first (`scheduleBackgroundPhotoUpload`).
- **Financeiro:** `FinanceComprovantePublishService` — lançamento salvo; comprovante em background.
- **Cartão:** assinatura gravada no membro antes do export PDF.
- **Cartas:** `_persistHistorico` antes de `buildChurchTransferLetterPdf`.
- **Relatórios:** query membros limitada + logs RELATORIO.
- **Patrimônio:** reforço `uploading` no início do batch de fotos.

## Próximas ondas (sem mudar UI)

1. Auditar `.snapshots()` sem `limit` nos restantes ecrãs.
2. Relatórios financeiro/patrimônio/eventos: mesma query limitada em todos os sub-relatórios.
3. Substituir `catch (_) {}` restantes no caminho de gravação.

---

## Deploy

Após alterações de código: `.\scripts\deploy_web_hosting.ps1` ou `.\scripts\deploy_completo.ps1` conforme pedido.
