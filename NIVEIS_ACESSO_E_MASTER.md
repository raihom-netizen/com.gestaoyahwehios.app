# Níveis de Acesso — Gestão YAHWEH

## Resumo

- **MASTER (Gestor Master Geral)** — Você. Controle total: todas as igrejas, Frotas, logs, remover/editar/criar qualquer dado.
- **GESTOR / ADM (Gestor Local)** — Controla tudo **dentro da sua igreja**. Uma igreja não vê a outra.
- **LÍDER** — Cria/edita escalas, eventos e publicações na sua igreja.
- **USER** — Acesso básico; motorista pode lançar abastecimento.

## Ser Master e Gestor Local da mesma igreja (ex.: O Brasil Para Cristo)

Para você ser ao mesmo tempo **Gestor Master Geral** e **Gestor Local** da igreja **O Brasil Para Cristo**:

1. No Firebase Authentication, o seu usuário deve ter **custom claims**:
   - `role`: `"MASTER"`
   - `igrejaId`: **ID do documento da igreja** "O Brasil Para Cristo" na coleção `tenants` (ou o mesmo ID em `igrejas`, se for o identificador da igreja).

2. Como isso é definido:
   - Por **Cloud Function** (por exemplo `setUserRole` ou uma função administrativa que defina claims).
   - Ou manualmente no Firebase Admin (Auth → usuário → custom claims):  
     `{ "role": "MASTER", "igrejaId": "<ID_IGREJA_O_BRASIL_PARA_CRISTO>" }`.

3. Com isso:
   - **Master**: você acessa o painel admin global, todas as igrejas, Frotas, auditoria e pode remover/editar/criar tudo.
   - **Gestor Local**: ao usar o app no contexto da igreja O Brasil Para Cristo (`igrejaId` igual ao seu claim), você controla tudo dessa igreja como gestor local.

## Logs de auditoria

- **Coleção**: `auditoria`.
- **Quem escreve**: apenas as Cloud Functions (banco, Drive, ações críticas).
- **Quem lê**:
  - **Master**: vê todos os registros (uso de banco, Google Drive, ações em qualquer igreja).
  - **Gestor Local**: vê apenas registros da **sua igreja** (`igrejaId` no documento = igreja do seu token).

Eventos registrados incluem, entre outros:

- Backup diário 00h (Firestore + Drive)
- Criação/atualização de pastas no Drive (por tenant ou global)
- Alteração de perfil de usuário (`setUserRole`)
- Ativar/inativar usuário (`setUserActive`)
- Criação/edição de usuário no tenant (`upsertTenantUser`)
- Criação de novo tenant (igreja) e pastas Drive
- Arquivamento de mídias para o Drive

## Regras de segurança (Firestore)

- **Uma igreja não vê a outra**: leitura/escrita em `tenants/{tenantId}/...` e `igrejas/{tenantId}/...` exige `request.auth.token.igrejaId == tenantId` (ou `role == MASTER`).
- **Master pode remover tudo**: onde houver `delete`, o Master está autorizado (membros, frota por igreja, assinaturas, vendas, licenças, frota_licenses, frota_customers, etc.).
- **Frotas (módulo global)**: apenas Master/ADM leem e escrevem; apenas Master pode deletar.
