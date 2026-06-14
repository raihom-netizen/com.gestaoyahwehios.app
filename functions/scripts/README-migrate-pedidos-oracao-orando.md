# Migração — orandoMembros (Pedidos de Oração)

Preenche o array denormalizado `orandoMembros` a partir de `orandoUids` em
`igrejas/{churchId}/pedidosOracao`.

## Quando usar

Pedidos antigos que só têm `orandoUids` / `orandoCount` — avatares aparecem
após alguém tocar de novo em «Estou orando». Esta migração preenche todos de
uma vez.

## Comandos

Simular (não grava):

```powershell
.\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1
.\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano
```

Executar:

```powershell
.\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1 -Execute
.\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1 -Igreja igreja_o_brasil_para_cristo_jardim_goiano -Execute
```

Reprocessar todos (mesmo com `orandoMembros` já preenchido):

```powershell
.\scripts\migrate_pedidos_oracao_orando_membros_denorm.ps1 -Execute -Force
```

Ou via npm em `functions/`:

```bash
npm run migrate-pedidos-oracao-orando -- --dry-run
npm run migrate-pedidos-oracao-orando -- --igreja=igreja_o_brasil_para_cristo_jardim_goiano
```

## Campos gravados

- `orandoMembros[]` — `{ uid, nome, fotoUrl }`
- `orandoUids` — alinhado aos UIDs
- `orandoCount` — tamanho do array
- `orandoMembrosDenormMigratedAt` — timestamp da migração

## Resolução de perfil

1. Índice `membros` por `authUid` / `firebaseUid`
2. Fallback: entrada existente em `orandoMembros` ou nome «Membro»
