# Agentes Cursor — Gestão YAHWEH

Este repositório usa **regras persistentes** em `.cursor/rules/` e o manual **`prompt_mestre_cursor.md`**.

## Comportamento esperado do agente

1. Ler e seguir **`prompt_mestre_cursor.md`** (arquitetura offline-first, Controle Total / WhatsApp, §0–22).
2. Aplicar sempre a regra **`prompt-mestre-arquitetura.mdc`** (`alwaysApply: true`).
3. Evoluir serviços existentes — **não** criar duplicatas (`regra-mestra-projeto.mdc`).
4. Responder em **português**; alterações **focadas** e mínimas.

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
| Deploy regras | `scripts/deploy_firebase_rules.ps1` |
| Deploy web | `scripts/deploy_web_hosting.ps1` |

## Comando Composer (opcional)

Referencie `@prompt_mestre_cursor.md` ou peça implementação «alinhada ao manual arquitetural».

As regras `.mdc` com `alwaysApply: true` já carregam o essencial — **não é obrigatório** colar o comando mestre em cada sessão.
