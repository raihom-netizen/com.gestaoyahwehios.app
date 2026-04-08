# Contribuir — Gestão YAHWEH

Guia enxuto para quem desenvolve ou publica o projeto (Flutter + Firebase + web + painéis).

## Requisitos

- Flutter SDK compatível com `pubspec.yaml` (`sdk: >=3.4.0`).
- Node/npm para Cloud Functions (pasta `functions`).
- Firebase CLI (`firebase login`) para deploy.

## Scripts na raiz do repositório (PowerShell)

| Objetivo | Comando |
|----------|---------|
| Build web + deploy Hosting | `.\scripts\deploy_web_hosting.ps1` |
| Regras Firestore + Storage + índices | `.\scripts\deploy_firebase_rules.ps1` |

- **Hosting** serve `flutter_app/build/web` (ver `firebase.json`).
- Após publicar a web: URL `https://gestaoyahweh-21e23.web.app` — pedir **Ctrl+F5** por causa de cache.
- `version.json` e `index.html` usam **no-cache** no Hosting; assets estáticos (`assets/`, `canvaskit/`) usam cache longo para performance.

## Versão do app

Ao mudar funcionalidade visível ou correção de produto, incrementar em sequência:

- `flutter_app/lib/app_version.dart` — `appVersion`
- `flutter_app/pubspec.yaml` — `version: X.Y.Z+build`
- `flutter_app/web/version.json` — `version` e `build_number`

Há script auxiliar: `scripts/bump_version.ps1` (se existir no seu clone).

## Imagens Firebase na web

Não usar `Image.network` direto para URLs `firebasestorage.googleapis.com` no painel/site. Usar `SafeNetworkImage` / `StorageFriendlyImage` (`lib/ui/widgets/safe_network_image.dart`).

## Erro de rede / “Tentar novamente”

Use `ThemeCleanPremium.premiumErrorState` e `ThemeCleanPremium.showErrorSnackBarWithRetry` (`lib/ui/theme_clean_premium.dart`) para manter o mesmo padrão visual nos painéis.

## Crashlytics (Android / iOS)

O projeto já inclui `firebase_crashlytics` no Dart e os plugins Gradle (`com.google.gms.google-services`, `com.google.firebase.crashlytics`).

1. Coloque **`google-services.json`** em `flutter_app/android/app/` (baixar na Firebase Console → configurações do projeto Android). Sem este ficheiro o **build Android falha**.
2. iOS: `GoogleService-Info.plist` no Xcode, se quiser Crashlytics também no iPhone.
3. Relatórios: [Firebase Console → Crashlytics](https://console.firebase.google.com/project/gestaoyahweh-21e23/crashlytics). Em **debug** a recolha fica desligada (`kReleaseMode`); use um build **release** para ver crashes reais.

## Backup e dados

- Console do projeto: `https://console.firebase.google.com/project/gestaoyahweh-21e23/overview`
- Política de backup/export do Firestore: configurar na própria consola Google Cloud / Firebase (export agendado ou sob demanda), conforme necessidade da operação.

## Análise e testes

```powershell
cd flutter_app
dart analyze
flutter test
```

Reduzir avisos do analisador nos módulos que você tocar mantém o projeto sustentável.
