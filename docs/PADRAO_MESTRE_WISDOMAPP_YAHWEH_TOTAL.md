# Padrão mestre WISDOMAPP → Gestão YAHWEH (sistema total)

**Objetivo:** deixar o Gestão YAHWEH **tão rápido quanto o WISDOMAPP** em **Web, Android e iOS** — abrindo instantâneo, gravando sempre, upload de fotos/vídeos/áudio estável, sites públicos leves.

**Projeto alvo:** `C:\gestao_yahweh_premium_final\flutter_app`  
**Referência de performance:** `C:\WISDOMAPP` (versão 10.04+, cache-first, FirestoreWebGuard, CF para writes pesados)

**Docs relacionados (já existentes — não duplicar, complementar):**
- `docs/MAPEAMENTO_PADRAO_FIREBASE_CT_WISDOM_YAHWEH.md`
- `docs/ARCHITECTURE_PERFORMANCE_V4.md`
- `docs/ARCHITECTURE_INSTANT_UX.md`
- `docs/instant-media-performance.md`
- `docs/PADRONIZACAO_MULTIPLATAFORMA.md`
- `docs/CAMADA_DADOS_ESTABILIDADE.md`

---

## 1. Resultado que o usuário deve sentir

| Antes (lento) | Depois (padrão WISDOMAPP) |
|---------------|---------------------------|
| Tela branca / spinner longo | Conteúdo do cache em **< 200 ms** |
| Lista “piscando” ao rolar | Último dado visível até refresh terminar |
| Gravação falha na Web | Write com retry leve, **sem** `terminate()` |
| Upload trava o app | Storage direto + barra de progresso + fila offline |
| 10 módulos abertos = travamento | Shell lazy: só **2 módulos** na memória |
| Site público lento | Feed pré-processado em `_performance_cache` |

---

## 2. Arquitetura em 4 camadas (copiar do WISDOMAPP)

```
┌─────────────────────────────────────────────────────────────┐
│  UI (telas) — Future/get + estado local, NÃO Firestore cru  │
├─────────────────────────────────────────────────────────────┤
│  ModuleCacheService (ChangeNotifier) — RAM + SharedPrefs    │
│  + Hive (Android/iOS) | SharedPreferences (Web)             │
├─────────────────────────────────────────────────────────────┤
│  ChurchRepository / LoadService — gateway único por módulo  │
├─────────────────────────────────────────────────────────────┤
│  Firestore (get cache-first) | Storage (bytes) | CF (admin) │
└─────────────────────────────────────────────────────────────┘
```

### Regras de ouro (não negociáveis)

1. **Nunca** chamar `FirebaseFirestore.instance.terminate()` em fluxo normal (login, toggle, gravar, upload).
2. **Web:** `runFirestoreOpSafe()` / `prepareForPublishWrite()` antes de gravar — ver `WISDOMAPP/lib/utils/firestore_web_guard.dart`.
3. **Leitura:** cache em disco → Firestore `Source.cache` → server (SWR: mostrar cache, atualizar em background).
4. **Gravação com mídia:** ordem **Storage → URL → Firestore** (strict publish).
5. **Listas:** paginação 20 itens; **proibir** `StreamBuilder` em listas longas na Web.
6. **Mídia grande:** cliente sobe Storage; metadados sensíveis podem ir por Cloud Function (Admin SDK).
7. **Shell:** lazy modules (máx. 2 retidos) — espelhar `WISDOMAPP/lib/screens/home_shell.dart`.

---

## 3. Template de cache por módulo (copiar/adaptar)

**Origem WISDOMAPP:** `lib/services/course_videos_cache_service.dart`

**Destino YAHWEH (criar um por módulo):**  
`flutter_app/lib/core/cache/modules/{modulo}_cache_service.dart`

```dart
/// Padrão cache-first — igual CourseVideosCacheService (WISDOMAPP).
class MembrosCacheService extends ChangeNotifier {
  static final instance = MembrosCacheService._();
  MembrosCacheService._();

  static const _kDocsJson = 'yahweh_membros_v1_{churchId}';
  List<MembroDoc> _docs = const [];
  bool _refreshing = false;
  Future<void>? _inFlight;
  String _signature = '';

  bool get showInitialLoading => _refreshing && _docs.isEmpty;

  Future<void> ensureLoaded(String churchId, {bool forceServer = false}) {
    if (_inFlight != null && !forceServer) return _inFlight!;
    _inFlight = _load(churchId, forceServer: forceServer).whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  void _notifyIfChanged(String sig) {
    if (sig == _signature && !_refreshing) return;
    _signature = sig;
    notifyListeners();
  }

  // 1) warmUp SharedPreferences
  // 2) notify se tem cache
  // 3) _refreshing = true só se vazio
  // 4) Firestore get(cache) then server
  // 5) persist + _notifyIfChanged
}
```

**Bootstrap no `main.dart` (YAHWEH):** aquecer só o essencial antes do 1º frame; resto `unawaited` com timeout 800 ms — ver `WISDOMAPP/lib/main.dart` linhas ~262–307.

---

## 4. Matriz completa — todos os módulos

Tenant: `igrejas/{churchId}/`

| Módulo | Firestore | Load service atual | Cache service (criar) | Upload Storage | Offline queue | Prioridade |
|--------|-----------|-------------------|----------------------|----------------|---------------|------------|
| **Membros** | `membros/` | `church_members_load_service.dart` | `membros_cache_service.dart` | `membros/{id}/foto_*` | ✅ expandir | P0 |
| **Cadastro igreja** | doc raiz | `church_cadastro_load_service.dart` | `igreja_root_cache_service.dart` | `configuracoes/logo_*` | ✅ | P0 |
| **Cartão membro** | `cartoes/` | (via repository) | `cartoes_cache_service.dart` | `cartoes/{id}/` | 🔲 adicionar | P1 |
| **Cargos** | `cargos/` | `church_cargos_load_service.dart` | `cargos_cache_service.dart` | — | 🔲 adicionar | P1 |
| **Departamentos** | `departamentos/` | `church_departments_load_service.dart` | `departamentos_cache_service.dart` | — | 🔲 adicionar | P1 |
| **Chat igreja** | `chats/{id}/messages/` | `church_chat_service.dart` | thread cache + paginação | `chat_media/` | ✅ parcial | P0 |
| **Certificados** | `certificados_emitidos/` | `church_certificados_load_service.dart` | `certificados_cache_service.dart` | `certificados/` | 🔲 adicionar | P1 |
| **Minha escala** | `escalas/` (filtro user) | `church_schedules_load_service.dart` | `escalas_cache_service.dart` | — | ✅ | P0 |
| **Escala geral** | `escalas/` | idem | compartilha cache | — | ✅ | P0 |
| **Fornecedores** | `fornecedores/` | `church_fornecedores_load_service.dart` | `fornecedores_cache_service.dart` | anexos | 🔲 adicionar | P2 |
| **Financeiro** | `finance/` | `church_finance_load_service.dart` | `finance_cache_service.dart` | `financeiro/YYYY_MM/` | ✅ | P0 |
| **Eventos** | `eventos/` | `church_eventos_load_service.dart` | `eventos_cache_service.dart` | `eventos/` | ✅ | P0 |
| **Avisos** | `avisos/` | `church_avisos_load_service.dart` | `avisos_cache_service.dart` | `avisos/` | ✅ | P0 |
| **Carta transferência** | `cartas_historico/` | via `transferencias` repo | `cartas_cache_service.dart` | PDF | 🔲 | P2 |
| **Patrimônio** | `patrimonio/` | `church_patrimonio_load_service.dart` | `patrimonio_cache_service.dart` | fotos | ✅ | P1 |
| **Agenda** | `agenda/` | `church_agenda_load_service.dart` | `agenda_cache_service.dart` | — | ✅ | P2 |
| **Visitantes** | `visitantes/` | `church_visitantes_load_service.dart` | `visitantes_cache_service.dart` | — | ✅ | P2 |

**Gateway único:** `lib/core/repositories/church_repository.dart` — telas **só** falam com repository/cache, nunca `.collection()` direto.

---

## 5. Padrão de gravação (Web + mobile)

### 5.1 Metadados simples (sem arquivo)

```dart
await FirestoreWebGuard.runFirestoreOpSafe(() async {
  await ChurchRepository.membros.doc(id).set(payload, SetOptions(merge: true));
});
```

### 5.2 Com foto / vídeo / áudio (strict publish)

Ordem obrigatória (já documentado em `publication_engine.dart`):

```
1. Otimizar mídia no cliente (resize JPEG/WebP, áudio AAC, vídeo MP4)
2. putData / putFile → Firebase Storage (com progresso)
3. getDownloadURL (ou path canônico)
4. Gravar Firestore com { url, storagePath, status: 'published', updatedAt }
5. UI: refresh cache local (invalidate signature) — NÃO snapshot infinito
```

**Referências WISDOMAPP:**
| Tipo | Arquivo |
|------|---------|
| Imagem curso | `lib/services/course_video_image_service.dart` |
| Vídeo MP4 | `lib/services/course_video_file_service.dart` |
| Comprovante via CF | `FunctionsService.uploadReceiptToStorage` |
| Fila offline | `lib/services/pending_storage_upload_service.dart` |

**Referências YAHWEH (usar/expandir):**
| Tipo | Arquivo |
|------|---------|
| Fila Storage | `lib/services/storage_upload_queue_service.dart` |
| Batch fotos | `lib/services/media_batch_upload_queue.dart` |
| Strict publish | `lib/core/publication/publication_engine.dart` |
| Guard write | `lib/utils/firestore_write_guard.dart` |

### 5.3 Áudio (chat / avisos / eventos)

```
Gravar → arquivo local (.aac / .m4a)
→ StorageUploadQueueService.enqueue(path, destino: ChurchStorageLayout.chatAudio(...))
→ stub message/doc status: uploading
→ onComplete: patch url + status: sent
→ retry automático se rede cair
```

**Limite sugerido:** áudio 5 min / 10 MB; vídeo aviso 60 s / 80 MB; vídeo evento 5 min / 250 MB (igual cursos WISDOMAPP).

---

## 6. Cloud Functions — writes pesados (Admin)

**Padrão WISDOMAPP:** `lib/utils/admin_course_firestore_bridge.dart` + `ctAdminUpsertCourseVideo`

**Criar no YAHWEH (`functions/src/`):**

| Callable | Uso |
|----------|-----|
| `yahwehPublishAvisoStrict` | Valida tenant + grava aviso após Storage OK |
| `yahwehPublishEventoStrict` | Idem eventos |
| `yahwehBulkImportMembros` | Import CSV grande |
| `yahwehGenerateCertificadoPdf` | PDF server-side + Storage |
| `yahwehOptimizeImage` | WebP variants (já existe parcialmente V4) |

**Regra:** cliente faz upload; CF só valida, normaliza timestamps, evita corrupção Web.

---

## 7. Shell e navegação (velocidade percebida)

**Copiar conceitos de** `WISDOMAPP/lib/screens/home_shell.dart`:

| Conceito | Implementação YAHWEH |
|----------|---------------------|
| `_materializedModuleIndices` | `church_shell_lazy_module_policy.dart` |
| Máx. 2 módulos retidos | Ajustar `_kMaxRetainedMaterializedModules = 2` |
| `AutomaticKeepAliveClientMixin` | Telas pesadas (financeiro, chat, escalas) |
| Prefetch ao entrar | `ChurchTenantDashboardWarmupService` |
| ScrollController por aba | Evitar perder posição ao trocar menu |

**Proibir:** montar Dashboard + Chat + Membros + Financeiro + Escalas ao mesmo tempo.

---

## 8. Sites públicos (3 superfícies)

| Site | Rota / tela | Fonte de dados | Padrão rápido |
|------|-------------|----------------|---------------|
| **Site igreja público** | `site_public_page.dart`, `church_public_page.dart` | `igrejas/{id}` + slug | Ler `_performance_cache/public_feed` (CF) |
| **Cadastro membro público** | fluxo onboarding público | `membros` draft + Auth | Write via CF `yahwehPublicMemberSignup` |
| **Site divulgação** | marketing global | coleção marketing | Cache estático + CDN Hosting |

**WISDOMAPP equivalente:** `landing_content/main` (read público) + `LandingScreen` cache local.

**YAHWEH:** CF `generatePublicFeedCache` (já em V4) — **obrigar** site público a usar cache, não listar `avisos`/`eventos` live.

---

## 9. Web vs Android vs iOS — paridade

| Recurso | Web | Android | iOS |
|---------|-----|---------|-----|
| Cache disco módulos | SharedPreferences + RAM | Hive + RAM | Hive + RAM |
| Firestore persistence | OFF + long-polling | ON | ON |
| Live snapshots listas | OFF (`disableLiveSnapshotsOnWeb`) | limitado | limitado |
| Upload vídeo grande | putData + progress | putFile | putFile |
| Gravação áudio | MediaRecorder web / file picker | record package | record package |
| Biometria reopen | N/A | warmUp hint | Face/Touch ID |
| Push | FCM web | FCM | APNs |

**Doc:** `docs/PARITY_WEB_ANDROID_IOS.md`

---

## 10. Plano de implementação (6 fases)

### Fase 0 — Fundação (1–2 dias)
- [ ] Auditar telas com `.collection(` em `lib/ui/` → migrar para `ChurchRepository`
- [ ] Garantir `FirestoreWebGuard` sem `terminate()` em retry automático
- [ ] Criar `lib/core/cache/yahweh_cache_bootstrap.dart` (warmUp central)

### Fase 1 — P0 módulos (1 semana)
- [ ] Membros, Avisos, Eventos, Financeiro, Escalas, Chat — cache service cada
- [ ] Refatorar telas principais: remover StreamBuilder → `ListenableBuilder` + cache
- [ ] Strict publish testado Web + Android

### Fase 2 — P1 módulos (1 semana)
- [ ] Cargos, Departamentos, Certificados, Cartões, Patrimônio
- [ ] Expandir `OfflineModules` + fila Storage

### Fase 3 — Sites públicos (3 dias)
- [ ] Site igreja 100% cache `_performance_cache`
- [ ] Cadastro membro público via CF
- [ ] Divulgação estática

### Fase 4 — Cloud Functions (3 dias)
- [ ] Callables strict publish + optimizeImage
- [ ] Eliminar reads `tenants/` legado no backend

### Fase 5 — QA multi-plataforma (1 semana)
- [ ] Checklist `docs/CHECKLIST_PRODUCAO.md`
- [ ] Teste rede lenta / offline / troca de igreja
- [ ] Teste upload 10 fotos + 1 vídeo + 3 áudios chat

---

## 11. Checklist por tela (antes de dar módulo por pronto)

- [ ] Abre com dados do cache (mesmo offline)
- [ ] Pull-to-refresh chama `ensureLoaded(forceServer: true)`
- [ ] Gravar não usa `terminate()`
- [ ] Upload mostra progresso e completa Firestore depois
- [ ] Áudio/vídeo/foto funcionam Web + Android + iOS
- [ ] Lista não reconstrói player/iframe a cada notify
- [ ] Nenhum `StreamBuilder` desnecessário na Web
- [ ] Paginação 20 itens

---

## 12. Arquivos WISDOMAPP para copiar (espelhar em YAHWEH)

Copiar/adaptar de `C:\WISDOMAPP\lib\` → `flutter_app\lib\`:

| Origem WISDOMAPP | Destino YAHWEH sugerido |
|------------------|-------------------------|
| `utils/firestore_web_guard.dart` | já existe — alinhar `runFirestoreOpSafe` |
| `services/course_videos_cache_service.dart` | template `core/cache/modules/*_cache_service.dart` |
| `services/pending_storage_upload_service.dart` | merge com `storage_upload_queue_service.dart` |
| `services/course_video_file_service.dart` | `core/media/church_video_upload_service.dart` |
| `services/course_video_image_service.dart` | `core/media/church_image_upload_service.dart` |
| `utils/admin_course_firestore_bridge.dart` | `core/bridge/yahweh_admin_firestore_bridge.dart` |
| `screens/home_shell.dart` (lazy policy) | `ui/igreja_clean_shell.dart` |
| `services/app_session_cache.dart` | alinhar `PersistentAuthSessionService` |
| `widgets/course_photo_lightbox.dart` | galeria avisos/eventos |

Backup já em: `docs/backup_wisdomapp/`

---

## 13. Prompt Cursor — colar para implementar módulo a módulo

Arquivo dedicado: **`docs/PROMPT_CURSOR_PERFORMANCE_MODULO.md`**

---

## 14. Métricas de sucesso

| Métrica | Meta |
|---------|------|
| Time-to-first-content (cache) | < 300 ms |
| Time-to-first-content (cold) | < 2 s |
| Gravação Firestore Web sucesso | > 99% |
| Upload foto 2 MB | < 8 s em 4G |
| Crash por `client terminated` | 0 |
| Módulos na RAM | ≤ 2 |

---

*Documento gerado a partir do WISDOMAPP em produção (jun/2026) e auditoria do Gestão YAHWEH Premium.*
