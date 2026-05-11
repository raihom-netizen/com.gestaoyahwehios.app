# Migração — iOS App Store (Reader/Multiplatform) + Login Expresso + Atualizar Plano Web

> Caderno técnico do que foi implementado no **Gestão YAHWEH** em
> maio/2026 (build `11.2.295+1512`) para:
>
> 1. **Homologar na App Store** sem rejeição por pagamento (Guidelines
>    3.1.1, 3.1.3(b), 3.2.1(viii), 4.8 e Privacy Manifest).
> 2. **Replicar o «Login Expresso»** do Controle Total (Google
>    silencioso → Apple iOS → Google UI).
> 3. **Fluxo express «Atualizar plano»** — rota web pública que pede
>    login simples, mostra plano atual + vencimento e leva direto ao
>    checkout Mercado Pago, sem passar pelo painel.
>
> Este ficheiro é o **mapa** para aplicar a mesma lógica em outros
> projetos (Controle Total, Moova Super Premium, etc.).

---

## 0. Contexto e estratégia aprovada

A Apple rejeita app SaaS que:

- Mostre botões «Pagar com Mercado Pago / Cartão» dentro do binário iOS.
- Abra Safari para checkout sem se enquadrar em **Multiplatform Service**
  (3.1.3(b)).
- Colete doações dentro do app (3.2.1(viii) — doações em iOS só por
  website/SMS).
- Ofereça login Google sem oferecer **Sign in with Apple** (4.8).
- Submeta sem **Privacy Manifest** (`PrivacyInfo.xcprivacy` é
  obrigatório desde maio/2024).

Solução adotada (mesma de SaaS aprovados como Spotify, Netflix, Kindle
e o competidor «enuves»):

1. **Em iOS native**, NUNCA expor preços, checkout ou link direto para
   pagamento dentro do app. Tela `IosPaymentUnavailableView` mostra
   apenas nome + capacidade + recursos dos planos.
2. **Único botão** «Atualizar plano no site» abre Safari na URL pública
   `/atualizar-plano` com `from=ios_app&email=...`.
3. **Rota web `/atualizar-plano`** (`ExpressRenewGatePage`): header
   «Super Premium», botão **Login Expresso** (Google popup/redirect),
   header com plano atual + vencimento, lista de planos, ciclo,
   checkout Mercado Pago — tudo na web, fora do binário iOS.
4. **Webhook Mercado Pago + Cloud Function** atualiza Firestore;
   `RenewPlanPage` ouve via snapshot listener e libera o plano sem
   reabrir o app.
5. Doações em iOS native abrem Safari externo (`launchUrl`,
   `LaunchMode.externalApplication`) — **nunca** WebView in-app.

Adicionalmente foi portado o **«Login Expresso»** do Controle Total
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
  # webview_flutter pode existir (mp_checkout_embed_io) — em iOS native
  # NÃO usar para checkout MP, abrir Safari externo no lugar.
```

`version: X.Y.Z+N` — incrementar `+N` quando publicar (regra
`controle-versao` deste workspace).

### `web/version.json` e `lib/app_version.dart`

Manter sincronizados com o `+N` do pubspec.

---

## 2. iOS Reader / Multiplatform — arquivos Dart

### 2.0 Regra obrigatória (maio/2026)

No iOS native em modo Reader (`IosPaymentsGate.shouldHidePayments == true`):

- **Nenhum CTA de upgrade** deve abrir `RenewPlanPage()` diretamente.
- Todos os CTAs («Atualizar plano», «Ver planos», «Ativar plano», ações em
  `SnackBar`, diálogos de limite e banners de trial/licença) devem abrir
  **Safari externo** em `/atualizar-plano` com `email` quando disponível.

Implementação padrão (helper central no gate):

```dart
static Future<bool> openUpgradePlansExternally({
  String source = 'ios_app',
}) async {
  final email = (FirebaseAuth.instance.currentUser?.email ?? '').trim();
  final uri = Uri.parse('${AppConstants.publicWebBaseUrl}/atualizar-plano')
      .replace(queryParameters: {
    'from': 'ios_app',
    'utm_source': 'app_ios',
    'utm_medium': source,
    if (email.isNotEmpty) 'email': email,
  });
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

Uso padrão em qualquer botão:

```dart
if (IosPaymentsGate.shouldHidePayments && IosPaymentsGate.isIosNative) {
  IosPaymentsGate.openUpgradePlansExternally(source: 'dashboard_trial_expired');
  return;
}
Navigator.push(context, MaterialPageRoute(builder: (_) => const RenewPlanPage()));
```

### 2.1 `lib/services/ios_payments_gate.dart` (NOVO)

Serviço estático, sem estado de instância. API:

- `IosPaymentsGate.isIosNative` — `true` em iPhone/iPad nativos.
- `IosPaymentsGate.paymentsAllowed` — `false` em iOS quando o flag
  remoto `exibir_pagamento_ios` for `false` (default conservador).
  Sempre `true` em Android/Web/Desktop.
- `IosPaymentsGate.shouldHidePayments` — atalho semântico.
- `IosPaymentsGate.initialize()` — chamar **uma vez** em `main()` antes
  do `runApp`. Não-bloqueante: em qualquer falha mantém o default
  conservador.

Constantes:

```dart
static const String remoteConfigKey = 'exibir_pagamento_ios';
static const bool _defaultIosShowPayments = false;
```

### 2.2 `lib/ui/widgets/ios_payment_unavailable_view.dart` (NOVO)

Tela «Atualizar plano» — substitui o checkout em iOS. Mostra:

- Cabeçalho «Atualizar plano» + ícone `workspace_premium_rounded`.
- Texto: "Veja os planos disponíveis e a capacidade de cada um. Para
  contratar ou trocar de plano, use o botão abaixo — a contratação é
  feita no nosso site."
- **CTA «Atualizar plano no site» NO TOPO** (FilledButton primary).
- Lista de planos com nome, capacidade ("até X membros"), badge
  «Recomendado» e 3 bullets de recursos. **SEM preços, sem ciclo
  Mensal/Anual, sem botão de cobrança.**
- **CTA «Atualizar plano no site» NO RODAPÉ** (mesmo botão).
- Card explicativo: «após contratar no site, o plano é ativado
  automaticamente nesta conta — pode ser preciso reabrir o app».
- Construtor aceita `embedded: true` para uso dentro de `AppShell` /
  shell de navegação (omite `AppBar` própria).

URL externa montada com:

```dart
final params = <String, String>{
  'from': 'ios_app',
  'utm_source': 'app_ios',
  'utm_medium': 'manage_subscription',
  if (email.isNotEmpty) 'email': email,
};
return Uri.parse('${AppConstants.publicWebBaseUrl}/atualizar-plano')
    .replace(queryParameters: params);
```

### 2.3 `lib/main.dart`

Inicializar **antes** do `runApp`:

```dart
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'ui/widgets/ios_payment_unavailable_view.dart';
import 'ui/pages/plans/express_renew_gate_page.dart';

// dentro do main():
configureFirestoreForOfflineAndSpeed();
try {
  await IosPaymentsGate.initialize();
} catch (_) {}
// ... resto do main
```

E no `onGenerateRoute`, **antes** do switch principal:

```dart
// iOS App Store (Apple Guideline 3.1.1 / 3.1.3): no app iOS nativo,
// NUNCA expor páginas com preços/checkout (LandingPage, RenewPlanPage,
// SitePublicPage). Redireciona tudo para login ou para a tela
// informativa sem preços.
if (IosPaymentsGate.isIosNative) {
  if (path == '/') {
    final em = uri.queryParameters['email']?.trim();
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => LoginPage(
        title: 'Entrar — Painel da Igreja',
        afterLoginRoute: '/painel',
        showFleetBranding: false,
        backRoute: '/',
        prefillEmail: (em != null && em.isNotEmpty) ? em : null,
      ),
    );
  }
  if (path == '/planos' || path == '/pagamento') {
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => const IosPaymentUnavailableView(),
    );
  }
}
```

E no switch principal, registrar a nova rota web:

```dart
case '/atualizar-plano': {
  final em = uri.queryParameters['email']?.trim();
  pagina = ExpressRenewGatePage(
    prefillEmail: (em != null && em.isNotEmpty) ? em : null,
  );
  break;
}
```

### 2.4 `lib/ui/pages/plans/renew_plan_page.dart`

Adicionar prop `expressMode` ao construtor:

```dart
class RenewPlanPage extends StatefulWidget {
  final bool embeddedInShell;
  final bool expressMode; // NOVO
  const RenewPlanPage({
    super.key,
    this.embeddedInShell = false,
    this.expressMode = false,
  });
}
```

No início de `build`:

```dart
@override
Widget build(BuildContext context) {
  // Apple Guideline 3.1.1: em iOS, comportamento Reader/SaaS — exceto
  // no fluxo expressMode que só roda na web (rota `/atualizar-plano`).
  if (!widget.expressMode && IosPaymentsGate.shouldHidePayments) {
    return IosPaymentUnavailableView(embedded: widget.embeddedInShell);
  }
  // ... fluxo Mercado Pago original (Android/web/expressMode)
}
```

Em `expressMode`:
- Header `_buildExpressHeader` com plano atual + vencimento + email.
- Hide do botão «Ativar plano (demo)».
- AppBar customizada ("Atualizar plano", sem leading/actions).
- Após pagamento, mostrar `_buildExpressDoneView` (não redireciona).

### 2.5 `lib/ui/pages/plans/express_renew_gate_page.dart` (NOVO)

Rota pública `/atualizar-plano` — gate de autenticação Reader-friendly.

Comportamento:
- `StreamBuilder<User?>` em `FirebaseAuth.instance.authStateChanges()`.
- Logado → `RenewPlanPage(expressMode: true)`.
- Deslogado → tela própria com:
  - **Header «Super Premium»** (gradient `#0A3D91 → brandPrimary →
    #2B6FE0`) com `assets/logo.png` em cartão branco arredondado,
    título «Atualizar plano», pílula com troféu + «Gestão YAHWEH —
    Super Premium».
  - **Card de login**: badge com `?email=...` quando vem do app iOS,
    botão grande gradient «Login Expresso» → `signInWithPopup`
    (Google) com fallback `signInWithRedirect` (Safari/iOS); link
    discreto «Entrar com e-mail e senha» que empilha a `LoginPage`
    tradicional com `afterLoginRoute: /atualizar-plano`.
  - **Footer**: «Conexão segura · Pagamento via Mercado Pago».

Aceita `?email=...` da URL para pré-preencher.

### 2.6 Pontos de UI ajustados (label condicional + gating)

Em todos os pontos abaixo, o **botão continua existindo** e abre o
`RenewPlanPage` (que em iOS vira `IosPaymentUnavailableView`). Só o
**texto** muda em iOS:

| Ficheiro | Texto Android/Web | Texto iOS Reader |
|---|---|---|
| `lib/services/members_limit_service.dart` (`shortMessage`, `blockedDialogMessage`) | «Faça upgrade» | «Atualize seu plano» |
| `lib/ui/pages/internal_new_member_page.dart` | «Ver planos» | «Atualizar plano» |
| `lib/ui/pages/members_page.dart` (dialog + SnackBar) | «Ver planos» | «Atualizar plano» |
| `lib/ui/pages/dashboard_page.dart` (`banner()`) | «Ativar plano» / «Ver planos» / «Vincule o pagamento...» | «Atualizar plano» / «atualize seu plano no site» |
| `lib/ui/pages/onboarding/trial_expired_page.dart` | «Escolher plano» + texto DEMO | «Atualizar plano» + texto Reader |
| `lib/ui/igreja_clean_shell.dart` (AppBar + sidebar + drawer mobile) | «Adquirir Plano» / «Planos e assinatura» | «Atualizar plano» |
| `lib/ui/pages/subscription_expired_page.dart` | «Renovar Licença / Pagar Agora» | «Atualizar plano» |
| `lib/ui/pages/completar_cadastro_membro_page.dart` | «Ver planos» | «Atualizar plano» |
| `lib/ui/pages/public_member_signup_page.dart` | «Ver planos» | «Atualizar plano» |
| `lib/ui/login_page.dart` `_buildPlanosResumoCard` | preços por plano + «Ver página completa de planos» → `/planos` | preços OCULTOS + «Atualizar plano no site» → Safari externo |

Padrão de import e uso:

```dart
import 'package:gestao_yahweh/services/ios_payments_gate.dart';

final iosReader = IosPaymentsGate.shouldHidePayments;
// ou para checagem nativa pura (sem flag remota):
final iosNative = IosPaymentsGate.isIosNative;
// ...
Text(iosReader ? 'Atualizar plano' : 'Ver planos')
```

### 2.7 Site público da igreja em iOS native

`lib/ui/church_public_page.dart` — em iOS native, redirecionar para
Safari externo:

- **Botão «Doação»** (`onDoacao`): `showChurchPublicDonationSheet`
  proibido em iOS (3.2.1(viii)). Em iOS, abre
  `${publicWebBaseUrl}/igreja/<slug>` no Safari.
- **«Adquirir Sistema»** no rodapé: em iOS abre
  `${publicWebBaseUrl}/atualizar-plano?from=ios_app` no Safari (em vez
  de `pushNamed('/planos')` que mostraria preços via LandingPage).

`lib/ui/site_publico_igreja/church_public_donation_sheet.dart` —
`_showCheckoutPreviewModal` em iOS native usa `launchUrl(uri,
mode: LaunchMode.externalApplication)` em vez de
`showMercadoPagoCheckoutFullscreen` (defesa em profundidade).

`lib/ui/pages/church_donations_page.dart` (admin tesouraria) — mesma
proteção: em iOS native, preview de checkout MP abre Safari, não
WebView.

### 2.8 Páginas que devem permanecer com preços (web/Android, informativo)

- `lib/ui/login_page.dart` — bloco `_showGestorMarketingBlocks` (em iOS
  o `_buildPlanosResumoCard` esconde preços via `iosReader`; nas
  outras plataformas mantém).
- `lib/ui/landing_page.dart` — `LandingPage` (rota `/planos` em
  Android/web; em iOS native redirecionada via `onGenerateRoute`).

### 2.9 Firebase Console — Remote Config

Antes do upload na App Store:

1. **Firebase Console → Remote Config**.
2. Criar parâmetro `exibir_pagamento_ios` = `false` (boolean).
3. **Publicar**.
4. Após aprovação na Apple, alterar para `true` quando/se for
   integrar `In-App Purchase` (caso decida monetizar dentro do app).

### 2.10 Notas de revisão (App Store Connect)

Texto sugerido (em inglês para o reviewer da Apple):

> This app is a B2B church management SaaS (multiplatform service per
> Guideline 3.1.3(b)). Subscriptions and billing are handled
> exclusively on the web platform via Mercado Pago — no digital goods
> are sold inside the iOS binary. All "Update plan" buttons open
> Safari externally on `<seu-dominio>.com.br/atualizar-plano`.
> Donations to non-profit churches (when the church owner enables
> them) also open in Safari per Guideline 3.2.1(viii).
>
> Demo account:
>   Email: [seu e-mail demo]
>   Password: [sua senha]
>   Tenant: [igreja de testes]
>
> Sign in with Apple is offered alongside Google Sign-In on iOS as
> required by Guideline 4.8.

Prints da loja **não** podem mostrar preços ou botões «Assinar».

---

## 3. Login Expresso — arquivos Dart

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

Widget visual idêntico à faixa do Controle Total:

- Gradiente `#111827 → #1F2937 → #0F766E`.
- Ícone `Icons.flash_on_rounded` em quadrado branco semitransparente.
- Título «Login expresso» + subtítulo «Clique aqui e use e-mail salvo
  do navegador/celular».
- `FilledButton.tonalIcon` à direita com texto «Entrar» (vira spinner
  quando `loading: true`).
- Padding `14/0/14/10` + `SafeArea(top: false)`.

### 3.3 `lib/ui/login_page.dart`

Imports:

```dart
import 'package:gestao_yahweh/services/express_login_service.dart';
import 'package:gestao_yahweh/services/ios_payments_gate.dart';
import 'package:gestao_yahweh/ui/widgets/login_expresso_faixa.dart';
```

Estado e método `_onLoginExpresso()` — vide código fonte.

UI — em `_buildNativeMobileChurchLogin`:

- `SingleChildScrollView` ganha **+84 px** de padding inferior.
- No `Stack` do `Scaffold.body`, `Positioned(left: 0, right: 0,
  bottom: 0, child: LoginExpressoFaixa(...))`.

### 3.4 Helper externo «Atualizar plano no site» (pré-login)

Adicionar no `LoginPage` o método que o card de planos usa em iOS:

```dart
Future<void> _openExternalUpgradePlanFromLogin() async {
  final params = <String, String>{
    'from': 'ios_app',
    'utm_source': 'app_ios',
    'utm_medium': 'login_planos',
  };
  final uri = Uri.parse('${AppConstants.publicWebBaseUrl}/atualizar-plano')
      .replace(queryParameters: params);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
```

E em `_buildPlanosResumoCard`:

```dart
final iosReader = IosPaymentsGate.isIosNative;
// ... (esconde preços e troca botão final)
TextButton.icon(
  onPressed: iosReader
      ? _openExternalUpgradePlanFromLogin
      : () => Navigator.pushNamed(context, '/planos'),
  icon: Icon(Icons.open_in_new_rounded, size: 18, color: theme),
  label: Text(
    iosReader ? 'Atualizar plano no site' : 'Ver página completa de planos',
  ),
),
```

---

## 4. Configurações iOS (pasta `ios/`)

### 4.1 `ios/Runner/Info.plist`

Privacy strings obrigatórias para os plugins usados (sem elas, app
crasha ao abrir câmera/galeria/calendário/etc., e a Apple rejeita):

```xml
<key>NSFaceIDUsageDescription</key>
<string>Usamos Face ID para liberar acesso rápido ao app.</string>
<key>NSCalendarsUsageDescription</key>
<string>Adicionar eventos da igreja ao seu calendário (Google/Apple) após confirmar presença.</string>
<key>NSCameraUsageDescription</key>
<string>Usamos a câmera para você tirar e enviar fotos no perfil, no mural, em eventos e no cadastro de membros.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Permitimos gravação de áudio apenas quando você publicar um vídeo no mural com som.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Salvar a carteirinha digital na galeria de fotos quando você tocar em Salvar.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Permitir acesso às suas fotos para você escolher imagens em publicações, perfil, mural ou envio de arquivos da igreja.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Usamos sua localização com o app aberto para mapas, distâncias ou recursos que você acionar (eventos, cadastros ou endereços).</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Se você permitir localização em segundo plano, usamos apenas para funcionalidades que você ativar (alertas ou rotas). Pode alterar nas Configurações do iPhone.</string>
<key>NSContactsUsageDescription</key>
<string>Usado apenas se você optar por importar contatos para o cadastro de membros — nada é enviado sem sua confirmação.</string>
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>https</string>
    <string>http</string>
    <string>mailto</string>
    <string>tel</string>
    <string>sms</string>
    <string>whatsapp</string>
</array>
<!-- CFBundleURLTypes do Google Sign-In já existe -->
```

### 4.2 `ios/Runner/Runner.entitlements`

**OBRIGATÓRIO** — Sign in with Apple (Guideline 4.8) + Push (FCM):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>
    <key>aps-environment</key>
    <string>production</string>
</dict>
</plist>
```

**Pré-requisito Apple Developer + Codemagic:**

1. `developer.apple.com` → **Identifiers** → App ID:
   - Marcar **Sign In with Apple**.
   - Marcar **Push Notifications**.
2. **Profiles** → criar/regenerar `.mobileprovision` App Store que
   inclua **as duas capabilities**.
3. **Codemagic** → atualizar `CM_PROVISIONING_PROFILE` com o Base64 do
   novo perfil (ou ativar **Automatic signing**).

Sem isso, o build vai falhar com:
`Provisioning profile doesn't include the
com.apple.developer.applesignin entitlement`.

### 4.3 `ios/Runner/PrivacyInfo.xcprivacy` (NOVO — OBRIGATÓRIO desde maio/2024)

A Apple exige Privacy Manifest em todas as submissões. Sem ele, a App
Store emite warning e pode rejeitar com "Missing Privacy Manifest".

Conteúdo mínimo do app (cada plugin Firebase já traz seu próprio):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array>
        <!-- E-mail, Nome, Telefone, Fotos, CrashData, Localização, UserID
             — todos com Linked=true, Tracking=false, purposes
             AppFunctionality / Authentication / Analytics. -->
    </array>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>C617.1</string></array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>CA92.1</string></array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>E174.1</string></array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array><string>35F9.1</string></array>
        </dict>
    </array>
</dict>
</plist>
```

> Ver `ios/Runner/PrivacyInfo.xcprivacy` deste projeto para o conteúdo
> completo com todos os data types.

### 4.4 Registrar `PrivacyInfo.xcprivacy` no `project.pbxproj`

**Não basta criar o arquivo** — precisa estar listado no Xcode project
para entrar no bundle. Adicionar 4 entradas no `Runner.xcodeproj/project.pbxproj`:

**A) `PBXBuildFile` section** (perto das outras `*.plist in Resources`):

```
B4F7E8B11CF9000F007C117D /* PrivacyInfo.xcprivacy in Resources */ = {isa = PBXBuildFile; fileRef = B4F7E8B01CF9000F007C117D /* PrivacyInfo.xcprivacy */; };
```

**B) `PBXFileReference` section**:

```
B4F7E8B01CF9000F007C117D /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = text.xml; path = "PrivacyInfo.xcprivacy"; sourceTree = "<group>"; };
```

**C) `PBXGroup` do Runner** (mesma lista do `Info.plist`,
`GoogleService-Info.plist`):

```
B4F7E8B01CF9000F007C117D /* PrivacyInfo.xcprivacy */,
```

**D) `PBXResourcesBuildPhase` do target Runner** (mesma lista do
`GoogleService-Info.plist in Resources`):

```
B4F7E8B11CF9000F007C117D /* PrivacyInfo.xcprivacy in Resources */,
```

> Os IDs (24-char hex) podem ser quaisquer, desde que únicos. Use o
> mesmo prefixo das outras entries para consistência.

### 4.5 `ios/Podfile`

```ruby
platform :ios, '14.0'
# ...
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
    end
  end
end
```

iOS 14.0+ é o mínimo aceito pela App Store em 2026.

---

## 5. Checklist de validação

### iOS Reader / Multiplatform

- [ ] `flutter pub get` baixou `firebase_remote_config`.
- [ ] `IosPaymentsGate.initialize()` chamado em `main()`.
- [ ] Existe `IosPaymentsGate.openUpgradePlansExternally(...)`.
- [ ] `RenewPlanPage` em iOS (sem `expressMode`) mostra
      `IosPaymentUnavailableView`.
- [ ] `IosPaymentUnavailableView` **não mostra preços** nem toggle
      Mensal/Anual. CTA está no topo E no rodapé.
- [ ] Botões da view abrem Safari externo (`LaunchMode.externalApplication`).
- [ ] Em iOS native, todos os CTAs de upgrade (dashboard, shell, members,
      onboarding, signup público/interno, diálogos de limite, snackbars e tela de
      licença expirada) chamam `openUpgradePlansExternally(...)` em vez de
      `Navigator.push(...RenewPlanPage())`.
- [ ] Banners/diálogos em iOS dizem «Atualizar plano» (não «Pagar»,
      «Comprar», «Adquirir», «Assinar», «Renovar agora»).
- [ ] `_buildPlanosResumoCard` em iOS native: sem coluna de preço, com
      botão «Atualizar plano no site».
- [ ] Rotas `/`, `/planos`, `/pagamento` em iOS native interceptadas no
      `onGenerateRoute`.
- [ ] Doações (`ChurchPublicPage`, `church_public_donation_sheet`,
      `church_donations_page`) abrem Safari em iOS native, não WebView.
- [ ] `exibir_pagamento_ios = false` publicado no Remote Config.
- [ ] Print da loja não mostra «Pagar» / «Comprar» / preços.

### Login Expresso

- [ ] Faixa aparece no rodapé do login mobile (Android/iOS).
- [ ] Toque na faixa → autenticação sem UI quando há sessão Google.
- [ ] Em iPhone sem Google → fallback para Apple Sign-In.
- [ ] Sem nenhuma sessão → seletor Google nativo abre.
- [ ] Após login, vai para `/painel`.
- [ ] Faixa **não** aparece em web nem no login master.

### Express Renew (rota web `/atualizar-plano`)

- [ ] Abre direto pela URL com header «Super Premium».
- [ ] `?email=...` mostra badge "Vamos entrar com `<email>`".
- [ ] Botão Login Expresso abre popup Google; em Safari (popup
      bloqueado) cai para `signInWithRedirect` automaticamente.
- [ ] Após login → `RenewPlanPage(expressMode: true)` com header de
      plano atual + vencimento.
- [ ] Após pagamento → `_buildExpressDoneView` (não redireciona).
- [ ] Link "Entrar com e-mail e senha" abre `LoginPage` que volta
      para `/atualizar-plano` ao logar.

### iOS — pasta `ios/` e Apple Developer

- [ ] `Info.plist` com NSCamera, NSMicrophone, NSContacts,
      LSApplicationQueriesSchemes.
- [ ] `Runner.entitlements` com `com.apple.developer.applesignin` +
      `aps-environment=production`.
- [ ] `PrivacyInfo.xcprivacy` criado E registrado no
      `project.pbxproj` (4 entries).
- [ ] App ID com **Sign In with Apple** + **Push Notifications**
      ativos no Apple Developer.
- [ ] Provisioning profile App Store regenerado com as 2 capabilities.
- [ ] Codemagic com profile atualizado.
- [ ] `dart analyze` sem erros novos.

---

## 6. Diferenças por projeto

| Projeto | iOS Reader+Hardening+Express | Login Expresso |
|---|---|---|
| **Gestão YAHWEH** (origem) | ✅ Implementado (`11.2.295+1512`) | ✅ Implementado (portado do Controle Total) |
| **Controle Total** (`C:\Controletotalapp_Independente`) | ⏳ Aplicar | ✅ **Já é a fonte** — não mexer |
| **Moova Super Premium** (`C:\moova_super_premium`) | ⏳ Aplicar | ⏳ Aplicar |

### Pontos de atenção ao portar

- **Trocar imports** `gestao_yahweh` → pacote real do projeto
  alvo (`controletotalapp` / `moova_super_premium`).
- **`AppConstants.publicWebBaseUrl`** — substituir pela URL do site
  público correspondente. **Confirmar** que no site público existe (ou
  vai ser criada) a rota `/atualizar-plano` que recebe `?from=ios_app`.
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
- **Bundle ID iOS** e Team ID — manter os do projeto alvo. As
  capabilities (Sign in with Apple, Push) são por App ID.
- **Logo** — `assets/logo.png` no `ExpressRenewGatePage`. Cada app usa
  o seu.
- **Cores do header «Super Premium»** — adaptar gradient ao
  `brandPrimary` de cada projeto.

---

## 7. Comandos úteis

```powershell
# Análise dart restrita aos ficheiros novos/alterados
cd flutter_app
dart analyze --no-fatal-warnings `
  lib\services\express_login_service.dart `
  lib\services\ios_payments_gate.dart `
  lib\ui\widgets\login_expresso_faixa.dart `
  lib\ui\widgets\ios_payment_unavailable_view.dart `
  lib\ui\login_page.dart `
  lib\ui\pages\plans\renew_plan_page.dart `
  lib\ui\pages\plans\express_renew_gate_page.dart `
  lib\main.dart

# Pub get após adicionar firebase_remote_config
flutter pub get

# Build iOS local (só macOS):
# flutter build ipa --release --no-tree-shake-icons
```

---

## 8. Quando habilitar pagamento in-app no iOS

Quando/se a app passar a usar **In-App Purchase** da Apple:

1. Implementar IAP com pacote `in_app_purchase` no `RenewPlanPage`.
2. No Firebase Console → Remote Config: trocar
   `exibir_pagamento_ios` para `true`.
3. `IosPaymentsGate.shouldHidePayments` passa a `false` em iOS e o
   fluxo Mercado Pago / IAP volta a aparecer.

---

## 9. Resumo de arquivos por categoria

### Novos arquivos Dart

```
flutter_app/lib/services/ios_payments_gate.dart
flutter_app/lib/services/express_login_service.dart
flutter_app/lib/ui/widgets/ios_payment_unavailable_view.dart
flutter_app/lib/ui/widgets/login_expresso_faixa.dart
flutter_app/lib/ui/pages/plans/express_renew_gate_page.dart
```

### Dart modificados (label condicional / gating / express)

```
flutter_app/lib/main.dart                                       # gate `/`, `/planos`, `/pagamento`, rota `/atualizar-plano`
flutter_app/lib/app_version.dart                                # bump
flutter_app/pubspec.yaml                                        # firebase_remote_config + bump
flutter_app/web/version.json                                    # bump
flutter_app/lib/ui/login_page.dart                              # Login Expresso + _buildPlanosResumoCard sem preços iOS
flutter_app/lib/ui/pages/plans/renew_plan_page.dart             # gate iOS + expressMode
flutter_app/lib/services/members_limit_service.dart             # mensagens iOS
flutter_app/lib/ui/pages/dashboard_page.dart                    # banners iOS neutralizados
flutter_app/lib/ui/pages/internal_new_member_page.dart          # label
flutter_app/lib/ui/pages/members_page.dart                      # label
flutter_app/lib/ui/pages/onboarding/trial_expired_page.dart     # label
flutter_app/lib/ui/igreja_clean_shell.dart                      # tooltips/labels
flutter_app/lib/ui/pages/subscription_expired_page.dart         # label
flutter_app/lib/ui/pages/completar_cadastro_membro_page.dart    # label
flutter_app/lib/ui/pages/public_member_signup_page.dart         # label
flutter_app/lib/ui/church_public_page.dart                      # doação + Adquirir Sistema → Safari iOS
flutter_app/lib/ui/site_publico_igreja/church_public_donation_sheet.dart  # checkout MP → Safari iOS
flutter_app/lib/ui/pages/church_donations_page.dart             # checkout MP admin → Safari iOS
```

### Arquivos iOS (`ios/`)

```
flutter_app/ios/Runner/Info.plist                  # privacy strings + LSApplicationQueriesSchemes
flutter_app/ios/Runner/Runner.entitlements         # SignInWithApple + aps-environment
flutter_app/ios/Runner/PrivacyInfo.xcprivacy       # NOVO — Privacy Manifest
flutter_app/ios/Runner.xcodeproj/project.pbxproj   # registrar PrivacyInfo.xcprivacy (4 entries)
```

---

_Última atualização: 2026-05-09 — Gestão YAHWEH `11.2.295+1512`._
