# Importação de membros — Brasil para Cristo (BPC)

Script que importa o CSV **PLANILHA_SISTEMA_IGREJA_BPC_DB_V3 - MEMBERS.csv** para a igreja **Brasil para Cristo** no Firestore.

## Automático (recomendado)

Na **raiz do projeto** execute:

```powershell
.\importar-membros-bpc.ps1
```

O script usa o CSV em `membros_igrebrasilparacristo\` e as credenciais em `secrets\gestaoyahweh-21e23-7951f1817911.json`. Tudo em um comando.

## Comportamento

- **Com CPF válido (11 dígitos):** o membro é importado como **ativo**; o ID do documento é o CPF (apenas números).
- **Sem CPF:** o membro é importado como **pendente** (`STATUS`/`status` = `pendente`) para atualização completa depois no painel (ex.: tela "Aprovar Novos Membros" ou edição de membros).

## Pré-requisitos

1. **Node.js** (v18+).
2. **Chave do Firebase Admin:** defina a variável de ambiente `GOOGLE_APPLICATION_CREDENTIALS` apontando para o arquivo JSON da conta de serviço do projeto **gestaoyahweh-21e23** (Firebase Console → Configurações do projeto → Contas de serviço → Gerar nova chave privada).

## Uso

1. Na pasta do projeto (raiz):
   ```bash
   cd scripts
   npm install
   ```
2. Executar (a partir da pasta `scripts`):
   ```bash
   node import-members-bpc.js
   ```
   Por padrão o script usa o CSV em **`membros_igrebrasilparacristo/PLANILHA_SISTEMA_IGREJA_BPC_DB_V3 - MEMBERS.csv`** (pasta do projeto). Para outro arquivo:
   ```bash
   node import-members-bpc.js "C:\caminho\para\arquivo.csv"
   ```

3. Ao final, o script exibe quantos foram importados **com CPF** (ativos) e quantos **sem CPF** (pendentes).

## Tenant

Igreja utilizada: **Brasil para Cristo** — `tenantId`: `brasilparacristo_sistema`  
Coleção: `tenants/brasilparacristo_sistema/members`.

## Seed 65 membros (alternativa)

Se não tiver o CSV e precisar popular 65 membros de exemplo para o painel exibir corretamente:

```bash
npm run seed-bpc-65
```

Ou: `node seed-members-bpc-65.js`

O script adiciona membros até completar 65, sem alterar membros existentes.
