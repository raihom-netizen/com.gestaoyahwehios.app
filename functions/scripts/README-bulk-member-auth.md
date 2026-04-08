# Criar autenticação Firebase para todos os membros

## O que faz

- Função em nuvem **`bulkEnsureMembersAuth`** (após `firebase deploy --only functions`)
- Percorre `igrejas/{id}/membros` e, para quem **não tem `authUid`**, cria usuário com **e-mail do cadastro** (ou `CPF@membro.gestaoyahweh.com.br`) e senha **`123456`**
- Grava `authUid` no documento do membro, `users/{uid}`, custom claims e `usersIndex` por CPF
- **Pendentes**: `active: false` no Auth — continuam bloqueados no app até o gestor aprovar

## Pelo app (recomendado)

1. Faça deploy: `firebase deploy --only functions:bulkEnsureMembersAuth,functions:createMemberLoginFromPublic,...`
2. Entre como **gestor/adm** da igreja → **Configurações** → **Criar logins para membros sem conta**

## MASTER — todas as igrejas

Chame a callable **sem** `tenantId` (só conta MASTER / admin no token):

```bash
# Após deploy, no cliente ou via extensão — ou use o painel Firebase > Functions > testar
# Com tenantId vazio e role MASTER, processa todas as igrejas.
```

## Cadastro novo (interno ou externo)

O app já chama **`createMemberLoginFromPublic`** após salvar o membro. Essa função agora lê **`igrejas/{tenantId}/membros`** (correção anterior: antes apontava só para `tenants/.../members`).

Senha padrão unificada: **123456**.
