# Domínios alinhados — Gestão YAHWEH

## URLs oficiais (mesmo app, mesmo Firebase)

| URL | Uso |
|-----|-----|
| [https://gestaoyahweh.com.br](https://gestaoyahweh.com.br) | Domínio canónico (marketing, links públicos) |
| [https://gestaoyahweh-21e23.web.app](https://gestaoyahweh-21e23.web.app) | Hosting Firebase (mesmo build) |
| `gestaoyahweh-21e23.firebaseapp.com` | Auth OAuth redirect |

Ambos servem **`flutter_app/build/web`** (`firebase.json` → site `gestaoyahweh-21e23`).

## Firebase Console — Authorized domains (obrigatório)

1. [Authentication → Settings → Authorized domains](https://console.firebase.google.com/project/gestaoyahweh-21e23/authentication/settings)
2. Adicionar **todos**:
   - `gestaoyahweh.com.br`
   - `www.gestaoyahweh.com.br`
   - `gestaoyahweh-21e23.web.app`
   - `gestaoyahweh-21e23.firebaseapp.com`

Sem isso: login Google/e-mail falha com **"This domain is not authorized"** num dos domínios.

## Google OAuth (Web client)

[APIs & Services → Credentials](https://console.cloud.google.com/apis/credentials?project=gestaoyahweh-21e23) → OAuth 2.0 Web client:

**Authorized JavaScript origins:**
- `https://gestaoyahweh.com.br`
- `https://www.gestaoyahweh.com.br`
- `https://gestaoyahweh-21e23.web.app`

## Storage CORS

```powershell
.\scripts\apply_firebase_storage_cors.ps1
```

Ou checklist completo:

```powershell
.\scripts\ensure_firebase_domains_aligned.ps1
```

## Código (app)

- `PublicWebOrigin` / `AppConstants.effectivePublicWebBaseUrl` — na web usa o host actual se for oficial.
- `FirestoreWebGuard.bindWebHostingDomainSession()` — persistência + `enableNetwork()` no arranque/resume.
- Android: `AndroidManifest.xml` — deep links `gestaoyahweh.com.br` e `gestaoyahweh-21e23.web.app`.
- iOS/Android nativos: mesmo projeto Firebase (`firebase_options.dart`); sessão `Persistence.LOCAL` na web.

## Deploy

Publicar **uma vez** — actualiza os dois domínios (custom domain aponta para o mesmo hosting):

```powershell
.\scripts\deploy_web_hosting.ps1
```

Depois: **Ctrl+F5** ou limpar dados do site no telemóvel.
