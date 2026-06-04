# Copiar toolchain GCP + regras Firebase para outros projetos

Kit mínimo para publicar **Firestore/Storage rules** em `firebaserules.googleapis.com` (não no banco Firestore), com `gcloud` automático e IAM via `googleapis`.

## Ficheiros a copiar (raiz do repo destino)

### Scripts (pasta `scripts/`)

| Ficheiro | Função |
|----------|--------|
| `install_google_cloud_sdk.ps1` | Instala gcloud (winget / zip / installer) |
| `ensure_gestao_yahweh_toolchain_path.ps1` | PATH Flutter/Firebase/gcloud (renomear variáveis se outro produto) |
| `ensure_google_cloud_auth.ps1` | Auth SA + token Node |
| `ensure_functions_node_for_gcp.ps1` | `npm ci` em `functions/` (googleapis) |
| `firebase_rules_gcp_publish.cjs` | Publicação REST Firestore + Storage |
| `firebase_rules_preflight.ps1` | Skip `/test` se já sincronizado |
| `firebase_rules_gcp_watchdog.ps1` | Retry 503 em background |
| `grant_gcp_firebase_rules_iam.cjs` | IAM SA via API (googleapis) |
| `gcp_service_account_token.cjs` | Token OAuth SA |
| `setup_gcp_firebase_rules_permanent.ps1` | APIs + IAM + publish |
| `regras_gcp_automatico_forcado.ps1` | **Comando único** (autorizado) |
| `deploy_firebase_rules.ps1` | Deploy completo (preflight + GCP + índices) |
| `apply_firebase_storage_cors.ps1` | CORS bucket (gsutil) |

Opcionais: `setup_google_cloud_automatico.ps1`, `deploy_firebase_rules_background.ps1`

### Regras Cursor (`.cursor/rules/`)

| Ficheiro | `alwaysApply` |
|----------|----------------|
| `gcloud-toolchain-automatico.mdc` | sim |
| `deploy-firebase-regras-automatico.mdc` | sim |
| `configuracao-mestre-automatica.mdc` | sim (ajustar nome do produto) |

### Manual

- `prompt_mestre_cursor.md` (secção **6.2** e **6.4**)
- `AGENTS.md` (toolchain + comando autorizado)

### Raiz do projeto destino

- `firestore.rules`, `storage.rules`, `firestore.indexes.json`, `firebase.json`
- `cors.json` (se usar CORS web Storage)
- Pasta `ANDROID/` ou `secrets/` com `*-firebase-adminsdk*.json`
- `functions/package.json` com `"googleapis"` e `"google-auth-library"`

## Ajustes no projeto novo

1. Substituir `gestaoyahweh-21e23` por o **Project ID** Firebase em scripts `.ps1` / `.cjs`.
2. Em `ensure_gestao_yahweh_toolchain_path.ps1`: opcional renomear `GESTAO_YAHWEH_TOOLCHAIN_ROOT` → `MEU_PRODUTO_TOOLCHAIN_ROOT`.
3. Cursor: referenciar `@prompt_mestre_cursor.md` ou copiar secções 6.2–6.4.
4. Primeira vez no PC:
   ```powershell
   .\scripts\regras_gcp_automatico_forcado.ps1
   ```

## Comando único (utilizador autorizou)

```powershell
.\scripts\regras_gcp_automatico_forcado.ps1
```

Ordem interna: toolchain → gcloud → auth → `npm ci` functions → setup IAM (googleapis + gcloud) → preflight → `firebase_rules_gcp_publish.cjs` → CORS.

## Notas

- Regras ficam no **Google Cloud** (`firebaserules.googleapis.com`), não em documentos Firestore.
- `gcloud services enable` pode falhar com PERMISSION_DENIED na SA — normal; publish REST com SA costuma funcionar.
- IAM API (`grant_gcp_firebase_rules_iam.cjs`) exige credencial **Owner** humana (ADC) uma vez; depois gcloud fallback cobre o resto.
