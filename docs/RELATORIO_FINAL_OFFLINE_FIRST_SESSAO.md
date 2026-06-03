# Relatório final — Offline-first, sessão permanente e performance (Controle Total)

Data: 2026-06-02

## Pré-requisitos bloqueantes (estado)

| Erro | Estado | Ação |
|------|--------|------|
| `core/no-app` | Corrigido no cliente | `ensureFirebaseCore()` + init único em `FirebaseBootstrap` |
| `permission-denied` (chat) | Regras corrigidas (`chats` vs `chat_threads`) | `.\scripts\deploy_firebase_rules.ps1` |

**Nota:** Sessão «nunca expirar» não é garantia absoluta (Firebase pode invalidar token). Comportamento: manter `currentUser` enquanto válido; relogin só quando necessário ou em **Trocar conta**.

---

## Arquivos alterados (esta missão + base anterior)

### Firebase / bootstrap
- `flutter_app/lib/core/firebase/firebase_bootstrap.dart`
- `flutter_app/lib/core/firebase_bootstrap.dart` — `ensureFirebaseCore()`
- `flutter_app/lib/core/firebase_bootstrap_service.dart`
- `flutter_app/lib/core/firestore_app_config.dart` — persistência mobile
- `flutter_app/lib/main.dart` — `Persistence.LOCAL`, `configureFirestoreForOfflineAndSpeed`, rota

### Sessão permanente
- `flutter_app/lib/services/persistent_auth_session_service.dart`
- `flutter_app/lib/services/app_shell_session_cache.dart`
- `flutter_app/lib/services/church_sign_out_navigation.dart` — logout só com troca de conta
- `flutter_app/lib/services/login_preferences.dart` — `prepareChurchAccountSwitch` + limpa resume
- `flutter_app/lib/services/app_google_sign_in.dart` — `disconnect` só na troca

### Offline-first / sincronização
- `flutter_app/lib/core/app_finalize_bootstrap.dart` — filas ao arranque/resume
- `flutter_app/lib/services/app_connectivity_service.dart` — ONLINE/OFFLINE/SYNC, sem `reconnect` pesado
- `flutter_app/lib/services/storage_upload_persistence_service.dart` (existente)
- `flutter_app/lib/services/mural_publish_outbox_service.dart` (existente)
- `flutter_app/lib/services/church_chat_media_outbox_service.dart` (existente)

### Retornar onde parou
- `flutter_app/lib/services/app_resume_state_service.dart` **(novo)**
- `flutter_app/lib/ui/igreja_clean_shell.dart` — aba + tenant
- `flutter_app/lib/ui/pages/church_chat_thread_page.dart` — thread ativa

### Performance / limites
- `flutter_app/lib/core/yahweh_performance_v4.dart`
- `flutter_app/lib/ui/pages/members_page.dart` — 20/página
- `flutter_app/lib/ui/admin_igrejas_tab.dart` — master limit 25 + resumo
- `flutter_app/lib/ui/pages/patrimonio_page.dart` — limit 20
- `flutter_app/lib/services/church_chat_service.dart` — 30 msgs, threads limitados, `local` offline

### Publicação directa (CT)
- `flutter_app/lib/services/feed_publish_preflight.dart`
- `flutter_app/lib/services/feed_media_publish_fast.dart`
- `flutter_app/lib/services/mural_fast_publish_service.dart`
- `flutter_app/lib/services/patrimonio_publish_service.dart`
- `flutter_app/lib/services/finance_comprovante_publish_service.dart`
- `flutter_app/lib/services/member_profile_photo_update_service.dart`
- `flutter_app/lib/services/church_chat_instant_send_service.dart`

### Dashboard agregado
- `flutter_app/lib/services/church_tenant_dashboard_doc_service.dart`
- `flutter_app/lib/services/master_dashboard_cache_service.dart`

### Regras
- `firestore.rules` — paths `igrejas/.../chats/...`

### Logs
- `flutter_app/lib/core/yahweh_flow_log.dart` — START, SUCCESS, ERROR, OFFLINE, ONLINE, SYNC
- `flutter_app/lib/core/yahweh_catch_log.dart`

### Documentação
- `docs/PADRONIZACAO_PERFORMANCE_CONTROLE_TOTAL.md`
- `docs/REFACTOR_PRODUCAO_CONTROLE_TOTAL.md`
- `docs/FIREBASE_PADRAO_CONTROLE_TOTAL.md`
- `docs/RELATORIO_ERRO_FIREBASE_CHAT.md`

---

## Comportamento implementado

### Sessão
- Cold start: `PersistentAuthSessionService` + `FirebaseAuth.currentUser` (sem `signInSilently` no arranque).
- Biometria: só se activa; senão abre directo.
- Logout: só **Configurações → Trocar conta** (`signOutForAccountSwitch`).

### Offline (mobile)
- `persistenceEnabled: true`, cache ilimitado.
- Escritas Firestore ficam locais e sincronizam quando a rede volta.
- Chat texto offline: `deliveryStatus: local` → recovery envia quando online.

### Sincronização automática
- `AppConnectivityService`: ao voltar online → `enableNetwork` + `AppFinalizeBootstrap.onAppResume` + filas Storage/mural/chat.

### Cache primeiro
- Dashboard: `dashboard_stats/summary` (cache Firestore → servidor).
- Master: `master_dashboard_summary` + prefs locais.

---

## Testes executados

```powershell
cd flutter_app
dart analyze --no-fatal-warnings lib/services/app_resume_state_service.dart lib/services/app_connectivity_service.dart lib/services/persistent_auth_session_service.dart lib/core/yahweh_flow_log.dart lib/services/church_chat_service.dart
```

Deploy recomendado:

```powershell
.\scripts\deploy_firebase_rules.ps1
.\scripts\deploy_web_hosting.ps1
```

### Teste manual (checklist)

1. Login → fechar app → reabrir → entra no painel sem login (biometria se activa).
2. Abrir Chat → thread → fechar app → reabrir → mesma aba do painel (shell index).
3. Modo avião → enviar texto no chat → mensagem aparece (`local`) → rede → sincroniza.
4. Publicar aviso offline (mobile) → sucesso na UI → online → foto sincroniza.
5. Configurações → Trocar conta → pede login de novo.
6. Master → lista ≤ 25 igrejas; KPIs do resumo agregado.

---

## Próxima onda (sem mudar layout)

- Reabrir thread de chat automaticamente no hub (ler `AppResumeStateService.readChatThread`).
- Eventos: query só do mês visível.
- Financeiro: aba resumo vs detalhe lazy.
- Auditar `limit(500)` restantes em exportações de membros.
