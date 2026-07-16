# Agentes Cursor — Gestão YAHWEH

Este repositório usa **regras persistentes** em `.cursor/rules/` e o manual **`prompt_mestre_cursor.md`**.

**Memória única (igual Controle Total):** `PONTO_BASE_MEMORIA_2026-07-15_11.2.305+2106.md` + regra `.cursor/rules/ponto-base-memoria-11-2-305-2106.mdc`. Não criar segunda memória; ao atualizar release, substituir este ficheiro e apagar o anterior.

## Comportamento esperado do agente

1. Consultar primeiro o **ponto base de memória** (versão atual, painel igreja/master, regras, funções, índices, artefactos).
2. Ler e seguir **`prompt_mestre_cursor.md`** (arquitetura offline-first, Controle Total / WhatsApp, §0–22).
3. Aplicar sempre a regra **`prompt-mestre-arquitetura.mdc`** (`alwaysApply: true`).
4. Evoluir serviços existentes — **não** criar duplicatas (`regra-mestra-projeto.mdc`).
5. Responder em **português**; alterações **focadas** e mínimas.
6. **Build/deploy só com pedido explícito ao final** — não publicar nem rodar `deploy_completo.ps1` / hosting / regras por iniciativa própria (`sem-deploy-sem-pedido-explicito.mdc`, `deploy-so-ao-final.mdc`).

## Referência rápida

| Tema | Ficheiros |
|------|-----------|
| Offline-first | `offline_first_coordinator.dart`, `firestore_app_config.dart`, `optimistic_firestore_write.dart`, `tenant_offline_write.dart` |
| Auth + biometria | `auth_service.dart`, `auth_gate.dart`, `biometric_lock_page.dart` |
| Upload + fila BG | `storage_service.dart`, `background_upload_worker.dart`, `storage_upload_persistence_service.dart`, `mural_publish_outbox_service.dart` |
| Vídeo eventos | `media_video_compress_quality.dart`, `media_service.dart` (`prepareEventVideoForUpload`) |
| Dashboard stats | `church_tenant_dashboard_doc_service.dart`, `dashboard_stats_counter_service.dart` |
| Imagens UI + retry | `safe_network_image.dart`, `unavailable_media_widget.dart` |
| Chat paginação + retenção | `church_chat_service.dart` (20 msgs), `church_chat_storage_retention_service.dart` |
| Paginação listas | `yahweh_performance_v4.dart` (pageSize 20), `lazy_firestore_list_controller.dart` |
| Conflitos offline LWW | `firestore_last_write_wins.dart` |
| Partilha WhatsApp | `yahweh_share_service.dart`, `yahweh_share_button.dart` |
| Web uploads | `web_safe_media.dart`, `upload_bytes_core.dart` |
| Regras Firebase | `firestore.rules`, `storage.rules`, `FIREBASE_RULES_SECURITY.txt` |
| Deploy regras (GCP, autorizado) | `scripts/regras_gcp_automatico_forcado.ps1` |
| Deploy regras (detalhe) | `scripts/deploy_firebase_rules.ps1` |
| Deploy web | `scripts/deploy_web_hosting.ps1` |
| gcloud (auto) | `scripts/install_google_cloud_sdk.ps1` via `ensure_gestao_yahweh_toolchain_path.ps1` |
| GCP regras REST | `scripts/firebase_rules_gcp_publish.cjs` |

## Toolchain (antes de deploy)

```powershell
. .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
```

Instala **gcloud** automaticamente se faltar (winget / zip). Nao pedir instalacao manual.

## Regras Firebase (autorizado)

```powershell
.\scripts\regras_gcp_automatico_forcado.ps1
```

Publica em **firebaserules.googleapis.com** (nao no banco Firestore): preflight + `firebase_rules_gcp_publish.cjs` + `-ForcePublish`. Inclui `ensure_functions_node_for_gcp.ps1` (googleapis para IAM). Sem pedir confirmacao extra se o utilizador autorizou.

**Copiar para outros projetos:** `docs/GCP_TOOLCHAIN_COPIAR_OUTROS_PROJETOS.md` + scripts listados + `.cursor/rules/gcloud-toolchain-automatico.mdc` + `prompt_mestre_cursor.md`.

## Comando Composer (opcional)

Referencie `@prompt_mestre_cursor.md` ou peça implementação «alinhada ao manual arquitetural».

As regras `.mdc` com `alwaysApply: true` já carregam o essencial — **não é obrigatório** colar o comando mestre em cada sessão.
