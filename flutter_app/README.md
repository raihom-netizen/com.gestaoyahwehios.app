# Gestão YAHWEH

Sistema de gestão para igrejas: membros, eventos, financeiro, assinaturas e integração Mercado Pago.

## Requisitos

- Flutter SDK >= 3.4.0
- Firebase (Auth, Firestore, Functions, Storage, Hosting)
- Conta Mercado Pago (para pagamentos)

## Como rodar

```bash
cd flutter_app
flutter pub get
flutter run
```

- **Web:** `flutter run -d chrome` ou `flutter run -d web-server --web-port=8080`
- **Android:** `flutter run -d android`
- **iOS:** `flutter run -d ios`

## Build de produção

```bash
flutter build web --release
# Saída em build/web — publicar no Firebase Hosting
firebase deploy --only hosting
```

## Variáveis de ambiente / Firebase

- **Firebase Console:** ative Auth (e-mail/senha, Google), Firestore, Functions, Storage, Hosting.
- **Authorized domains:** adicione o domínio do app em Authentication > Settings.
- **Cloud Functions:** configure `MP_ACCESS_TOKEN` (ou use config/mercado_pago no painel admin) para Mercado Pago.
- **Firestore:** use as regras em `../firestore.rules` (raiz do projeto).

## Estrutura principal

```
lib/
├── core/           # Constantes (app_constants.dart)
├── data/           # Dados estáticos (planos_oficiais)
├── services/       # Lógica (members_limit_service, subscription_service, billing_service)
├── ui/             # Telas e widgets
│   ├── auth_gate.dart
│   ├── login_page.dart
│   ├── igreja_clean_shell.dart   # Painel igreja
│   ├── admin_panel_page.dart    # Painel master
│   ├── pages/       # Páginas (membros, eventos, assinatura, etc.)
│   └── widgets/    # Componentes reutilizáveis (skeleton_loader, version_footer)
└── main.dart
```

## Versão

A versão é definida em `lib/app_version.dart`. Atualize também `pubspec.yaml` (version) e `web/version.json` ao liberar.

## Documentação adicional

- `lib/ui/PADRAO_VISUAL_CLEAN_PREMIUM.md` — padrão visual do painel
- `SUGESTOES_MELHORIA.md` — melhorias sugeridas (UX, performance, segurança)
