# Checklist de Produção — Gestão YAHWEH

**Nenhum deploy completo** (`deploy_completo.ps1`) deve ocorrer se algum item crítico falhar.

## Gate automático (CI local)

```powershell
.\scripts\verify_production_checklist.ps1
```

Integrado no início de `deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1`.  
Bypass de emergência: `-SkipProductionGate` (não recomendado).

## Bloqueadores de release

| Área | Critério |
|------|----------|
| Firebase | Núcleo inicializado (`FirebaseBootstrapService`) |
| permission-denied | Zero em Chat, Avisos, Eventos, Uploads |
| Chat | Leitura `igrejas/{tenant}/chats` OK |
| Avisos | Leitura `igrejas/{tenant}/avisos` OK |
| Eventos | Leitura `igrejas/{tenant}/eventos` OK |
| Upload | Filas locais &lt; 15 jobs presos |
| Login | Auth com sessão válida (teste manual) |
| Sync | Fila Hive &lt; 200 tarefas ou offline esperado |

## Central de Saúde (painel ADM)

Menu Master → **Saúde do Sistema** → aba **Central**

- Status: Firebase, Firestore, Storage, Auth, Sync, Chat, Site Público
- **Modo Produção: LIBERADO / BLOQUEADO**
- **Último erro** da sessão (`SystemLastErrorRegistry`)

## Backup automático

Cloud Functions já deployadas:

- `backupDailyToGcs` — export Firestore diário → GCS (`gcs.backup_bucket`)
- `backupDailyToDrive` — backup legado Google Drive

Coleções incluídas no export Firestore: usuários, eventos, avisos, patrimônio, financeiro (documentos em `igrejas/{tenant}/...`).

Restauração: Firebase Console → Firestore → Import/Export ou bucket GCS.

## Monitoramento

| Serviço | Onde |
|---------|------|
| Crashlytics | `main.dart` + `CrashlyticsService` (Android/iOS release) |
| Analytics | `AnalyticsService` |
| Performance | `PerformanceService` + traces em `production_module_traces.dart` |

Traces canónicos: `time_dashboard`, `time_chat`, `time_avisos`, `time_eventos`, `time_patrimonio`, `time_financeiro`, `time_upload`, `time_sync_flush`, `time_login`.

Erros categorizados: `firestore_error`, `storage_error`, `upload_error` via `YahwehObservability`.

## Teste manual pós-deploy (20 passos)

1. Login permanente + biometria  
2. Dashboard carrega offline-first  
3. Chat envia/recebe texto e mídia  
4. Avisos publica (Publication Engine)  
5. Eventos publica  
6. Patrimônio grava foto  
7. Financeiro grava lançamento  
8. Sync flush após voltar online  
9. Site público abre feed  
10. Painel Master → Central = LIBERADO  

## Arquitetura fechada

Sem novas funcionalidades até todos os bloqueadores acima estarem estáveis em **Android, iOS e Web**.

## Gate multiplataforma (release)

| Critério | Regra |
|----------|-------|
| Testes QA | 28 testes em **Android**, **iPhone** e **Web** |
| Módulos | Login, Chat, Avisos, Eventos, Membros, Patrimônio, Financeiro, Uploads — mesma experiência |
| Offline | Android/iOS obrigatório; Web cache + recuperação automática |
| Falha numa plataforma | **Release bloqueada** |

Documentação: `docs/PADRONIZACAO_MULTIPLATAFORMA.md` · Código: `lib/core/qa/multiplatform_qa_matrix.dart`

Ver `.cursor/rules/padronizacao-multiplataforma.mdc` e `fase-final-qualidade.mdc`.
