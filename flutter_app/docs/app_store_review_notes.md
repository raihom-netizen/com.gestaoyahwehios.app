# Gestão YAHWEH — App Store Review (Apple)

Documento de apoio à revisão da App Store: notas para colar no App Store Connect e checklist interno.  
**Não** substitui o preenchimento oficial em [App Store Connect](https://appstoreconnect.apple.com).

---

## 1. App Review Information — English (paste in “Notes”)

**App type**  
Gestão YAHWEH is a **B2B / multi-tenant church management SaaS**. Churches use the app to manage members, schedules, finances, communications, etc.

**Digital goods / subscriptions (Guideline 3.1.x)**  
The **platform subscription** (church license) is **not sold inside the iOS app**. On **iOS**, the app is a **Reader mirror**: **no in-app checkout**, **no subscription prices**, **no “upgrade plan” buttons**, and **no external links to the sales/checkout website**. When the license expires, a **neutral blocked screen** appears (contact administrator / use the web panel — text only, no payment CTAs). Payment (Mercado Pago PIX / card) happens **only on the website** in a browser outside the app; Firestore is updated via webhook; the app reads the license status after login.

**Android**  
Managers can tap **Alterar plano** — opens the web flow (`/atualizar-plano`) in Chrome for Mercado Pago (PIX or card up to 6 installments).

**Remote Config**  
Feature flag `exibir_pagamento_ios` (Firebase Remote Config) defaults to **off** on iOS so reviewers and end users do not see purchase UI in the native build unless we explicitly enable it for a future product decision.

**Sign in with Apple**  
Where Sign in with Apple is offered alongside other third-party login options, it follows Apple’s requirements.

**Demo / test access**  
*Fill in before submission:* test URL, email, password, tenant/church name, and steps: e.g. “Tap X → Safari opens → complete login on web → return to app”.

**Charitable donations / church contributions (Guideline 3.2.2(iv))**  
The app is **not** a registered charitable organization. On **iOS**, the in-app **“Donation”** menu does **not** collect PIX or card payments. It only opens the **church’s public website in Safari**, where members may contribute (same as the web). **Android** retains in-app donation tools for church treasurers.

**What to test**  
1. Sign in as the demo church manager.  
2. Open **Settings / subscription / renew plan** entry points: the app should **not** show Mercado Pago checkout for the **platform** subscription inside the app on iOS; it should open the **website** flow if payment is needed.  
3. Open **Donation** on iOS: should show an informational screen and open **Safari** to the church public page — **no** PIX/card form inside the native app.  
4. Core modules (members, schedules, etc.) work with the demo data.

**Contact**  
*Fill in:* name, phone, email monitored during review.

---

## 2. Notas para o revisor — Português (equipa / referência interna)

**Tipo de app**  
O **Gestão YAHWEH** é um **SaaS B2B multi-inquilino** para **gestão de igrejas** (membros, escalas, finanças, comunicação, etc.).

**Assinatura da plataforma / Guideline 3.1**  
A **assinatura da plataforma** **não é vendida dentro da app iOS**. No **iPhone/iPad**, a app é **espelho**: **sem checkout**, **sem preços**, **sem botão «Alterar plano»** e **sem links externos** para o site de vendas. Licença vencida → ecrã neutro (contactar administrador / painel web — só texto). Pagamento (Mercado Pago) só na **web**; webhook atualiza Firestore; a app lê o estado após login.

**Android**  
Gestor toca **Alterar plano** → abre `/atualizar-plano` no Chrome (PIX / cartão até 6x).

**Remote Config**  
A flag `exibir_pagamento_ios` (Firebase Remote Config) vem **desligada por defeito** no iOS, para não aparecer UI de pagamento da plataforma na app nativa durante a revisão (e em produção), salvo decisão explícita de produto.

**Sign in with Apple**  
Onde o login com Apple é oferecido juntamente com outros fornecedores, cumpre os requisitos da Apple.

**Conta de teste**  
*Preencher antes do envio:* URL, credenciais, igreja de teste, passos (ex.: “toque em X → abre Safari → login no site → …”).

**Doações / Guideline 3.2.2(iv)**  
A app **não** é ONG registada. No **iOS**, o menu **Doação** **não** recolhe PIX/cartão: abre o **site público da igreja no Safari**. No **Android**, o módulo de doações do tesoureiro mantém-se.

**O que testar**  
1. Entrar com o gestor de demonstração.  
2. Abrir fluxos de **renovar / atualizar plano** da plataforma: na **iOS nativa** não deve aparecer checkout da **licença** dentro da app; deve orientar para o **site**.  
3. Menu **Doação** no iPhone: ecrã informativo + Safari — **sem** formulário de pagamento no binário.  
4. Validar módulos principais com dados de demo.

**Contacto**  
*Preencher:* nome, telefone, e-mail.

---

## 3. Checklist (metadados, capturas, loja)

### App Store Connect — texto
- [ ] **Descrição / promo text**: não prometer “compre o plano na app” no iOS; falar em **gestão** e, se necessário, “renovação da licença no **site**”.
- [ ] **Keywords**: evitar associação a compra in-app da licença da plataforma no iOS.
- [ ] **Categoria** coerente (ex.: Produtividade / Negócios).
- [ ] **Support URL** e **Marketing URL** válidos; **política de privacidade** acessível e alinhada ao app.

### Capturas de ecrã (iPhone)
- [ ] **Sem preços** da assinatura da plataforma nas capturas do **iOS**, se a política for “só na web”.
- [ ] Mostrar **funcionalidades** (membros, escalas, mural, etc.), não o checkout da licença.
- [ ] **iOS:** capturas **sem** ecrã de PIX/cartão de dízimo **dentro** da app (doação = Safari).
- [ ] Se aparecerem valores na web/Android, deixar claro que é **contribuição da igreja**, não licença YAHWEH.

### Binary / comportamento
- [ ] Confirmar **`exibir_pagamento_ios` = false** (Remote Config) para o build enviado à revisão.
- [ ] Testar em dispositivo limpo: **nenhum** ecrã de preço/checkout da **licença** dentro da app iOS.
- [ ] Fluxo “Atualizar plano” abre **Safari** e o site; regressão à app sem crash.

### Privacidade e compliance
- [ ] **Privacy Nutrition Labels** alinhados com Firebase, analytics, notificações, etc.
- [ ] **App Privacy** no Connect: consistente com `PrivacyInfo.xcprivacy` / SDKs.
- [ ] **Tracking**: se não usarem ATT, não fazer tracking que exija prompt (revisar SDKs).

### Login (4.8 / UX)
- [ ] **Sign in with Apple** visível e funcional onde há Google/outros.
- [ ] Conta de teste com **passo a passo** nas notas (incl. 2FA desligado ou código acordado).

### IAP
- [ ] Se **não** usarem IAP para a licença: **não** mencionar “compras integradas” da licença na descrição iOS; as notas explicam o modelo **web**.

### Após aprovação
- [ ] Processo interno antes de alterar `exibir_pagamento_ios` ou metadados que conflitem com a guideline 3.1.

---

## 4. Onde isto se reflete no código (referência técnica)

| Tema | Ficheiros / mecanismos |
|------|-------------------------|
| Gate iOS + Remote Config `exibir_pagamento_ios` | `lib/services/ios_payments_gate.dart` |
| Inicialização do gate | `lib/main.dart` |
| Renovação sem checkout in-app (Reader) | `lib/ui/pages/plans/renew_plan_page.dart`, `lib/ui/widgets/ios_payment_unavailable_view.dart` |
| Rotas `/planos` e `/pagamento` no iOS | `lib/main.dart` (`onGenerateRoute`) |
| Doações iOS (3.2.2(iv)) | `lib/ui/widgets/ios_donation_reader_view.dart`, `ios_payments_gate.dart` (`openChurchDonationsExternally`), `igreja_clean_shell.dart` |
| Migração / outros apps | `docs/migracoes/IOS_DOACOES_322IV.md` (só YAHWEH; CT/Moova sem doações) |

---

*Última actualização: 2026-05-18 — doações iOS Safari-only + Reader licença. Ajustar campos “Fill in / Preencher” antes de cada submissão.*
