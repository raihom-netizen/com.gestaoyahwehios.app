# Referência de Versões e Estabilidade — Gestão YAHWEH

**Uso:** Consultar este arquivo **sempre** que for alterar o sistema. Manter atualizado a cada nova versão para **estabilidade** e **segurança** do usuário.

---

## Versão atual (única fonte de verdade)

| Onde verificar | Valor atual |
|----------------|-------------|
| **flutter_app/lib/app_version.dart** | `appVersion` e `appVersionLabel` |
| **flutter_app/pubspec.yaml** | `version:` |

**Estado atual:** **10.0.19** (build 20) — conferir nos dois arquivos acima antes de qualquer mudança.

---

## Regra de versão (obrigatória)

- **A cada melhoria, correção ou ajuste:** incrementar **somente** nestes dois arquivos:
  1. `flutter_app/lib/app_version.dart` → `appVersion` e `appVersionLabel` (ex.: 10.0.19 → 10.0.20)
  2. `flutter_app/pubspec.yaml` → `version: 10.0.19+20` → `version: 10.0.20+21` (incrementar também o build number)
- **Não alterar** a lógica onde a versão é usada: main.dart, VersionFooter, UpdateChecker, version.json (gerado no build).
- **Após incrementar:** anotar nesta seção o novo número e, na tabela de histórico abaixo, a descrição breve do que mudou.

---

## Histórico de versões (referência para não quebrar o que já existe)

| Versão   | Build | Descrição resumida |
|----------|-------|--------------------|
| 10.0.19  | 20    | Lista de planos para o gestor: todos os planos por quantidade de membros; cards modernos com nome, “Até X membros”, preço mensal/anual; ordenação por membros. |
| 10.0.18  | 19    | Planos e pagamento: BillingService com billingCycle e paymentMethod; RenewPlanPage com Mensal/Anual e PIX/Cartão; EditarPrecosPlanosPage com priceAnnual; BILLING_BACKEND.md. |
| 10.0.17  | 18    | Tema Clean Premium; responsividade (admin drawer, dashboard, site); theme_clean_premium.dart; breakpoints 600/900/1200. |
| 10.0.16  | 17    | (base anterior — Painel ADM, Gestão Igrejas, Frotas integrado no app principal.) |
| …        | …     | Ao adicionar nova versão, inserir **acima** desta linha e atualizar a “Versão atual” no topo. |

---

## O que já existe no sistema (não remover sem planejamento)

### App principal (flutter_app) — Gestão YAHWEH
- **Site público:** CPF/e-mail para encontrar igreja; planos; cadastro; login.
- **Painel da igreja (gestor):** Dashboard, membros, usuários, departamentos, escalas, eventos/mural, notificações, carteirinha, financeiro, assinatura (RenewPlanPage).
- **Assinatura (gestor):** Lista de todos os planos (ref. quantidade de membros); escolha Mensal/Anual; PIX ou Cartão; checkout Mercado Pago; ativar demo.
- **Painel Master (ADM):** Abas Igrejas e Planos; Mercado Pago, Licenças Frota, Editar Preços, Dashboard, Usuários, Alertas, Planos & Cobranças, Auditoria, Customização, Suporte, Multi-Admin, Níveis de Acesso; em mobile: drawer com todos os itens.
- **Preços dos planos (ADM):** Editar Preços — priceMonthly e priceAnnual em `config/plans/items`.
- **Firebase:** Projeto gestaoyahweh-21e23; Firestore default + database `frotasveiculo` para módulo frotas.
- **Tema:** ThemeCleanPremium (theme_clean_premium.dart) aplicado no MaterialApp.
- **Serviços:** SubscriptionService (leitura subscriptions), BillingService (createMpCheckout, activatePlanDemo), auth, Firestore.

### App separado (gestao_frotas)
- Firebase GESTAOFROTAS (gestaofrotas-2f19d); domínio gestaofrotas-2f19d.web.app.
- Landing, login, app shell, painel admin (licenças, usuários, recebimentos); backup Drive (pasta ID fixa); master raihom@gmail.com.

### Banco e segurança
- **subscriptions:** somente servidor (Cloud Functions); app só lê.
- **config/plans/items:** leitura para gestor; escrita só ADM (Editar Preços).
- **config/mercado_pago:** só ADM.
- Regras em `firestore.rules` (projeto principal) e `firestore-gestaofrotas.rules` (GESTAOFROTAS).

---

## Estabilidade e segurança para o usuário

1. **Versão:** Sempre que mudar algo, incrementar versão nos dois arquivos e anotar aqui.
2. **Referência completa:** Ver também `REFERENCIA_SISTEMA_E_ALTERACOES.md` para estrutura, arquivos críticos e regras de mudança.
3. **Não alterar por engano:** Rotas (main.dart), tema global, firebase_options, regras Firestore e pontos que afetam login/assinatura devem ser tocados com cuidado.
4. **Testes:** Após mudanças, validar login, painel da igreja, assinatura e ADM nas rotas principais.
5. **Backend:** Alterações em pagamento/assinatura devem estar alinhadas com `flutter_app/lib/services/BILLING_BACKEND.md` e com as regras de `subscriptions`.

---

## Como usar este arquivo

- **Antes de mudar o sistema:** Ler a “Versão atual” e o “Histórico de versões” para saber o que já está entregue.
- **Depois de lançar nova versão:** Atualizar a tabela de histórico e a “Versão atual” neste arquivo.
- **Para garantir estabilidade:** Manter este arquivo e o `REFERENCIA_SISTEMA_E_ALTERACOES.md` como referência única de versões e estado do sistema.

---

---

## Regras do banco e deploy no domínio

- **Regras Firestore** (arquivo `firestore.rules`): garantem que **nenhuma igreja vê dados da outra**; só o **master** (role MASTER em users) tem acesso a tudo. Master de referência: CPF 94536368191, Raihom Severino Barbosa, raihom@gmail.com; gestor da igreja Brasil para Cristo.
- **Como publicar versão e regras:** seguir o guia **`COMO_SUBIR_VERSAO_E_REGRAS.md`** (Firebase Console ou CLI para regras; build web + hosting para o domínio).

---

*Última atualização: fev/2026. Manter este arquivo atualizado a cada nova versão.*
