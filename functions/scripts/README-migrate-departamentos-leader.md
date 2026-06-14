# Migração — leaderName / leaderFotoUrl em departamentos

Preenche campos denormalizados para exibir **Líder: …** na lista sem carregar o roster de membros.

## O que faz

Para cada doc em `igrejas/{churchId}/departamentos`:

1. Lê CPF(s) do líder (`leaderCpfs`, `leaderCpf`, `viceLeaderCpf`, legado)
2. Busca o 1.º membro em `igrejas/{churchId}/membros` pelo CPF
3. Grava (merge):
   - `leaderName` — `NOME_COMPLETO` / `nome` / `name`
   - `leaderFotoUrl` — `fotoThumbUrl` / `fotoUrl` / …
   - `leaderCpfs` normalizado + `leaderCpf` / `viceLeaderCpf`
   - `leaderDenormMigratedAt` / `leaderDenormMigratedBy`

## Comandos

```powershell
# Simular (todas as igrejas)
.\scripts\migrate_departamentos_leader_denorm.ps1

# Simular só BPC
.\scripts\migrate_departamentos_leader_denorm.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano

# Gravar produção
.\scripts\migrate_departamentos_leader_denorm.ps1 -Execute

# Só uma igreja
.\scripts\migrate_departamentos_leader_denorm.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano -Execute
```

Node direto (pasta `functions/`):

```bash
npm run migrate-departamentos-leader -- --dry-run
npm run migrate-departamentos-leader -- --igreja=igreja_o_brasil_para_cristo_jardim_goiano
```

## Validar no app

1. Abra **Departamentos** — cards devem mostrar **Líder: Nome** sem delay de roster
2. Firebase Console → `igrejas/{id}/departamentos/{deptId}` → confira `leaderName`, `leaderFotoUrl`

## Flags

| Flag | Efeito |
|------|--------|
| `--dry-run` | Só log, não grava |
| `--igreja=` | Limita a uma igreja |
| `--force` | Reprocessa mesmo com campos já preenchidos |
| `--clear-orphans` | Limpa `leaderName`/`leaderFotoUrl` se não há CPF de líder |
