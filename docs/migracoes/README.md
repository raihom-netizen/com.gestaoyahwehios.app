# `docs/migracoes`

Pasta com material para **replicar** features deste projeto
(Gestão YAHWEH) em outros apps do mesmo ecossistema.

| Ficheiro | Para que serve |
|---|---|
| [`IOS_READER_E_LOGIN_EXPRESSO.md`](./IOS_READER_E_LOGIN_EXPRESSO.md) | Caderno técnico completo — arquivos novos, mudanças por ficheiro, configurações iOS (Info.plist, entitlements, PrivacyInfo), checklists, comandos. |
| [`IOS_DOACOES_322IV.md`](./IOS_DOACOES_322IV.md) | **Só Gestão YAHWEH** — doações no iOS via Safari (Guideline 3.2.2(iv)). Controle Total e Moova **não têm** módulo de doações. |
| [`PROMPT_APLICAR_EM_OUTROS_APPS.md`](./PROMPT_APLICAR_EM_OUTROS_APPS.md) | Prompts prontos para colar no Cursor abrindo Controle Total ou Moova. |
| **Notas App Store (por app)** | [`../../flutter_app/docs/app_store_review_notes.md`](../../flutter_app/docs/app_store_review_notes.md) — **Gestão YAHWEH**. Controle Total: `C:\Controletotalapp_Independente\docs\app_store_review_notes.md`. Moovaup: `C:\moova_super_premium\flutter_app\docs\app_store_review_notes.md`. |

## O que está documentado

1. **iOS App Store Hardening** (Guidelines 3.1.1, 3.1.3(b), 3.2.1(viii), 4.8)
   - `IosPaymentsGate` (Firebase Remote Config `exibir_pagamento_ios`).
   - `IosPaymentUnavailableView` (sem preços, CTA topo + rodapé).
   - Helper central `openUpgradePlansExternally(...)` para iOS.
   - Gate `onGenerateRoute` para `/`, `/planos`, `/pagamento` em iOS native.
   - Em iOS native, todos os CTAs de upgrade abrem Safari externo no **login web**
     do painel (`/igreja/login?after=/atualizar-plano?from=ios_app&from=ios_app&email=…`),
     não direto em `/atualizar-plano` — evita sessão sem claims (`igrejaId`). Ver
     `IosPaymentsGate.churchWebLoginThenAtualizarPlanoUri` no código-fonte.
   - **Doações (só YAHWEH):** no iOS, módulo «Doação» → `IosDonationReaderView` → Safari (`/igreja/{slug}`). Android mantém `ChurchDonationsPage`. **Controle Total / Moova:** sem módulo de doações — não aplicar.
   - Checkout MP de **licença** em iOS: Safari (login web primeiro).
   - Labels condicionais «Atualizar plano» (não «Pagar/Comprar/Assinar»).
2. **Express Renew** — rota web pública `/atualizar-plano`
   - `ExpressRenewGatePage` (header «Super Premium» + Login Expresso popup).
   - `RenewPlanPage(expressMode: true)` com plano atual + vencimento + checkout direto.
3. **Login Expresso** (faixa flutuante)
   - `ExpressLoginService` (Google silent → Apple iOS → Google UI).
   - `LoginExpressoFaixa` (widget do Controle Total).
4. **Configurações iOS obrigatórias**
   - `Info.plist` (NSCamera, NSMicrophone, NSContacts, `LSApplicationQueriesSchemes`).
   - `Runner.entitlements` (`com.apple.developer.applesignin` + `aps-environment`).
   - `PrivacyInfo.xcprivacy` + registro no `project.pbxproj` (4 entries).

## Apps alvo — o que aplicar

| App | Licença / plano (3.1.x) | Doações (3.2.2) | Login expresso |
|-----|-------------------------|-----------------|----------------|
| **Gestão YAHWEH** | ✅ Reader + Safari | ✅ `IosDonationReaderView` | ✅ Portado do CT |
| **Controle Total** | ⏳ Aplicar hardening | ❌ **N/A** (app sem doações) | ✅ **Fonte original** |
| **Moova Super Premium** | ⏳ Aplicar hardening | ❌ **N/A** (app sem doações) | ⏳ Aplicar |

## Origem e builds

Implementado em **Gestão YAHWEH** (maio/2026):

- Baseline Reader: **`11.2.295+1512`**
- URL iOS login-first: **`11.2.295+1558`**
- Doações iOS só Safari: código em **`11.2.295+1577+`** (reenviar à Apple após rejeição 3.2.2(iv))

Cadernos: [`IOS_READER_E_LOGIN_EXPRESSO.md`](./IOS_READER_E_LOGIN_EXPRESSO.md) + [`IOS_DOACOES_322IV.md`](./IOS_DOACOES_322IV.md).

**Nota:** a questão da **licença da plataforma** (renovar plano no site) segue o padrão Reader — caminho certo para aprovação 3.1.x. Doações é requisito **adicional** só no YAHWEH.
