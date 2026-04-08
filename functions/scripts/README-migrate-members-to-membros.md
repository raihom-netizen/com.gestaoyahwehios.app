# Script: members → membros (urgente / local)

Roda **fora** das Cloud Functions. Corrige dados quando o painel mostra `Erro: internal`.

## Pré-requisito

- Node 20+ na pasta `functions` (`npm install` já feito).
- Uma destas opções:
  1. **Conta de serviço** (recomendado): no Firebase Console → Configurações do projeto → Contas de serviço → gerar chave JSON. Depois:
     - Windows PowerShell:
       ```powershell
       $env:GOOGLE_APPLICATION_CREDENTIALS="C:\caminho\para\chave.json"
       ```
  2. Ou **gcloud**:
     ```bash
     gcloud auth application-default login
     ```

## Comandos

```bash
cd functions
npm run migrate-members-to-membros
```

- **Só uma igreja** (ex.: Brasil para Cristo Jardim Goiano):

```bash
node scripts/migrate-members-to-membros.js --igreja=igreja_o_brasil_para_cristo_jardim_goiano
```

- **Só copiar** `members` → `membros` (sem sincronizar `users`):

```bash
node scripts/migrate-members-to-membros.js --no-users
```

## O que faz

1. Em cada documento de `igrejas`, copia `members/{id}` → `membros/{id}` (merge).
2. Lê `users` e grava em `igrejas/{igrejaId}/membros/{uid}` quem tem `tenantId` ou `igrejaId` válido na coleção `igrejas`.

A subcoleção antiga `members` **não é apagada**.
