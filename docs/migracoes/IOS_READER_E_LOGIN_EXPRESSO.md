# Migração — iOS Reader/Multiplatform + Login Expresso

> Caderno técnico do que foi implementado no **Gestão YAHWEH** em maio/2026
> para (a) homologar na App Store sem rejeição por pagamento e
> (b) replicar o **botão «Login expresso»** do **Controle Total** App.
>
> Este ficheiro é o «mapa» para aplicar a mesma lógica em outros projetos
> (Controle Total, Moova Super Premium, etc.).

---

## 0. Contexto e objetivo

Apple rejeita app de SaaS que:

- Mostre botões «Pagar com Mercado Pago / Cartão» dentro do binário iOS.
- Abra Safari para checkout sem ser configurado como **Multiplatform Service**.

Solução adotada (mesma do app **enuves**, aprovado pela Apple):

1. App em iOS continua mostrando **preços informativos** dos planos.
2. **Único botão** «Atualizar plano» abre Safari na URL pública
   (`/planos`) com `email` e `utm_*` em query, para o site amarrar a
   compra ao tenant correto.
3. Webhook (Cloud Function + Mercado Pago) atualiza Firestore;
   `RenewPlanPage` ouve via `snapshot listener` e libera o plano sem o
   utilizador reabrir o app.

Adicionalmente foi portado o **«Login expresso»** do Controle Total
para Gestão YAHWEH — faixa flutuante de 1 toque
(Google silencioso → Apple iOS → Google UI).

---

## 1. Mudanças de pacotes / versão

### `pubspec.yaml`

```yaml
dependencies:
  # ... existentes ...

  # iOS Reader / Multiplatform Service: flag remota `exibir_pagamento_ios`.
  firebase_remote_config: ^5.4.0

  # url_launcher já existe no projeto — confirmar versão >= 6.x
  # google_sign_in / sign_in_with_apple também já existiam
```

`version: X.Y.Z+N` — incrementar `+N` quando publicar (regra
`controle-versao` deste workspace).

### `web/version.json` e `lib/app_version.dart`

Manter sincronizados com o `+N` do pubspec.

---

## 2. iOS Reader / Multiplatform — arquivos

### 2.1 `lib/services/ios_payments_gate.dart` (NOVO)

Serviço estático, sem estado de instância. API:

- `IosPaymentsGate.isIosNative` — `true` em iPhone/iPad nativos.
- `IosPaymentsGate.paymentsAllowed` — `false` em iOS quando o flag
  remoto `exibir_pagamento_ios` for `false` (default conservador).
  Sempre `true` em Android/Web/Desktop.
- `IosPaymentsGate.shouldHidePayments` — atalho semântico.
- `IosPaymentsGate.initialize()` — chamar **uma vez** em `main()` antes
  do `runApp`. Não‑bloqueante: em qualquer falha mantém o default
  conservador.

Constantes:

```dart
static const String remoteConfigKey = 'exibir_pagamento_ios';
static const bool _defaultIosShowPayments = false;
```

### 2.2 `lib/ui/widgets/ios_payment_unavailable_view.dart` (NOVO)

Tela «Atualizar plano» — substitui o checkout em iOS. Mostra:

- Cabeçalho «Atualizar plano» + ícone `workspace_premium_rounded`.
- Toggle Mensal / Anual (12 por 10).
- Lista de planos com nome, descrição, preço, badge «Recomendado».
  Carrega preços efetivos via `PlanPriceService.getEffectivePlanConfigs()`,
  com fallback para `planosOficiais` quando offline.
- Botão único `FilledButton.icon` → abre Safari em
  `${AppConstants.publicWebBaseUrl}/planos?utm_source=app_ios&utm_medium=manage_subscription&email=<user>`
  via `launchUrl(uri, mode: LaunchMode.externalApplication)`.
- Card explicativo: «após pagar no site, o plano é ativado
  automaticamente neste app — pode ser preciso reabrir».
- Construtor aceita `embedded: true` para uso dentro de `AppShell` /
  shell de navegação (omite `AppBar` própria).

### 2.3 `lib/main.dart`

Inicializar **antes** do `runApp`:

```dart
import 'package:gestao_yahweh/services/ios_payments_gate.dart';

// dentro do main():
configureFirestoreForOfflineAndSpeed();
try {
  await IosPaymentsGate.initialize();
} catch (_) {}
// ... resto: AppConnectivityService, StorageUploadQueueService, runApp
```

### 2.4 `lib/ui/pages/plans/renew_plan_page.dart`

No início de `build`:

```dart
@override
Widget build(BuildContext context) {
  if (IosPaymentsGate.shouldHidePayments) {
    return IosPaymentUnavailableView(embedded: widget.embeddedInShell);
  }
  // ... fluxo Mercado Pago original
}
```

### 2.5 Pontos de UI ajustados (label condicional)

Em todos os pontos abaixo, o **botão continua existindo** e abre o
`RenewPlanPage` (que em iOS vira `IosPaymentUnavailableView`). Só o
**texto** muda em iOS:

| Ficheiro | Texto Android/Web | Texto iOS Reader |
|---|---|---|
| `lib/services/members_limit_service.dart` (`shortMessage`, `blockedDialogMessage`) | «Faça upgrade» | «Atualize seu plano» |
| `lib/ui/pages/internal_new_member_page.dart` | «Ver planos» | «Atualizar plano» |
| `lib/ui/pages/members_page.dart` (dialog + SnackBar) | «Ver planos» | «Atualizar plano» |
| `lib/ui/pages/dashboard_page.dart` (`banner()`) | «Ativar plano» / «Ver planos» | «Atualizar plano» |
| `lib/ui/pages/onboarding/trial_expired_page.dart` | «Escolher plano» + texto DEMO | «Atualizar plano» + texto Reader |
| `lib/ui/igreja_clean_shell.dart` (AppBar + sidebar + drawer mobile) | «Adquirir Plano» / «Planos e assinatura» | «Atualizar plano» |
| `lib/ui/pages/subscription_expired_page.dart` | «Renovar Licença / Pagar Agora» | «Atualizar plano» |

Padrão de import e uso:

```dart
import 'package:gestao_yahweh/services/ios_payments_gate.dart';

final iosReader = IosPaymentsGate.shouldHidePayments;
// ...
Text(iosReader ? 'Atualizar plano' : 'Ver planos')
```

### 2.6 Páginas que devem permanecer com preços (informativo)

- `lib/ui/login_page.dart` — bloco `_showGestorMarketingBlocks`.
- `lib/ui/landing_page.dart` — `LandingPage` (rota `/`).

> **Não** usar o gate nessas páginas: a Apple aceita preços
> informativos (Guideline 3.1.3) desde que não haja botão de checkout
> direto. Estes blocos só *mostram* preços + botão «Iniciar teste
> grátis» (que vai a `/signup`, sem pagamento).

### 2.7 Firebase Console — Remote Config

Antes do upload na App Store:

1. **Firebase Console → Remote Config**.
2. Criar parâmetro `exibir_pagamento_ios` = `false` (boolean).
3. **Publicar**.
4. Após aprovação na Apple, alterar para `true` quando/se for
   integrar `In‑App Purchase` (caso decida monetizar dentro do app).

### 2.8 Notas de revisão (App Store Connect)

Texto curto sugerido:

> Este aplicativo é uma ferramenta de gestão administrativa para
> instituições já cadastradas. O faturamento e a gestão de licenças
> são realizados fora do ambiente mobile, via plataforma desktop/web.
> Não há venda de bens digitais dentro do binário do aplicativo.

Prints da loja **não** podem mostrar preços ou botões «Assinar».

---

## 3. Login Expresso — arquivos

### 3.1 `lib/services/express_login_service.dart` (NOVO)

API estática `ExpressLoginService.tryExpressLogin()`:

1. Se houver `FirebaseAuth.instance.currentUser` → `alreadySignedIn`.
2. Tenta `appGoogleSignIn().signInSilently()` → autentica com
   `GoogleAuthProvider.credential` se devolver `idToken`.
3. Em iOS, se silencioso falhar, tenta
   `GestorOAuthOnboardingService.signInWithAppleIfAvailable()`.
4. Cai para `signInWithGoogleNative()` (Google com seletor de contas).
5. Devolve `ExpressLoginResult` com `kind`:
   `googleSilent | apple | googleInteractive | alreadySignedIn |
    cancelled | unsupported | error`.

Em web devolve `unsupported` (web usa `signInWithPopup`).

### 3.2 `lib/ui/widgets/login_expresso_faixa.dart` (NOVO)

Widget visual idêntico à faixa do Controle Total
(`screens/landing_screen.dart` → `_buildFaixaSuspensaLoginExpresso`):

- Gradiente `#111827 → #1F2937 → #0F766E`.
- Ícone `Icons.flash_on_rounded` em quadrado branco semitransparente.
- Título «Login expresso» + subtítulo «Clique aqui e use e‑mail salvo
  do navegador/celular».
- `FilledButton.tonalIcon` à direita com texto «Entrar» (vira spinner
  quando `loading: true`).
- Padding `14/0/14/10` + `SafeArea(top: false)`.
- Props: `onTap` (obrigatório), `loading`, `title`, `subtitle`,
  `buttonLabel`, `padding`.

### 3.3 `lib/ui/login_page.dart`

Imports:

```dart
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/ui/widgets/login_expresso_faixa.dart';
```

Estado:

```dart
bool _expressLoginInFlight = false;
```

Método `_onLoginExpresso()`:

- Guarda contra `kIsWeb`, `_loading`, `_sessionFinalizing`.
- Faz `setState(_expressLoginInFlight = true)` → chama o serviço.
- Se sucesso, troca para `_sessionFinalizing = true` e chama
  `_afterGoogleSignInSuccess()` (mesma rota pós‑login do botão Google
  convencional: `repairMyChurchBinding` quando necessário e
  `_finalizeChurchLoginAfterAuth`).
- Mensagens específicas para `not-found` (membro vs gestor),
  `FirebaseAuthException`, erros genéricos.

UI — em `_buildNativeMobileChurchLogin`:

- `SingleChildScrollView` ganha **+84 px** de padding inferior
  (`24 + 84`) para o conteúdo nunca ficar atrás da faixa.
- No `Stack` do `Scaffold.body`, **antes** do fechamento dos
  children, adicionar:

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

A faixa só é desenhada quando `_nativeChurchLogin` é `true`
(Android/iOS native + rota `/painel`). Web/master não a recebem.

---

## 4. Dependências de plataforma

### Android (`AndroidManifest.xml`)

Sem mudanças exclusivas para estas duas features (Google Sign‑In e
url_launcher já estavam configurados).

### iOS (`ios/Runner/Info.plist`)

- `LSApplicationQueriesSchemes` **não** precisa de `https` para
  `url_launcher` em iOS 9+.
- `CFBundleURLTypes` para Google Sign‑In já presente
  (REVERSED_CLIENT_ID do `GoogleService-Info.plist`).
- Sign in with Apple ativo no App ID + capability «Sign in with
  Apple» no Xcode (já configurado para `signInWithAppleIfAvailable`).

---

## 5. Checklist de validação

### iOS Reader

- [ ] `flutter pub get` baixou `firebase_remote_config`.
- [ ] `IosPaymentsGate.initialize()` chamado em `main()`.
- [ ] `RenewPlanPage` em iOS mostra `IosPaymentUnavailableView`.
- [ ] Botão da view abre Safari externo, **não** in‑app browser.
- [ ] Banners/diálogos em iOS dizem «Atualizar plano» (não «Pagar»,
      «Comprar», «Adquirir», «Assinar»).
- [ ] `landing_page.dart` e blocos de marketing do `login_page.dart`
      ainda mostram preços.
- [ ] `exibir_pagamento_ios = false` publicado no Remote Config.
- [ ] Print da loja não mostra «Pagar» / «Comprar».

### Login Expresso

- [ ] Faixa aparece no rodapé do login mobile (Android/iOS).
- [ ] Toque na faixa → autenticação sem UI quando há sessão Google.
- [ ] Em iPhone sem Google → fallback para Apple Sign‑In.
- [ ] Sem nenhuma sessão → seletor Google nativo abre.
- [ ] Após login, vai para `/painel` (rota normal pós‑Google).
- [ ] Faixa **não** aparece em web nem no login master.
- [ ] `dart analyze` limpo nos 3 ficheiros (service + widget +
      `login_page.dart`).

---

## 6. Diferenças por projeto

| Projeto | iOS Reader | Login Expresso |
|---|---|---|
| **Gestão YAHWEH** (origem) | ✅ Implementado | ✅ Implementado (portado do Controle Total) |
| **Controle Total** (`C:\Controletotalapp_Independente`) | ⏳ Aplicar | ✅ **Já é a fonte** — não mexer |
| **Moova Super Premium** (`C:\moova_super_premium`) | ⏳ Aplicar | ⏳ Aplicar |

### Pontos de atenção ao portar

- **Trocar nomes/imports** `gestao_yahweh` → pacote real do projeto
  alvo (`controletotalapp` / `moova_super_premium`).
- **`AppConstants.publicWebBaseUrl`** — substituir pela URL do site
  público correspondente (Controle Total / Moova).
- **`planosOficiais` / `PlanPriceService`** — cada app tem o próprio
  catálogo de planos. Reutilizar a lista local; o widget só lê.
- **`ThemeCleanPremium`** — usar o tema equivalente do projeto alvo.
- **`AppShell`** — alguns projetos têm shell próprio. Substituir o
  wrapper pelo equivalente local; se não houver, remover.
- **`GestorOAuthOnboardingService`** — em projetos sem este serviço,
  copiar o `signInWithAppleIfAvailable` e `signInWithGoogleNative`
  para um helper local antes de criar o `ExpressLoginService`.
- **Página de login mobile** — descobrir o equivalente a
  `_buildNativeMobileChurchLogin` (em Moova pode ser
  `mobile_login_screen.dart`; em Controle Total já é a
  `landing_screen.dart`).

---

## 7. Comandos úteis

```powershell
# Análise dart restrita aos ficheiros novos/alterados
cd flutter_app
dart analyze lib\services\express_login_service.dart `
             lib\services\ios_payments_gate.dart `
             lib\ui\widgets\login_expresso_faixa.dart `
             lib\ui\widgets\ios_payment_unavailable_view.dart `
             lib\ui\login_page.dart `
             lib\ui\pages\plans\renew_plan_page.dart

# Pub get após adicionar firebase_remote_config
flutter pub get

# Build iOS local (só macOS):
# flutter build ipa --release --no-tree-shake-icons
```

---

## 8. Quando habilitar pagamento in‑app no iOS

Quando/se a app passar a usar **In‑App Purchase** da Apple:

1. Implementar IAP com pacote `in_app_purchase` no `RenewPlanPage`.
2. No Firebase Console → Remote Config: trocar
   `exibir_pagamento_ios` para `true`.
3. `IosPaymentsGate.shouldHidePayments` passa a `false` em iOS e o
   fluxo Mercado Pago / IAP volta a aparecer.

---

_Última atualização: 2026‑05‑08 — Gestão YAHWEH `11.2.295+1508`._
