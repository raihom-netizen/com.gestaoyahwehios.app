# Migração `escalados[]` — Escalas

Popula o array denormalizado **`escalados[]`** (e **`memberUids`**) nos documentos legados que só tinham `memberCpfs` + `memberNames`.

## O que preserva

- Chaves **`confirmations`** por CPF (ex.: `94536368191`) — **não apaga**
- Espelha confirmação por **UID** quando `membros/{id}` tem `authUid` (acelera Minha Escala / queries `memberUids`)
- Campos legados `memberCpfs` / `memberNames` mantidos (dual-write alinhado ao app)

## Pré-requisito

- Node + `npm install` na pasta `functions/`
- Credenciais Admin:
  - `GOOGLE_APPLICATION_CREDENTIALS` → JSON conta de serviço, **ou**
  - `gcloud auth application-default login`

## Comandos

```powershell
# Simular (não grava)
.\scripts\migrate_escalas_escalados_denorm.ps1

# Piloto BPC
.\scripts\migrate_escalas_escalados_denorm.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano

# Gravar — uma igreja
.\scripts\migrate_escalas_escalados_denorm.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano -Execute

# Gravar — todas as igrejas
.\scripts\migrate_escalas_escalados_denorm.ps1 -Execute
```

Direto via Node:

```bash
cd functions
node scripts/migrate-escalas-escalados-denorm.js --dry-run
node scripts/migrate-escalas-escalados-denorm.js --igreja=igreja_o_brasil_para_cristo_jardim_goiano
```

## Coleções

- `igrejas/{churchId}/escalas` — escalas geradas
- `igrejas/{churchId}/escala_templates` — modelos

Docs que já têm `escalados[]` completo são ignorados (use `--force` para reprocessar).

## Referência no app

Lógica espelhada de `flutter_app/lib/core/escala_member_payload.dart` (`parseMembers` / `writeFieldsFromMembers`).
