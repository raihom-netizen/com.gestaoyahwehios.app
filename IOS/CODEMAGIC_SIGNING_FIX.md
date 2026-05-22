# Codemagic iOS — assinatura estável (definitivo)

## Política do repositório (a partir de 2026-05)

- **Por defeito:** só modo **manual** — `CM_CERTIFICATE` (P12 Base64) + `CM_PROVISIONING_PROFILE`.
- **`CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM`:** não usar na Codemagic (apagar). Causa erro em todo push se não for o par exacto do certificado Apple.
- **`CM_DISALLOW_API_ONLY_SIGNING: "1"`** no `codemagic.yaml` — o passo «Verificar variáveis» falha cedo com instruções claras se faltar P12.
- Passo 11 usa **`scripts/codemagic_ios_install_signing.sh`** (entrada única).

## Erro típico (build 1589+)

```
PEM não corresponde a nenhum certificado IOS_DISTRIBUTION
POST certificates returned 409 (já existe certificado Distribution)
```

## Causa

O secret `CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM` no Codemagic **não é o par** do certificado «Apple Distribution» activo na equipa Apple (82RC6YL7KL).

## Erro actual (build Codemagic — passo 11)

```
CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM não corresponde ao certificado
bootstrap HTTP 409 — já existe certificado Distribution (5 na API, máx. 3 activos)
```

**Correcção imediata (sem nova versão Android/web):**

1. **Codemagic** → `appstore_credentials`:
   - **Apague** ou deixe **vazio** `CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM` (está errado e dispara 409).
   - **Preencha** `CM_CERTIFICATE` (ou `CERTIFICATE_PRIVATE_KEY`) = Base64 do `.p12` Apple Distribution.
   - **Preencha** `CM_PROVISIONING_PROFILE` = Base64 do `.mobileprovision` App Store de `com.gestaoyahwehios.app`.
   - `CM_CERTIFICATE_PASSWORD` = senha do P12 (ou vazio).
2. **Apple** → revogue 1–2 certificados «Apple Distribution» **expirados/duplicados**:  
   https://developer.apple.com/account/resources/certificates/list  
   (deixe no máximo **2** activos até estabilizar.)
3. No Mac: exporte **novo** `.p12` + baixe **novo** perfil App Store (perfil deve incluir **esse** certificado).
4. PC: `.\scripts\encode_ios_codemagic_secrets.ps1` → colar os `.txt` em `D:\Temporarios\gestao_yahweh_codemagic\`.
5. **Novo build** Codemagic (mesma versão 11.2.295+1595).

O `codemagic.yaml` no repo tem `CM_AUTO_BOOTSTRAP_PEM_MISMATCH=0` para **não** tentar criar certificado novo na CI.

## Solução A — Recomendada (estável, igual Controle Total)

1. No Mac: exportar **Apple Distribution** como `.p12` + descarregar perfil **App Store** de `com.gestaoyahwehios.app`.
2. Na raiz do repo (PowerShell):

```powershell
.\scripts\encode_ios_codemagic_secrets.ps1
```

3. Codemagic → **Environment variables** → grupo `appstore_credentials`:
   - `CERTIFICATE_PRIVATE_KEY` ou `CM_CERTIFICATE` = Base64 do P12 (uma linha)
   - `CM_PROVISIONING_PROFILE` = Base64 do `.mobileprovision` (uma linha)
   - `CM_CERTIFICATE_PASSWORD` = senha do P12 (se tiver)
4. **Remover** ou deixar vazio `CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM` (evita modo API-only com PEM errado).
5. `codemagic.yaml`: `CM_FORCE_API_ONLY_SIGNING: "0"` (já é o padrão).
6. Novo build → modo **manual** instala P12 + perfil.

## Solução B — Só API (.p8) com PEM correcto

1. Gerar PEM + CSR:

```powershell
.\scripts\gen_ios_distribution_csr_private_key_pem.ps1
```

2. Apple Developer → Certificates → **Apple Distribution** → upload do `.csr`.
3. Codemagic: `CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM` = conteúdo **completo** do `distribution_private_key.pem`.
4. Perfil App Store: editar e marcar **esse** certificado Distribution.

## Solução C — Bootstrap automático na CI (sem Mac)

Se aparecer **409** (limite de 3 certificados Distribution):

1. Revogar um certificado antigo: https://developer.apple.com/account/resources/certificates/list
2. Push + build; com `CM_AUTO_BOOTSTRAP_PEM_MISMATCH=1` o CI cria par novo e grava PEM em `bootstrap_signing_output/`.
3. Copiar `distribution_private_key.pem` para o secret `CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM`.
4. Builds seguintes: estável com esse PEM.

## O que o repositório faz agora (scripts)

- Valida PEM antes do `fetch-signing-files --create` (evita 409 desnecessário).
- PEM inválido → tenta **P12** nos secrets → senão **bootstrap** ASC.
- Remove permissões `READ_MEDIA_*` no Android (build Play separado).
