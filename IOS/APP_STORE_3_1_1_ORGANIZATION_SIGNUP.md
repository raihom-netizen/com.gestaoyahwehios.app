# App Store — Guideline 3.1.1 (cadastro de organização no iOS)

## O que a Apple exige

No app **iOS nativo** (iPhone/iPad) **não** pode existir fluxo de **criar conta de igreja/empresa/organização** nem escolha de plano com compra dentro do binário.

- **Permitido:** login com conta **já existente**; link para o **site** (Safari) para cadastro, planos e licença.
- **Bloqueado:** ecrã «Criar conta — teste grátis», Google/Apple/e-mail para **nova** igreja, `/signup/completar-dados`, etc.

## Implementação (Gestão YAHWEH)

| Peça | Ficheiro |
|------|----------|
| Gate iOS | `lib/services/ios_payments_gate.dart` — `hideOrganizationSignup`, `openOrganizationSignupExternally()` |
| Ecrã iOS (só link web) | `lib/ui/widgets/ios_organization_signup_web_page.dart` |
| Rotas bloqueadas | `main.dart` — `/signup`, `/signup/completar-dados`, `/cadastro`, `/igreja/*/cadastro` → ecrã web ou Safari |
| Login igreja | `login_page.dart` — «Cadastrar igreja no site»; sem CTA in-app de nova igreja |
| OAuth novo gestor | `gestor_oauth_onboarding_service.dart` — sign-out + mensagem se conta sem `igrejaId` |

URL de cadastro: `https://gestaoyahweh-21e23.web.app/signup?from=ios_app&utm_medium=organization_signup`

## Resposta sugerida no App Store Connect

> No iOS, the app is a client for existing church accounts only. Organization registration and subscription selection are not available in the app; users open our website in Safari via «Abrir cadastro e planos no site». Login with Google, Apple, or email remains for users who already have an account. Build 11.2.295 (1593)+ reflects this change.

## Login iOS (sem compra no app)

| Rota / ecrã | Comportamento iOS nativo |
|-------------|-------------------------|
| `/igreja/login`, `/login` | Só login; pós-login → `/painel` (não checkout in-app) |
| `/planos`, `/pagamento`, `/atualizar-plano` | `IosPaymentUnavailableView` → Safari |
| `/signup`, cadastro igreja | `IosOrganizationSignupWebPage` ou Safari |
| Painel — «Adquirir plano» | Abre site (gate `exibir_pagamento_ios`) |
| OAuth sem igreja | Sign-out + mensagem; cadastro no site |

## Teste antes de reenviar

1. iPad: abrir app → não deve aparecer «Criar conta - teste grátis 30 dias» com formulário.
2. Qualquer atalho «Cadastrar» → ecrã informativo ou Safari em `/signup`.
3. Login `/igreja/login` → só entrar; botão «Cadastrar igreja no site».
4. Menu plano / atualizar plano → abre Safari, sem preços com CTA de compra no login.
