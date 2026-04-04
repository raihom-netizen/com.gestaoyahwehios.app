# Sugestões de melhoria — Gestão YAHWEH

Documento de melhorias sugeridas para UX, performance, segurança e manutenção.

---

## 1. UX / Interface (alto impacto)

### 1.1 Feedback visual e acessibilidade
- **Skeleton loaders** em mais telas (ex.: lista de membros, eventos) para reduzir sensação de “tela em branco”.
- **Feedback tátil**: garantir `InkWell`/`Material` em todos os toques; considerar `HapticFeedback.lightImpact()` em ações importantes (salvar, upgrade).
- **Contraste e acessibilidade**: revisar contraste de textos em cinza (`onSurfaceVariant`) em fundos claros para atender boas práticas (WCAG).
- **Modo escuro**: o tema já tem `themeDataDark`; expor toggle no painel (perfil ou configurações) e persistir preferência (ex.: `shared_preferences`).

### 1.2 Navegação e descoberta
- **Breadcrumb** no painel igreja (ex.: “Painel > Membros”) em telas internas para contexto.
- **Atalhos** no dashboard: cards clicáveis que levam direto a Membros, Eventos, Financeiro, etc.
- **Busca global** (já existe `busca_global_widget.dart`): integrar no AppBar do painel igreja para buscar membros, eventos e páginas.

### 1.3 Mensagens e empty states
- **Empty states** padronizados: ícone + título + texto + CTA (conforme `PADRAO_VISUAL_CLEAN_PREMIUM.md`).
- **Snackbars** com ação “Desfazer” onde fizer sentido (ex.: exclusão de item).
- **Confirmação** em ações destrutivas (ex.: remover membro, cancelar assinatura) com diálogo claro.

---

## 2. Performance

### 2.1 Firestore e cache
- **Paginação**: listas grandes (membros, eventos) com `limit(20)` + “Carregar mais” para reduzir leituras e tempo inicial.
- **Cache**: onde possível usar `GetOptions(source: Source.cache)` para dados que mudam pouco (ex.: lista de planos).
- **Contagem de membros**: no `MembersLimitService`, considerar um campo `membersCount` no documento do tenant atualizado por Cloud Function (onCreate/onDelete em `members`) para evitar `countMembers()` em toda abertura da tela de membros.

### 2.2 App e bundle
- **Lazy loading** de rotas pesadas (ex.: relatórios, PDF) com `deferred as` se o módulo for grande.
- **Imagens**: uso de `cached_network_image` para logos e fotos de membros, com placeholder e errorWidget.

---

## 3. Segurança e dados

### 3.1 Regras Firestore
- Revisar regras para `tenants`, `subscriptions`, `config/mercado_pago` e `config/analytics`: apenas leitura/escrita onde necessário por role (admin, gestor).
- Garantir que usuários só leiam/escrevam em `tenants/{tenantId}` do próprio `tenantId` (claims ou `users`).

### 3.2 Validação
- **Backend**: validar em Cloud Functions (ex.: `createMpPreapproval`, criação de igreja) limites e permissões antes de escrever no Firestore.
- **App**: validação de CPF/e-mail em formulários (evitar dados inválidos antes de chamar backend).

---

## 4. Funcionalidades

### 4.1 Notificações e avisos
- **Push (FCM)** já está referenciado; garantir uso para: vencimento de trial/plano (ex.: 7 e 3 dias antes), avisos de limite de membros (ex.: 90% do plano).
- **Notificações in-app**: sino no header com lista de avisos (trial, limite de membros, pagamento pendente).

### 4.2 Relatórios e exportação
- **Exportar membros** (CSV/Excel) para gestão externa e backup.
- **Relatório financeiro** (entradas/saídas por período) com opção de PDF.
- **Dashboard igreja**: gráficos de evolução de membros e de eventos no tempo (dados já podem vir do Firestore).

### 4.3 Integração Mercado Pago
- **Status do pagamento** no painel: exibir “Pendente”, “Pago”, “Próxima cobrança em DD/MM” a partir de `subscription`/`billing`.
- **Link “Minha assinatura”** que abre o portal do assinante no MP (se a API permitir) ou exibe instruções para alterar/cancelar.

---

## 5. Código e manutenção

### 5.1 Testes
- **Widget tests** para componentes críticos: login, card de plano, banner de limite de membros.
- **Unit tests** para serviços: `MembersLimitService`, `SubscriptionService`, `BillingService` (com mocks de Firestore/Functions).

### 5.2 Documentação
- **README** do app: como rodar (flutter run), variáveis de ambiente, estrutura de pastas.
- **Comentários** em funções públicas de serviços e em regras de negócio (ex.: carência de 3 dias, tolerância de 5 membros).

### 5.3 Organização
- Reduzir duplicação entre `members` e `membros`: migrar gradualmente para uma única coleção (`members`) e manter fallback temporário.
- Centralizar constantes (ex.: `membersGraceOverLimit`, `_graceDays`) em um arquivo `app_constants.dart` ou no próprio serviço, para fácil ajuste.

---

## 6. DevOps e monitoramento

### 6.1 CI/CD
- **GitHub Actions** (ou similar): build web e deploy no Firebase Hosting em push na branch principal.
- **Versionamento**: script único (ex.: `bump_version.ps1`) que atualize `app_version.dart`, `pubspec.yaml` e `web/version.json`.

### 6.2 Monitoramento
- **Firebase Crashlytics**: ativar e tratar erros não capturados para acompanhar falhas em produção.
- **Analytics**: eventos importantes (login, upgrade de plano, cadastro de membro) para entender uso e funil.

### 6.3 Backup e auditoria
- **Backup** periódico do Firestore (export para GCS) configurado no projeto.
- **Auditoria**: registro de ações sensíveis (alteração de plano, exclusão de dados) em uma coleção `audit_log` ou via Cloud Functions.

---

## Priorização sugerida

| Prioridade | Item                                      | Esforço |
|-----------|--------------------------------------------|--------|
| Alta      | Paginação em listas (membros/eventos)     | Médio  |
| Alta      | Contagem de membros em cache (tenant)     | Baixo  |
| Alta      | Confirmação em ações destrutivas          | Baixo  |
| Média     | Modo escuro + preferência salva           | Médio  |
| Média     | Exportar membros (CSV)                    | Médio  |
| Média     | Status da assinatura no painel            | Baixo  |
| Baixa     | Testes automatizados                      | Alto   |
| Baixa     | Breadcrumb e busca global no painel       | Médio  |

---

*Documento gerado como sugestão. Ajuste conforme a realidade do projeto e da equipe.*
