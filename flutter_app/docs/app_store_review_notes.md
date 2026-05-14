# Gestão YAHWEH — App Store Review (Apple)

Documento de apoio à revisão da App Store: notas para colar no App Store Connect e checklist interno.  
**Não** substitui o preenchimento oficial em [App Store Connect](https://appstoreconnect.apple.com).

---

## 1. App Review Information — English (paste in “Notes”)

**App type**  
Gestão YAHWEH is a **B2B / multi-tenant church management SaaS**. Churches use the app to manage members, schedules, finances, communications, etc.

**Digital goods / subscriptions (Guideline 3.1.x)**  
The **platform subscription** (church license) is **not sold inside the iOS app**. On **iOS**, the app runs in a **Reader / account-management** style mode: **no in-app checkout** and **no in-app prices** for the platform subscription. Managers who need to renew or change the plan are directed to complete **authentication and payment on our website** in the system browser (Safari). The iOS app then reflects the updated license via the same signed-in account / backend.

**Remote Config**  
Feature flag `exibir_pagamento_ios` (Firebase Remote Config) defaults to **off** on iOS so reviewers and end users do not see purchase UI in the native build unless we explicitly enable it for a future product decision.

**Sign in with Apple**  
Where Sign in with Apple is offered alongside other third-party login options, it follows Apple’s requirements.

**Demo / test access**  
*Fill in before submission:* test URL, email, password, tenant/church name, and steps: e.g. “Tap X → Safari opens → complete login on web → return to app”.

**What to test**  
1. Sign in as the demo church manager.  
2. Open **Settings / subscription / renew plan** entry points: the app should **not** show Mercado Pago checkout for the **platform** subscription inside the app on iOS; it should open the **website** flow if payment is needed.  
3. Core modules (members, schedules, etc.) work with the demo data.

**Contact**  
*Fill in:* name, phone, email monitored during review.

---

## 2. Notas para o revisor — Português (equipa / referência interna)

**Tipo de app**  
O **Gestão YAHWEH** é um **SaaS B2B multi-inquilino** para **gestão de igrejas** (membros, escalas, finanças, comunicação, etc.).

**Assinatura da plataforma / Guideline 3.1**  
A **assinatura da plataforma** (licença da igreja) **não é vendida dentro da app iOS**. No **iPhone/iPad**, a app funciona em modo **gestão de conta / Reader**: **sem checkout** e **sem preços** da assinatura da plataforma **dentro do binário**. Quem precisa de renovar ou mudar de plano faz **login e pagamento no site**, no **Safari** (navegador do sistema). A app iOS reflete o estado da licença após o backend atualizar.

**Remote Config**  
A flag `exibir_pagamento_ios` (Firebase Remote Config) vem **desligada por defeito** no iOS, para não aparecer UI de pagamento da plataforma na app nativa durante a revisão (e em produção), salvo decisão explícita de produto.

**Sign in with Apple**  
Onde o login com Apple é oferecido juntamente com outros fornecedores, cumpre os requisitos da Apple.

**Conta de teste**  
*Preencher antes do envio:* URL, credenciais, igreja de teste, passos (ex.: “toque em X → abre Safari → login no site → …”).

**O que testar**  
1. Entrar com o gestor de demonstração.  
2. Abrir fluxos de **renovar / atualizar plano** da plataforma: na **iOS nativa** não deve aparecer checkout da **licença** dentro da app; deve orientar para o **site**.  
3. Validar módulos principais com dados de demo.

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
- [ ] Se aparecerem valores (dízimo/oferta), deixar claro na loja que é **contribuição da igreja**, não compra da licença YAHWEH (se aplicável).

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

---

*Última actualização: documento criado para partilha interna e com a equipa de revisão Apple. Ajustar campos “Fill in / Preencher” antes de cada submissão.*
