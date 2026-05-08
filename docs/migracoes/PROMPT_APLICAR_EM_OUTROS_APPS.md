# Prompt — aplicar iOS Reader + Login Expresso em outro app

> Cole o conteúdo de **uma** das seções abaixo no chat do Cursor
> dentro do projeto alvo (Controle Total ou Moova). O agente vai ler
> o caderno técnico e replicar a lógica.
>
> **Pré‑requisito:** copie a pasta `docs/migracoes/` deste projeto
> (`c:\gestao_yahweh_premium_final\docs\migracoes`) para a raiz do
> projeto alvo, ou referencie o caminho absoluto no prompt.

---

## A) Para `C:\Controletotalapp_Independente`

> _Este projeto **já tem** o «Login expresso» (foi a fonte original).
> Só falta aplicar o iOS Reader/Multiplatform Service._

```
Aplique no Controle Total App a mesma estratégia de iOS Reader /
Multiplatform Service que foi implementada no Gestão YAHWEH.

Caderno técnico (LEIA antes de mexer):
C:\gestao_yahweh_premium_final\docs\migracoes\IOS_READER_E_LOGIN_EXPRESSO.md

Faça exatamente isto:

1. Adicione `firebase_remote_config: ^5.4.0` ao pubspec do app.
2. Crie `lib/services/ios_payments_gate.dart` com a mesma API
   (`isIosNative`, `paymentsAllowed`, `shouldHidePayments`,
   `initialize`, chave `exibir_pagamento_ios`, default `false`).
3. Crie `lib/ui/widgets/ios_payment_unavailable_view.dart` reutilizando
   o catálogo de planos local do Controle Total (planos / preços
   atuais), com o mesmo layout: cabeçalho «Atualizar plano», toggle
   Mensal/Anual, lista de cards, botão único que abre Safari na URL
   pública do Controle Total (substituir `gestaoyahweh.com.br/planos`
   pelo equivalente — confira em `AppConstants` ou similar).
4. Inicialize `IosPaymentsGate.initialize()` em `main.dart` antes do
   `runApp`, não bloqueante.
5. Na página de planos / renovação do Controle Total, no início do
   `build`, retorne `IosPaymentUnavailableView` quando
   `IosPaymentsGate.shouldHidePayments` for `true`.
6. Localize todos os botões/diálogos/banners que digam «Pagar»,
   «Comprar», «Assinar», «Adquirir», «Renovar agora», «Ver planos»
   nos fluxos de gestor e troque o **label** (não a navegação) para
   «Atualizar plano» quando `IosPaymentsGate.shouldHidePayments` for
   `true`. Listar antes de mexer e me mostrar os pontos detectados.
7. NÃO esconder preços nem botões em `login_page` / `landing_screen`
   (Apple Guideline 3.1.3 permite exibição informativa).
8. Bump de build (+1) em pubspec/web/version.json/app_version.dart.
9. Rodar `dart analyze` somente nos ficheiros novos/alterados e
   reportar.

Não criar Firebase Remote Config no console — eu faço manualmente
depois (chave `exibir_pagamento_ios = false`).

Não publicar deploy. Apenas alterações de código.
```

---

## B) Para `C:\moova_super_premium`

> _Este projeto precisa de **ambas** as features._

```
Aplique no Moova Super Premium duas mudanças que foram implementadas
no Gestão YAHWEH:

(1) iOS Reader / Multiplatform Service (App Store Guideline 3.1.3).
(2) Faixa flutuante «Login expresso» (Google silencioso → Apple iOS
    → Google UI), idêntica à do app Controle Total.

Caderno técnico completo (LEIA antes de mexer):
C:\gestao_yahweh_premium_final\docs\migracoes\IOS_READER_E_LOGIN_EXPRESSO.md

PARTE 1 — iOS Reader

1. Adicione `firebase_remote_config: ^5.4.0` ao pubspec.
2. Crie `lib/services/ios_payments_gate.dart` com a mesma API (chave
   `exibir_pagamento_ios`, default `false`).
3. Crie `lib/ui/widgets/ios_payment_unavailable_view.dart` adaptado ao
   tema/planos do Moova: cabeçalho «Atualizar plano», toggle
   Mensal/Anual, cards de plano, botão único que abre o site público
   do Moova em Safari (`launchUrl(..., LaunchMode.externalApplication)`).
   Substituir a URL `gestaoyahweh.com.br/planos` pela URL pública do
   Moova (verifique em `AppConstants` ou variável equivalente).
4. Inicialize `IosPaymentsGate.initialize()` em `main.dart` antes do
   `runApp`, não bloqueante.
5. Na página principal de planos/checkout do Moova, no início do
   `build` retorne `IosPaymentUnavailableView` quando
   `IosPaymentsGate.shouldHidePayments` for `true`.
6. Localize todos os botões/diálogos/banners que digam «Pagar»,
   «Comprar», «Assinar», «Adquirir», «Renovar», «Ver planos» e troque
   o **label** (não a navegação) para «Atualizar plano» quando
   `IosPaymentsGate.shouldHidePayments` for `true`. Liste antes os
   pontos detectados.
7. NÃO esconda preços/botões em landing/login pública (Apple permite
   exibição informativa).

PARTE 2 — Login Expresso

8. Crie `lib/services/express_login_service.dart` com:
   - `tryExpressLogin()` que faz, em ordem:
     a) `appGoogleSignIn().signInSilently()` → autentica via
        `GoogleAuthProvider.credential` se devolver idToken.
     b) Em iOS, `SignInWithApple.getAppleIDCredential` (com nonce
        SHA‑256) e `OAuthProvider('apple.com')`.
     c) Fallback: Google com UI (`appGoogleSignIn().signIn()`).
   - Retorna `ExpressLoginResult` com enum
     `googleSilent | apple | googleInteractive | alreadySignedIn |
      cancelled | unsupported | error`.
   - Em web devolve `unsupported`.
9. Crie `lib/ui/widgets/login_expresso_faixa.dart` com a faixa visual
   do Controle Total: gradiente `#111827 → #1F2937 → #0F766E`, ícone
   `flash_on_rounded`, título «Login expresso», subtítulo «Clique
   aqui e use e‑mail salvo do navegador/celular», botão tonal
   «Entrar» (vira spinner quando `loading: true`). Padding
   `14/0/14/10` + `SafeArea(top: false)`.
10. Localize a página de login mobile do Moova (a que é usada em
    Android/iOS native) e:
    - Adicione estado `bool _expressLoginInFlight = false`.
    - Adicione método `_onLoginExpresso()` que:
      * Guarda contra web/loading/finalizing.
      * Chama `ExpressLoginService.tryExpressLogin()`.
      * Em sucesso, executa o **mesmo pós‑login** que o botão Google
        já existente (reuse o método pós‑Google atual).
      * Trata cancelamento, `FirebaseAuthException`, erros genéricos.
    - No `Stack` do `Scaffold.body`, antes do fechamento dos
      children, insira:
      ```dart
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: LoginExpressoFaixa(
          onTap: _onLoginExpresso,
          loading: _expressLoginInFlight,
        ),
      ),
      ```
    - No `SingleChildScrollView` interno, adicione +84 px de padding
      bottom para o conteúdo nunca ficar coberto.
11. Faixa só desenha em mobile native — guardar com
    `!kIsWeb && (Platform.isAndroid || Platform.isIOS)` ou equivalente
    do projeto. Web/painel master não recebem.

PARTE 3 — Encerramento

12. Bump de build (+1) em pubspec / `web/version.json` /
    `lib/app_version.dart` (ou equivalente do Moova).
13. Rodar `dart analyze` somente nos ficheiros novos/alterados e
    reportar resultado.
14. NÃO criar parâmetro Remote Config no console — farei manual
    depois (chave `exibir_pagamento_ios = false`).
15. NÃO publicar / não fazer deploy. Apenas alterações de código.

Antes de mexer:
- Confirme o nome do pacote do projeto (em pubspec.yaml).
- Confirme o tema/cor primária equivalente a `ThemeCleanPremium`.
- Identifique o catálogo de planos local (`planosOficiais` ou nome
  análogo) e confirme se existe um `PlanPriceService`.
- Identifique a URL pública do site Moova (em `AppConstants` ou
  variável equivalente).

Reporte um plano de execução com a lista exata de ficheiros que vai
tocar antes de começar.
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
5. Após terminar:
   - Crie no Firebase Console o parâmetro
     `exibir_pagamento_ios = false` para o `Project ID` correto
     (cada app tem o seu).
   - Confira em iOS que o botão dispara Safari externo.
   - Bump de build + deploy quando estiver tudo ok.
