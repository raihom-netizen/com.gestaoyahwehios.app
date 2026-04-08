# Referência do Sistema e Alterações — Gestão YAHWEH

**Objetivo:** Ter uma referência única de tudo que foi feito no projeto. Usar este arquivo antes de qualquer mudança para **não quebrar o sistema**, manter **segurança** e **estabilidade** entre versões.

**Versões e estado atual:** Consultar **`REFERENCIA_VERSOES_ESTABILIDADE.md`**. Para **subir a versão e as regras no domínio:** **`COMO_SUBIR_VERSAO_E_REGRAS.md`**.

---

## 1. Regras obrigatórias (sempre seguir)

### 1.1 Controle de versão
- **A cada melhoria/correção:** incrementar versão em **dois arquivos apenas**:
  - `flutter_app/lib/app_version.dart` → `const String appVersion = 'X.Y.Z';` e `appVersionLabel`
  - `flutter_app/pubspec.yaml` → `version: X.Y.Z+BuildNumber` (incrementar também o build number)
- **Não alterar** onde a versão já é usada: main.dart, VersionFooter, UpdateChecker, version.json (gerado no build).

### 1.2 Estilo e arquitetura (`.cursorrules`)
- Interfaces **Apple Style**: limpas, muito espaçamento, fontes elegantes.
- Widgets modernos quando fizer sentido; código **modular e limpo** (Clean Architecture).
- Priorizar Dashboard com cards interativos e feedback visual/tátil.

---

## 2. Estrutura do repositório

```
gestao_yahweh_premium_final/
├── flutter_app/                    # App principal: Gestão YAHWEH (igrejas + ADM)
│   ├── lib/
│   │   ├── main.dart               # Rotas, tema, UpdateChecker
│   │   ├── app_version.dart        # Única fonte da versão
│   │   ├── firebase_options.dart    # Firebase projeto principal (gestaoyahweh-21e23)
│   │   ├── ui/
│   │   │   ├── theme_clean_premium.dart   # Tema global Clean Premium
│   │   │   ├── admin_panel_page.dart      # Painel Master (drawer em mobile)
│   │   │   ├── editar_precos_planos_page.dart  # Preços mensal + anual
│   │   │   └── ...
│   │   ├── pages/
│   │   │   ├── site_public_page.dart       # Home pública (CPF/email, planos)
│   │   │   └── plans/
│   │   │       └── renew_plan_page.dart    # Assinatura: plano + Mensal/Anual + PIX/Cartão
│   │   └── services/
│   │       ├── billing_service.dart        # createMpCheckout(planId, billingCycle, paymentMethod)
│   │       ├── subscription_service.dart   # Leitura subscriptions
│   │       └── BILLING_BACKEND.md          # Instruções para Cloud Functions
│   └── pubspec.yaml
├── gestao_frotas/                  # App SEPARADO: Controle de Frotas (Firebase GESTAOFROTAS)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── firebase_options.dart    # gestaofrotas-2f19d
│   │   ├── config/app_config.dart  # driveFolderId, master (raihom@gmail.com)
│   │   ├── pages/ (landing, login, app_shell)
│   │   └── ui/admin_panel_page.dart
│   └── README.md
├── firestore.rules                 # Regras Firestore projeto principal
├── firestore-gestaofrotas.rules    # Regras Firestore projeto GESTAOFROTAS
└── REFERENCIA_SISTEMA_E_ALTERACOES.md   # ESTE ARQUIVO
```

- **Dois sistemas distintos:** (1) Gestão YAHWEH (igrejas, ADM, site, planos) no Firebase **gestaoyahweh-21e23**; (2) Gestão Frotas no Firebase **GESTAOFROTAS** (gestaofrotas-2f19d), domínio **gestaofrotas-2f19d.web.app**.

---

## 3. Histórico de alterações (referência para não reverter sem querer)

### 3.1 Desmembramento do Controle de Frotas
- Criado app **separado** em `gestao_frotas/` com Firebase **GESTAOFROTAS**.
- Regras em `firestore-gestaofrotas.rules` (master: raihom@gmail.com; coleções: usuarios, frota_licenses, config, recebimentos, frota_veiculos, etc.).
- Config: `gestao_frotas/lib/config/app_config.dart` — driveFolderId `1VjmVUbRjOD0l7gu9SLsbzqDvO1JUONLN`, master raihom@gmail.com, CPF 94536368191.
- App principal (flutter_app) **não** foi removido; frotas pode ser acessado via link para o app separado.

### 3.2 Tema Clean Premium e responsividade (Gestão Igrejas / ADM)
- **Tema:** `flutter_app/lib/ui/theme_clean_premium.dart` — cores (primary, surfaceVariant), espaçamentos (spaceSm a spaceXxl), raios (radiusSm a radiusXl), ThemeData (AppBar, Card, Input, Buttons, TabBar, Dialog, Drawer). Breakpoints: breakpointMobile 600, breakpointTablet 900, breakpointDesktop 1200.
- **main.dart:** `theme: ThemeCleanPremium.themeData` no MaterialApp.
- **Painel Admin:** Em largura < 900px usa **Drawer** com todos os itens (Home, Mercado Pago, Licenças Frota, Dashboard, Usuários, etc.); em desktop mantém botões no AppBar. Aba Igrejas: em mobile métricas em Wrap, busca/filtros em Column.
- **Dashboard (igreja):** Mural + Estatísticas em Column em mobile, Wrap em desktop; Acessos rápidos com tileWidth responsivo; _TopBar com texto e ícones reduzidos em mobile.
- **Site público:** Já tinha isMobile; passou a usar ThemeCleanPremium.spaceMd no padding.

### 3.3 Planos, licença e pagamento no painel da igreja
- **Editar Preços (ADM):** `editar_precos_planos_page.dart` grava em `config/plans/items/{id}` os campos **priceMonthly** e **priceAnnual**.
- **Assinatura (igreja):** `renew_plan_page.dart` — escolha de **plano** (Firestore config/plans/items), **Mensal ou Anual**, **PIX ou Cartão parcelado**. Chama `BillingService().createMpCheckout(planId, billingCycle, paymentMethod)` e abre o link do Mercado Pago. Após sucesso redireciona para `/painel`.
- **BillingService:** Novos enums `BillingCycle` (monthly, annual) e `PaymentMethod` (pix, card). `createMpCheckout(planId, billingCycle, paymentMethod)` chama a callable `createMpPreapproval` com esses três parâmetros. `createMpPreapproval(planId)` mantido para compatibilidade (usa createMpCheckout).
- **Backend:** O arquivo `flutter_app/lib/services/BILLING_BACKEND.md` descreve o que a Cloud Function `createMpPreapproval` deve aceitar (billingCycle, paymentMethod) e como gravar intenção/subscription no banco.

### 3.4 Gravação no banco (conferência)
- **config/plans/items:** EditarPrecosPlanosPage (priceMonthly, priceAnnual); Super Admin (batch).
- **config/mercado_pago:** MercadoPagoAdminPage.
- **subscriptions:** apenas **server** (Cloud Functions); app só lê.
- **Painel igreja:** tenants/{id}/members, tenants/{id}/users, igrejas/{id}/departamentos, escalas, noticias, etc. — conforme cada página (members_page, schedules_page, events_manager_page, etc.).
- **Frotas (banco frotasveiculo no projeto principal):** frota_licenses, frota_veiculos, etc. — escritas pelas páginas de frota e admin de licenças.

---

## 4. Arquivos críticos (evitar mudanças que quebrem comportamento)

| Arquivo | Uso |
|--------|-----|
| `flutter_app/lib/app_version.dart` | Única fonte da versão; alterar só o número conforme regra. |
| `flutter_app/lib/main.dart` | Rotas, tema, guards (admin, master). Não remover rotas de painel/igreja/frotas sem ajustar links. |
| `flutter_app/lib/firebase_options.dart` | Projeto Firebase principal. Não trocar de projeto por engano. |
| `flutter_app/lib/services/firestore_frota.dart` | Acesso ao banco **frotasveiculo** (databaseId). Usado por páginas de frota no app principal. |
| `gestao_frotas/lib/firebase_options.dart` | Projeto GESTAOFROTAS. Não misturar com gestaoyahweh. |
| `gestao_frotas/lib/config/app_config.dart` | Master e Drive; usado em seed e admin. |
| `firestore.rules` / `firestore-gestaofrotas.rules` | Regras de segurança; alterar com cuidado. |
| `flutter_app/lib/ui/theme_clean_premium.dart` | Tema global; alterar cores/breakpoints impacta todo o app. |

---

## 5. Firebase e banco de dados

### 5.1 Projeto principal (gestaoyahweh-21e23)
- **Firestore:** default + database **frotasveiculo** (módulo frotas no app principal).
- **Coleções principais:** users, tenants, tenants/{id}/members, igrejas, subscriptions (server only), config/plans/items, config/mercado_pago, config/appDownloads, config/sistema, etc.
- **Regras:** firestore.rules (isMaster, canManageChurch, sameChurch, etc.).

### 5.2 Projeto GESTAOFROTAS (gestaofrotas-2f19d)
- **Firestore:** apenas banco **(default)**.
- **Coleções:** usuarios, frota_licenses, config (app, mercado_pago), recebimentos, frota_veiculos, frota_abastecimentos, etc.
- **Regras:** firestore-gestaofrotas.rules (master raihom@gmail.com).

---

## 6. Como fazer mudanças com segurança

1. **Antes de alterar:** Ler este arquivo e verificar se a mudança afeta rotas, tema, versão, Firebase ou regras.
2. **Versão:** Sempre incrementar em `app_version.dart` e `pubspec.yaml` ao fazer melhoria/correção.
3. **Novas features:** Preferir novos arquivos ou widgets sem reescrever fluxos críticos (login, auth_gate, subscription).
4. **Backend (Cloud Functions):** Qualquer mudança em assinatura/pagamento deve estar alinhada com `BILLING_BACKEND.md` e com as regras de `subscriptions`.
5. **App Frotas:** Alterações no sistema de igrejas não devem depender do app `gestao_frotas`; são projetos separados.

---

## 7. Resumo rápido para pesquisa

- **Versão:** alterar só `app_version.dart` + `pubspec.yaml`.
- **Tema/UI:** theme_clean_premium.dart; breakpoints 600 / 900 / 1200.
- **Planos/Preços:** config/plans/items (priceMonthly, priceAnnual); editar em EditarPrecosPlanosPage.
- **Assinatura igreja:** RenewPlanPage → **lista de todos os planos** ordenada por quantidade de membros (ref. membros), cards modernos com nome, “Até X membros”, preço mensal e anual; depois Mensal/Anual, PIX/Cartão → createMpCheckout → Mercado Pago; backend grava subscription.
- **Frotas separado:** pasta gestao_frotas, Firebase GESTAOFROTAS, firestore-gestaofrotas.rules.
- **Admin responsivo:** drawer em < 900px; aba Igrejas com Wrap/Column em mobile.

---

*Última atualização de referência: fev/2026. Ao fazer novas alterações significativas, atualize este arquivo para manter a referência sempre útil.*
