# Prompt — aplicar iOS App Store Hardening + Login Expresso + Express Renew em outro app

> Cole o conteúdo de **uma** das seções abaixo no chat do Cursor
> dentro do projeto alvo (Controle Total ou Moova). O agente vai ler
> o caderno técnico e replicar a lógica.
>
> **Pré-requisito:** copie a pasta `docs/migracoes/` deste projeto
> (`c:\gestao_yahweh_premium_final\docs\migracoes`) para a raiz do
> projeto alvo, ou referencie o caminho absoluto no prompt.

---

## A) Para `C:\Controletotalapp_Independente`

> _Este projeto **já tem** o «Login expresso» (foi a fonte original).
> Falta aplicar o **iOS App Store Hardening**: Reader, Multiplatform
> Service, Privacy Manifest, entitlements, e o fluxo express na web._
>
> **Não tem módulo de doações** — **pular PARTE 4** (só Gestão YAHWEH)._

```
Aplique no Controle Total App o mesmo iOS App Store Hardening que foi
implementado no Gestão YAHWEH (baseline `11.2.295+1512`, URL Safari
login-first `11.2.295+1558`).

Caderno técnico (LEIA antes de mexer):
C:\gestao_yahweh_premium_final\docs\migracoes\IOS_READER_E_LOGIN_EXPRESSO.md

Faça exatamente isto, na ordem:

PARTE 1 — Reader/Multiplatform (Guideline 3.1.1 / 3.1.3(b))

1. Adicione `firebase_remote_config: ^5.4.0` ao pubspec do app.
2. Crie `lib/services/ios_payments_gate.dart` com a mesma API
   (`isIosNative`, `paymentsAllowed`, `shouldHidePayments`,
   `initialize`, chave `exibir_pagamento_ios`, default `false`).
3. Crie `lib/ui/widgets/ios_payment_unavailable_view.dart` SEM PREÇOS
   nem toggle Mensal/Anual: apenas nome dos planos, capacidade,
   recursos. CTA «Atualizar plano no site» NO TOPO **e** NO RODAPÉ
   (mesmo botão que abre Safari na URL pública). A URL deve ser o **login web**
   do painel com `after` whitelistado para `/atualizar-plano?from=ios_app`
   (no YAHWEH: `churchWebLoginThenAtualizarPlanoUri` / `openUpgradePlansExternally`).
   No Controle Total / Moova, use o path equivalente de login + query `after`,
   **não** abrir só `/atualizar-plano` como primeira página (evita `igrejaId` /
   claims ausentes).
4. Inicialize `IosPaymentsGate.initialize()` em `main.dart` antes do
   `runApp`, não-bloqueante.
5. Na página de planos / renovação, no início do `build`, retorne
   `IosPaymentUnavailableView` quando
   `IosPaymentsGate.shouldHidePayments` for `true` E `expressMode`
   for `false`.
6. No `onGenerateRoute` do `main.dart`, ANTES do switch principal,
   adicione gate iOS native que intercepta `/`, `/planos`,
   `/pagamento` (todos viram `LoginPage` ou
   `IosPaymentUnavailableView` em iOS). Veja seção 2.3 do caderno.

PARTE 2 — Express Renew (rota web `/atualizar-plano` + login web antes no iOS)

7. Crie `lib/ui/pages/plans/express_renew_gate_page.dart`:
   - StreamBuilder<User?> em authStateChanges.
   - Logado → `RenewPlanPage(expressMode: true)`.
   - Deslogado → tela própria com header «Super Premium» (gradient da
     marca + logo do app + título «Atualizar plano»), card de login
     com botão «Login Expresso» que faz signInWithPopup do Google na
     web (com fallback signInWithRedirect em Safari/iOS).
   - Aceita `?email=...` para badge "Vamos entrar com <email>".
   - Link discreto «Entrar com e-mail e senha» empilha LoginPage
     tradicional com `afterLoginRoute=/atualizar-plano` ou, se fluxo iOS,
     `/atualizar-plano?from=ios_app` (manter `openedFromIosApp`).
8. Em `RenewPlanPage`, adicione prop `expressMode: bool` (default
   false). Em expressMode:
   - Header dedicado com plano atual + vencimento + email do user.
   - Hide do botão demo, AppBar customizada.
   - Após pagamento, mostrar tela de confirmação dedicada (sem
     redirecionar).
9. No `main.dart` `onGenerateRoute`, registre:
   - rota **login web** (ex.: `/igreja/login`) → `LoginPage` com `afterLoginRoute`
     vindo da query `after` (whitelist) e default seguro;
   - rota `/atualizar-plano` → `ExpressRenewGatePage(prefillEmail: …,
     openedFromIosApp: uri.queryParameters['from'] == 'ios_app')`.

PARTE 3 — Labels e textos condicionais

10. Localize todos os botões/diálogos/banners que digam «Pagar»,
    «Comprar», «Assinar», «Adquirir», «Renovar agora», «Ver planos»,
    «Vincule o pagamento» nos fluxos de gestor e:
    - troque o LABEL para «Atualizar plano» / «atualize seu plano no
      site» quando `IosPaymentsGate.shouldHidePayments` for `true`;
    - no iOS native, faça todos esses CTAs abrirem Safari externo no
      **login web** com destino pós-login `/atualizar-plano?from=ios_app`
      (helper `openUpgradePlansExternally` / `churchWebLoginThenAtualizarPlanoUri`
      no YAHWEH — replicar no Controle Total; não deixar `Navigator.push(RenewPlanPage())`
      nesses pontos).
    - implemente um helper central no gate (ex.:
      `IosPaymentsGate.openUpgradePlansExternally(source: ...)`) e
      reutilize em todos os botões/ações.
11. Em `login_page.dart` ou equivalente, no card de planos pré-login:
    em iOS native (`IosPaymentsGate.isIosNative`), esconder coluna de
    preço e trocar «Ver página completa de planos» por «Atualizar
    plano no site» que abre Safari no URL de **login web** com `after`
    para `/atualizar-plano?from=ios_app` (mesmo helper do gate; não usar
    só `/atualizar-plano` como primeira página).

PARTE 4 — Doações — **PULAR no Controle Total**

> O Controle Total **não** tem dízimos/ofertas. **Não** criar
> `IosDonationReaderView` aqui. Se no futuro existir módulo semelhante,
> seguir `docs/migracoes/IOS_DOACOES_322IV.md` (padrão YAHWEH).

PARTE 5 — Configurações iOS (`ios/`)

13. `ios/Runner/Info.plist` — adicionar:
    - `NSCameraUsageDescription`
    - `NSMicrophoneUsageDescription`
    - `NSContactsUsageDescription` (se app importa contatos)
    - `LSApplicationQueriesSchemes` com https/http/mailto/tel/sms/whatsapp
    Manter as existentes (NSFaceIDUsageDescription, NSPhotoLibrary*,
    NSLocation*, NSCalendars).
14. `ios/Runner/Runner.entitlements` — garantir AS DUAS keys:
    - `com.apple.developer.applesignin = ['Default']` (Guideline 4.8)
    - `aps-environment = production` (firebase_messaging)
15. CRIAR `ios/Runner/PrivacyInfo.xcprivacy` (Privacy Manifest
    obrigatório desde maio/2024) com:
    - NSPrivacyTracking=false, NSPrivacyTrackingDomains vazio.
    - NSPrivacyCollectedDataTypes (e-mail, nome, fotos, telefone,
      crash data, location, userID — tudo Linked=true,
      Tracking=false).
    - NSPrivacyAccessedAPITypes com 4 categorias e reasons:
      FileTimestamp (C617.1), UserDefaults (CA92.1), DiskSpace
      (E174.1), SystemBootTime (35F9.1).
    Conteúdo completo em
    `c:\gestao_yahweh_premium_final\flutter_app\ios\Runner\PrivacyInfo.xcprivacy`.
16. REGISTRAR o PrivacyInfo no `ios/Runner.xcodeproj/project.pbxproj`
    em 4 lugares: PBXBuildFile, PBXFileReference, PBXGroup,
    PBXResourcesBuildPhase. Veja seção 4.4 do caderno.

PARTE 6 — Encerramento

17. Bump de build (+1) em pubspec / `web/version.json` /
    `lib/app_version.dart`.
18. Rodar `dart analyze` somente nos ficheiros novos/alterados e
    reportar resultado.
19. NÃO criar parâmetro Remote Config no console — farei manual
    depois (chave `exibir_pagamento_ios = false` para o Project ID
    correto do Controle Total).
20. NÃO publicar / não fazer deploy. Apenas alterações de código.
21. Validação obrigatória final (iOS):
    - liste todos os pontos de CTA de upgrade encontrados;
    - confirme que em cada um deles o iOS chama
      `openUpgradePlansExternally(...)` com `email` quando disponível.

Antes de começar:
- Confirme nome do pacote no pubspec do Controle Total.
- Confirme tema/cor primária (equivalente a ThemeCleanPremium).
- Identifique catálogo de planos local (planosOficiais ou nome
  análogo).
- Confirme URL pública (em AppConstants ou variável equivalente) e que existam
  a rota de **login web** (com `after` whitelistado) e `/atualizar-plano` no site.
- Confirme onde está o LoginPage mobile e o método pós-Google a
  reutilizar.
- Identifique TODAS as chamadas a `MercadoPagoCheckoutFullscreen` /
  WebView de pagamento para gatear (donations admin, donation sheet
  público, etc.).

Reporte um plano de execução com a lista exata de ficheiros que vai
tocar antes de começar.

⚠️ AVISO IMPORTANTE — APPLE DEVELOPER:
Antes do próximo build iOS na Codemagic, o usuário precisa:
1. developer.apple.com → App ID → ativar Sign In with Apple + Push
   Notifications.
2. Profiles → regenerar .mobileprovision App Store com as 2
   capabilities.
3. Codemagic → atualizar CM_PROVISIONING_PROFILE com o Base64.
Sem isso, o build falha com erro de entitlement.
```

---

## B) Para `C:\moova_super_premium`

> _Este projeto precisa das **três** coisas: Login Expresso (não
> existia ainda) + iOS App Store Hardening completo + Express Renew._

```
Aplique no Moova Super Premium TRÊS mudanças que foram implementadas
no Gestão YAHWEH (baseline `11.2.295+1512`, URL Safari login-first `11.2.295+1558`):

(1) iOS App Store Hardening (Reader/Multiplatform/Privacy Manifest).
(2) Faixa flutuante «Login expresso» (Google silencioso → Apple iOS
    → Google UI), idêntica à do app Controle Total.
(3) Express Renew — rota web `/atualizar-plano` com header «Super
    Premium» + Login Expresso popup/redirect Google.

Caderno técnico completo (LEIA antes de mexer):
C:\gestao_yahweh_premium_final\docs\migracoes\IOS_READER_E_LOGIN_EXPRESSO.md

═══════════════════════════════════════════════════════════════
PARTE 1 — iOS Reader / Multiplatform (Guideline 3.1.1 / 3.1.3(b))
═══════════════════════════════════════════════════════════════

1. Adicione `firebase_remote_config: ^5.4.0` ao pubspec.
2. Crie `lib/services/ios_payments_gate.dart` (chave
   `exibir_pagamento_ios`, default `false`).
3. Crie `lib/ui/widgets/ios_payment_unavailable_view.dart` ADAPTADO
   ao tema/planos do Moova: SEM preços, SEM toggle Mensal/Anual.
   Apenas nome do plano, capacidade, recursos. CTA «Atualizar plano
   no site» NO TOPO e NO RODAPÉ. URL = **login web** do Moova com `after`
   para `/atualizar-plano?from=ios_app` (não só `/atualizar-plano` como
   primeira página). Substituir paths pelo equivalente do Moova
   (`AppConstants` ou similar).
4. Inicialize `IosPaymentsGate.initialize()` em `main.dart` antes do
   `runApp`.
5. Na página de planos/checkout do Moova, no início do `build`,
   retorne `IosPaymentUnavailableView` quando
   `IosPaymentsGate.shouldHidePayments` for `true` E `expressMode`
   for `false`.
6. No `onGenerateRoute` do `main.dart`, gate iOS native intercepta
   `/`, `/planos`, `/pagamento` (vão para LoginPage ou
   IosPaymentUnavailableView). Veja seção 2.3 do caderno.
7. Localize todos os botões/diálogos/banners que digam «Pagar»,
   «Comprar», «Assinar», «Adquirir», «Renovar», «Ver planos»,
   «Vincule o pagamento» e:
   - troque o LABEL para «Atualizar plano» quando
     `IosPaymentsGate.shouldHidePayments` for `true`;
   - no iOS native, todos os CTAs de upgrade devem abrir Safari externo
     no **login web** com `after` → plano expresso (`/atualizar-plano?from=ios_app`),
     não push direto para página de cobrança/planos nesses pontos.
   - implemente helper central no gate (ex.:
     `IosPaymentsGate.openUpgradePlansExternally(source: ...)`) e use em
     todos os pontos.
   Liste antes os pontos detectados.
8. Em login pública / landing do Moova, em iOS native esconder
   preços (se houver bloco resumo) e trocar botão «Ver planos» por
   «Atualizar plano no site» que abre Safari no **login web** com `after`
   para `/atualizar-plano?from=ios_app`.

═══════════════════════════════════════════════════════════════
PARTE 2 — Doações — **PULAR no Moova**
═══════════════════════════════════════════════════════════════

> O Moova **não** tem módulo de dízimos/ofertas (é app de motorista /
> licença). **Não** aplicar `IosDonationReaderView`. Licença motorista
> no iOS: Safari em `/login/apple?from=ios_app` (já no Moova).

═══════════════════════════════════════════════════════════════
PARTE 3 — Login Expresso
═══════════════════════════════════════════════════════════════

10. Crie `lib/services/express_login_service.dart` com:
    - `tryExpressLogin()` que faz, em ordem:
      a) `appGoogleSignIn().signInSilently()` → autentica via
         `GoogleAuthProvider.credential` se devolver idToken.
      b) Em iOS, `SignInWithApple.getAppleIDCredential` (com nonce
         SHA-256) e `OAuthProvider('apple.com')`.
      c) Fallback: Google com UI (`appGoogleSignIn().signIn()`).
    - Retorna `ExpressLoginResult` com enum
      `googleSilent | apple | googleInteractive | alreadySignedIn |
       cancelled | unsupported | error`.
    - Em web devolve `unsupported`.
11. Crie `lib/ui/widgets/login_expresso_faixa.dart` com a faixa
    visual: gradiente `#111827 → #1F2937 → #0F766E`, ícone
    `flash_on_rounded`, título «Login expresso», subtítulo «Clique
    aqui e use e-mail salvo do navegador/celular», botão tonal
    «Entrar» (vira spinner quando `loading: true`). Padding
    `14/0/14/10` + `SafeArea(top: false)`.
12. Localize a página de login mobile do Moova (a usada em
    Android/iOS native) e:
    - Adicione estado `bool _expressLoginInFlight = false`.
    - Adicione método `_onLoginExpresso()` que:
      * Guarda contra web/loading/finalizing.
      * Chama `ExpressLoginService.tryExpressLogin()`.
      * Em sucesso, executa o MESMO pós-login que o botão Google
        já existente.
      * Trata cancelamento, FirebaseAuthException, erros genéricos.
    - No `Stack` do `Scaffold.body`, antes do fechamento dos
      children, insira:
      ```dart
      Positioned(left: 0, right: 0, bottom: 0,
        child: LoginExpressoFaixa(
          onTap: _onLoginExpresso,
          loading: _expressLoginInFlight,
        ),
      ),
      ```
    - No `SingleChildScrollView` interno, adicione +84 px de padding
      bottom para o conteúdo nunca ficar coberto.
13. Faixa só desenha em mobile native — guardar com
    `!kIsWeb && (Platform.isAndroid || Platform.isIOS)` ou equivalente
    do projeto.

═══════════════════════════════════════════════════════════════
PARTE 4 — Express Renew (`/atualizar-plano`) + login web no `main.dart`
═══════════════════════════════════════════════════════════════

14. Crie `lib/ui/pages/plans/express_renew_gate_page.dart`:
    - StreamBuilder<User?> em authStateChanges.
    - Logado → `RenewPlanPage(expressMode: true)`.
    - Deslogado → header «Super Premium» (gradient brand + logo
      Moova + título «Atualizar plano») + card com botão grande
      gradient «Login Expresso» que faz `signInWithPopup` Google
      (web) ou `tryExpressLogin()` (mobile native, raro), com
      fallback `signInWithRedirect` em Safari iOS.
    - Aceita `?email=...` para badge "Vamos entrar com <email>".
    - Link discreto «Entrar com e-mail e senha» empilha LoginPage
      tradicional com `afterLoginRoute=/atualizar-plano` ou
      `/atualizar-plano?from=ios_app` (fluxo iOS).
15. Em `RenewPlanPage` (página de planos/checkout do Moova),
    adicione prop `expressMode: bool` (default false). Em
    expressMode:
    - Header dedicado com plano atual + vencimento + email user.
    - Hide do botão demo, AppBar customizada.
    - Após pagamento, mostrar tela final dedicada (não redireciona).
16. No `main.dart` `onGenerateRoute`, registre rota **login web** (com `after`
    whitelistado) e rota
    `/atualizar-plano` → `ExpressRenewGatePage(prefillEmail:
    uri.queryParameters['email'], openedFromIosApp: uri.queryParameters['from'] == 'ios_app')`.

═══════════════════════════════════════════════════════════════
PARTE 5 — Configurações iOS (`ios/`)
═══════════════════════════════════════════════════════════════

17. `ios/Runner/Info.plist` — adicionar:
    - `NSCameraUsageDescription`
    - `NSMicrophoneUsageDescription`
    - `NSContactsUsageDescription` (se app importa contatos)
    - `LSApplicationQueriesSchemes` com https/http/mailto/tel/sms/whatsapp
    Manter NSFaceID, NSPhotoLibrary*, NSLocation*, NSCalendars.
18. `ios/Runner/Runner.entitlements` — garantir AS DUAS keys:
    - `com.apple.developer.applesignin = ['Default']` (Guideline 4.8)
    - `aps-environment = production` (firebase_messaging)
19. CRIAR `ios/Runner/PrivacyInfo.xcprivacy` (Privacy Manifest
    obrigatório desde maio/2024). Conteúdo completo em
    `c:\gestao_yahweh_premium_final\flutter_app\ios\Runner\PrivacyInfo.xcprivacy`
    (NSPrivacyTracking=false, data types coletados, 4 APIs com
    reasons C617.1 / CA92.1 / E174.1 / 35F9.1).
20. REGISTRAR o PrivacyInfo no `ios/Runner.xcodeproj/project.pbxproj`
    em 4 lugares: PBXBuildFile, PBXFileReference, PBXGroup,
    PBXResourcesBuildPhase. Veja seção 4.4 do caderno.

═══════════════════════════════════════════════════════════════
PARTE 6 — Encerramento
═══════════════════════════════════════════════════════════════

21. Bump de build (+1) em pubspec / `web/version.json` /
    `lib/app_version.dart` (ou equivalente do Moova).
22. Rodar `dart analyze` somente nos ficheiros novos/alterados.
23. NÃO criar parâmetro Remote Config no console — eu faço manual
    depois (`exibir_pagamento_ios = false` para o Project ID Moova).
24. NÃO publicar / não fazer deploy. Apenas alterações de código.
25. Validação obrigatória final (iOS):
    - reporte checklist com todos os CTAs de upgrade detectados;
    - confirme um a um que chamam `openUpgradePlansExternally(...)`.

Antes de mexer:
- Confirme nome do pacote no pubspec.yaml do Moova.
- Confirme tema/cor primária (equivalente a ThemeCleanPremium).
- Identifique catálogo de planos local (`planosOficiais` ou nome
  análogo) e confirme se existe um `PlanPriceService`.
- Identifique a URL pública do site Moova (em `AppConstants` ou
  variável equivalente). Confirmar rotas **login web** + `/atualizar-plano`
  no site Moova (Moovaup).
- Confirme se Moova já tem `GestorOAuthOnboardingService` para Apple
  Sign-In; se não, copiar/criar helper local com
  `signInWithAppleIfAvailable`.
- Identifique TODAS as chamadas a checkout MP / WebView de pagamento
  para gatear em iOS native.

Reporte um plano de execução com a lista exata de ficheiros que vai
tocar antes de começar.

⚠️ AVISO IMPORTANTE — APPLE DEVELOPER:
Antes do próximo build iOS na Codemagic, o usuário precisa:
1. developer.apple.com → App ID do Moova → ativar Sign In with Apple
   + Push Notifications.
2. Profiles → regenerar .mobileprovision App Store com as 2
   capabilities.
3. Codemagic → atualizar CM_PROVISIONING_PROFILE com o Base64.
Sem isso, o build falha com erro de entitlement.
```

---

## Como usar

1. **No Cursor**, abra o projeto alvo (Controle Total ou Moova).
2. Copie/sincronize a pasta `docs/migracoes/` deste workspace para o
   projeto alvo, **ou** mantenha o caminho absoluto referenciado no
   prompt (Windows tem acesso entre projetos no mesmo disco).
3. Cole o prompt da seção apropriada (A ou B) no chat.
4. O agente vai abrir o caderno
   `IOS_READER_E_LOGIN_EXPRESSO.md`, listar o plano e executar.
5. Após terminar a parte de código, faça do seu lado:
   - **Apple Developer** → App ID com Sign In with Apple + Push Notifications.
   - **Profiles** → regerar `.mobileprovision` App Store.
   - **Codemagic** → atualizar `CM_PROVISIONING_PROFILE`.
   - **Firebase Console** → criar `exibir_pagamento_ios = false`.
   - **App Store Connect** → preencher "App Privacy" alinhado ao
     `PrivacyInfo.xcprivacy` + Notes para Review.
6. Bump de build + deploy quando estiver tudo ok.

## Ordem sugerida

1. **Controle Total** primeiro (já tem login expresso, é só hardening).
2. **Moova** depois (precisa de tudo).
3. Submeter cada um na App Store separadamente.
