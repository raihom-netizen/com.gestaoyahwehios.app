# Análise do painel da igreja — Gravar, editar, salvar, excluir

Verificação por módulo do painel (Igreja Clean Shell) para garantir que todas as operações de escrita (criar, editar, excluir) estão consistentes e com feedback/atualização da lista.

---

## Resumo das correções aplicadas

1. **Membros** (`members_page.dart`): `getIdToken(true)` antes de update e delete; try/catch com SnackBar de erro.
2. **Grupos** (`groups_page.dart`): `getIdToken(true)` antes de excluir grupo; try/catch com SnackBar de erro.
3. **Cadastro da igreja** (`igreja_cadastro_page.dart`): Sincronização com a coleção `igrejas` ao salvar dados e ao salvar logo, para o site público refletir nome, logo e endereço.

---

## Módulos verificados (por índice do menu)

| # | Módulo | Criar | Editar | Excluir | Refresh/Stream | Observações |
|---|--------|-------|--------|---------|----------------|-------------|
| 0 | **Painel** (Dashboard) | — | — | — | StreamBuilder | Apenas leitura. |
| 1 | **Cadastro da Igreja** | — | ✅ | — | FutureBuilder (uma vez) | Salva em `tenants` e **igrejas** (sync). Logo também em ambos. |
| 2 | **Membros** | ✅ | ✅ | ✅ | StreamBuilder | getIdToken + try/catch em update e delete. |
| 3 | **Departamentos** | ✅ | ✅ | — | FutureBuilder + _refreshDepartments() | Sem exclusão; refresh após add/update. |
| 4 | **Visitantes** | ✅ | ✅ | ✅ | StreamBuilder | Delete com getIdToken; form add/update já tinham. |
| 5 | **Grupos/Células** | ✅ | ✅ | ✅ | StreamBuilder | getIdToken + try/catch no delete. |
| 6 | **Mural de Avisos** | ✅ | ✅ | ✅ | StreamBuilder | instagram_mural: add/update/delete; avisoExpiresAt em avisos. |
| 7 | **Mural de Eventos** | ✅ | ✅ | ✅ | FutureBuilder + _refresh | events_manager: add/update/delete; refresh após ações. |
| 8 | **Pedidos de Oração** | ✅ | ✅ | ✅ | FutureBuilder + _refreshPedidos() | Add/update/delete com refresh e getIdToken. |
| 9 | **Agenda** | ✅ | — | — | _loadEvents() | Apenas adiciona (cultos/notícias); sem edição/exclusão na tela. |
| 10 | **Minha Escala** | — | ✅ (confirmação) | — | StreamBuilder | Atualiza `confirmations`. |
| 11 | **Escala Geral** | ✅ | ✅ | ✅ | FutureBuilder + _refresh | Templates e instâncias; refresh após editar/gerar/excluir. |
| 12 | **Emissão de Cartão** | — | ✅ (config) | — | — | Salva preferências em Firestore. |
| 13 | **Certificados** | — | — | — | _refreshMembers | Geração de PDF; não persiste no Firestore. |
| 14 | **Financeiro** | ✅ | ✅ | ✅ | FutureBuilder + refresh por aba | Despesas, contas, lançamentos; RefreshIndicator. |
| 15 | **Patrimônio** | ✅ | ✅ | ✅ | FutureBuilder + _refreshPatrimonioTabs | Bens, inventário; refresh após salvar/excluir. |
| 16 | **Relatórios** | — | — | — | — | Apenas leitura e export PDF. |
| 17 | **Armazenamento** | — | — | — | _load() | Leitura + teste de Drive. |
| 18 | **Configurações** | — | ✅ (feedback) | — | — | Envio de sugestão; export. |
| 19 | **Informações** | — | — | — | — | Envio de sugestão. |

---

## Padrões aplicados

- **getIdToken(true)** antes de writes em Firestore/Storage quando o módulo usa regras por role/tenantId.
- **Try/catch** em operações de escrita com SnackBar de erro para o usuário.
- **Refresh após escrita**: onde a lista usa FutureBuilder, chamar o método de refresh (ex.: `_refreshDepartments()`, `_refreshPedidos()`); onde usa StreamBuilder, o stream atualiza sozinho.
- **Sincronização tenants ↔ igrejas**: Cadastro da Igreja e logo gravam em `tenants` e em `igrejas` para o site público e o mural público usarem os mesmos dados.

---

## Módulos sem exclusão (por desenho)

- **Departamentos**: não há botão “Excluir”; apenas criar e editar.
- **Agenda**: só adiciona eventos; não há fluxo de editar/excluir na tela atual.

---

## Como testar

1. **Cadastro da Igreja**: alterar nome, endereço, salvar; alterar logo e salvar. Conferir no site público (`/igreja/{slug}`) se nome e logo aparecem.
2. **Membros**: editar um membro e salvar; excluir um membro (com confirmação). Ver lista atualizar e mensagem de sucesso/erro.
3. **Grupos**: criar, editar e excluir grupo. Ver lista atualizar.
4. **Mural de Avisos / Eventos**: criar, editar e excluir aviso e evento. Ver feed atualizar.
5. **Pedidos de Oração**: criar, editar e excluir. Ver lista atualizar.
6. **Financeiro**: adicionar/editar/excluir despesa fixa, conta e lançamento. Puxar para atualizar se necessário.
7. **Patrimônio**: adicionar/editar/excluir bem. Ver abas atualizarem após salvar/excluir.
8. **Escala Geral**: criar/editar template, gerar escala, excluir template. Ver listas atualizarem.

Se em algum módulo aparecer “permission-denied” ou a lista não atualizar após salvar/excluir, conferir as regras do Firestore e se o usuário tem o role/tenantId corretos (e se `getIdToken(true)` está sendo chamado antes da escrita).
