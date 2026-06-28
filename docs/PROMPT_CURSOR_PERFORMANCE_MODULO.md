# Prompt Cursor — implementar performance WISDOMAPP em um módulo YAHWEH

Use este prompt **um módulo por vez** no projeto `C:\gestao_yahweh_premium_final\flutter_app`.

Leia antes: `docs/PADRAO_MESTRE_WISDOMAPP_YAHWEH_TOTAL.md`

---

## Prompt (copiar e substituir `{MODULO}`)

```
Estou padronizando o Gestão YAHWEH Premium para ficar tão rápido quanto o WISDOMAPP (Web + Android + iOS).

Projeto: C:\gestao_yahweh_premium_final\flutter_app
Referência: C:\WISDOMAPP (cache-first, FirestoreWebGuard, strict publish Storage→Firestore)

Módulo alvo: {MODULO}
Firestore path: igrejas/{churchId}/{COLECAO}/
Load service existente: {LOAD_SERVICE}.dart
Telas principais: {TELAS}

Tarefas obrigatórias:

1. CACHE-FIRST
   - Criar `{modulo}_cache_service.dart` espelhando WISDOMAPP `course_videos_cache_service.dart`:
     warmUp SharedPreferences → notify se tem cache → fetch Firestore cache → server → persist
     - `_inFlight` dedupe, `_signature` para notifyListeners só quando mudou
     - `showInitialLoading` só se `_docs.isEmpty && _refreshing`

2. UI SEM TREMEDEIRA
   - Refatorar telas listadas: remover StreamBuilder desnecessários na Web
   - Usar ListenableBuilder no cache service
   - AutomaticKeepAliveClientMixin em telas pesadas
   - Comparar dados por id, não por referência de Map

3. GRAVAÇÃO ESTÁVEL
   - Todas writes via FirestoreWebGuard.runFirestoreOpSafe (NUNCA terminate no fluxo normal)
   - prepareForPublishWrite() antes de gravar após upload
   - Gateway ChurchRepository apenas — zero .collection() na UI

4. UPLOAD MÍDIA (se módulo tiver foto/vídeo/áudio)
   - Ordem: otimizar → Storage putData/putFile → URL → Firestore
   - Usar StorageUploadQueueService + retry offline
   - Progresso visível na UI
   - Áudio: gravar local → enqueue → patch doc status uploading→sent

5. WEB + ANDROID + iOS
   - Web: snapshots live OFF para listas; cache SharedPreferences
   - Mobile: Hive via TenantModuleHiveCache onde aplicável
   - Testar os 3 alvos

6. NÃO REGREDIR
   - Manter paths canônicos igrejas/{churchId}/...
   - Não reintroduzir tenants/ legado
   - flutter analyze sem erros nos arquivos tocados

Entregáveis:
- Arquivos criados/alterados listados
- Resumo do que ficou cache-first
- Como testar manualmente (Web Ctrl+F5, Android, iOS)
```

---

## Módulos — valores para substituir

### Membros
- `{MODULO}` = Membros
- `{COLECAO}` = membros
- `{LOAD_SERVICE}` = church_members
- `{TELAS}` = members_page.dart, member_form_*.dart

### Cadastro igreja
- `{MODULO}` = Cadastro Igreja
- `{COLECAO}` = (doc raiz)
- `{LOAD_SERVICE}` = church_cadastro
- `{TELAS}` = igreja_cadastro_page.dart, igreja_dashboard_moderno.dart

### Cartão membro
- `{MODULO}` = Cartão Membro
- `{COLECAO}` = cartoes
- `{LOAD_SERVICE}` = (repository cartoes)
- `{TELAS}` = member_card_page.dart

### Cargos
- `{MODULO}` = Cargos
- `{COLECAO}` = cargos
- `{LOAD_SERVICE}` = church_cargos
- `{TELAS}` = cargos_page.dart

### Departamentos
- `{MODULO}` = Departamentos
- `{COLECAO}` = departamentos
- `{LOAD_SERVICE}` = church_departments
- `{TELAS}` = departments_page.dart

### Chat igreja
- `{MODULO}` = Chat
- `{COLECAO}` = chats/{threadId}/messages
- `{LOAD_SERVICE}` = church_chat_service
- `{TELAS}` = church_chat_hub_page.dart, church_chat_thread_page.dart

### Certificados
- `{MODULO}` = Certificados
- `{COLECAO}` = certificados_emitidos
- `{LOAD_SERVICE}` = church_certificados
- `{TELAS}` = certificados_page.dart

### Minha escala / Escala geral
- `{MODULO}` = Escalas
- `{COLECAO}` = escalas
- `{LOAD_SERVICE}` = church_schedules
- `{TELAS}` = schedules_page.dart, my_schedules_page.dart

### Fornecedores
- `{MODULO}` = Fornecedores
- `{COLECAO}` = fornecedores
- `{LOAD_SERVICE}` = church_fornecedores
- `{TELAS}` = fornecedores_page.dart

### Financeiro
- `{MODULO}` = Financeiro
- `{COLECAO}` = finance
- `{LOAD_SERVICE}` = church_finance
- `{TELAS}` = finance_page.dart

### Eventos
- `{MODULO}` = Eventos
- `{COLECAO}` = eventos
- `{LOAD_SERVICE}` = church_eventos
- `{TELAS}` = events_manager_page.dart

### Avisos
- `{MODULO}` = Avisos
- `{COLECAO}` = avisos
- `{LOAD_SERVICE}` = church_avisos
- `{TELAS}` = instagram_mural.dart, avisos_*.dart

### Carta transferência
- `{MODULO}` = Carta Transferência
- `{COLECAO}` = cartas_historico
- `{LOAD_SERVICE}` = transferencias repository
- `{TELAS}` = telas de cartas/transferência

### Site igreja público
- `{MODULO}` = Site Público Igreja
- `{COLECAO}` = _performance_cache/public_feed
- `{LOAD_SERVICE}` = ChurchPerformanceCacheService
- `{TELAS}` = site_public_page.dart, church_public_page.dart

### Cadastro membro público
- `{MODULO}` = Cadastro Membro Público
- `{COLECAO}` = membros (draft público)
- `{LOAD_SERVICE}` = (criar public_member_signup_service)
- `{TELAS}` = fluxo onboarding público

### Site divulgação
- `{MODULO}` = Divulgação
- `{COLECAO}` = marketing global
- `{LOAD_SERVICE}` = marketing cache
- `{TELAS}` = landing/divulgação

---

## Ordem recomendada de execução

1. Membros  
2. Avisos  
3. Eventos  
4. Financeiro  
5. Escalas (minha + geral)  
6. Chat  
7. Cadastro igreja  
8. Cartão membro  
9. Cargos + Departamentos  
10. Certificados  
11. Fornecedores + Carta transferência  
12. Sites públicos (igreja + cadastro + divulgação)
