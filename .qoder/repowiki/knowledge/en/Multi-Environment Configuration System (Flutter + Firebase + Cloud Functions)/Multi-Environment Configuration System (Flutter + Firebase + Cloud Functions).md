---
kind: configuration_system
name: Multi-Environment Configuration System (Flutter + Firebase + Cloud Functions)
category: configuration_system
scope:
    - '**'
source_files:
    - flutter_app/lib/firebase_options.dart
    - flutter_app/lib/core/firebase_bootstrap.dart
    - flutter_app/lib/features/chat/data/tdlib_credentials.dart
    - flutter_app/.env
    - flutter_app/.env.example
    - firebase.json
    - functions/.env.gestaoyahweh-21e23
    - flutter_app/android/key.properties
    - flutter_app/ios/Runner/GoogleService-Info.plist
    - flutter_app/.firebaserc
    - functions/package.json
---

## What system/approach is used

The project uses a layered configuration approach combining:
- **Firebase CLI configuration** (`firebase.json`, `.firebaserc`) for hosting, functions, firestore rules, and storage rules deployment targets.
- **FlutterFire-generated platform options** (`lib/firebase_options.dart`) providing per-platform Firebase credentials (web, Android, iOS).
- **`.env` files with `flutter_dotenv`** for runtime secrets like Telegram API keys, loaded via `loadTdlibDotEnv()` in `main.dart` before app initialization.
- **Platform-specific native configs**: `android/key.properties` for signing, `ios/Runner/GoogleService-Info.plist` for iOS Firebase config, `android/google-services.json` for Android.
- **Cloud Functions environment variables** defined in `functions/.env.gestaoyahweh-21e23` and managed through Firebase CLI `defineString` parameters during non-interactive deployments.
- **Firebase Remote Config** (`firebase_remote_config` dependency) for feature flags like iOS payment UI control (`exibir_pagamento_ios`).
- **Hive local storage** (`hive`, `hive_flutter`) for offline-first persistent app state and user preferences.

## Key files and packages

- `flutter_app/lib/firebase_options.dart` — Generated Firebase platform options with hardcoded per-platform credentials
- `flutter_app/lib/core/firebase_bootstrap.dart` — Centralized Firebase initialization with retry logic and EcoFire integration
- `flutter_app/lib/features/chat/data/tdlib_credentials.dart` — TDLib credential loading from `.env` via `flutter_dotenv`
- `flutter_app/.env` and `flutter_app/.env.example` — Telegram API credentials template
- `flutter_app/pubspec.yaml` — Dependencies including `flutter_dotenv`, `firebase_remote_config`, `hive`, `shared_preferences`
- `firebase.json` — Hosting, functions, firestore rules, storage rules, and emulator configuration
- `functions/.env.gestaoyahweh-21e23` — Cloud Functions environment variables (Drive IDs, MercadoPago keys, SendGrid)
- `flutter_app/android/key.properties` — Android signing keystore configuration
- `flutter_app/ios/Runner/GoogleService-Info.plist` — iOS Firebase configuration
- `flutter_app/.firebaserc` — Default Firebase project mapping
- `functions/package.json` — Node.js 22 engine specification and function dependencies

## Architecture and conventions

**Initialization order is strict**: `main.dart` loads TDLib dotenv first (soft-fail), then initializes Firebase through `FirebaseBootstrap.ensureInitialized()`, followed by health checks and offline coordination. This ensures all services are ready before `runApp()`.

**Secrets management follows a clear pattern**: Sensitive values (Telegram API keys, keystore passwords, service account JSON) are stored in `.env` files excluded from git via `.gitignore`, with `.env.example` templates committed for reference. Platform-specific secrets use native configurations (Android/iOS).

**Feature flagging strategy**: Runtime feature toggles use Firebase Remote Config for server-controlled features (like iOS payment restrictions for App Store compliance), while compile-time constants live in `lib/core/app_constants.dart` for immutable app behavior.

**Multi-tenant support**: Church-specific configurations are resolved dynamically using slug-based routing and Firestore data, with public web base URLs normalized through `PublicWebOrigin` utilities.

**Build-time vs runtime separation**: Flutter build artifacts include only `.env.example` (not real secrets), while CI/CD pipelines inject actual secrets through environment variables or secure storage mechanisms.

## Conventions and constraints

- **Never commit `.env` files with real secrets** — enforced by `.gitignore` and documented in comments throughout the codebase
- **Use `flutterfire configure` to regenerate `firebase_options.dart`** — manual edits will be overwritten by setup scripts
- **TDLib credentials are optional** — soft-fail loading allows the app to run without Telegram integration if credentials are missing
- **Firebase initialization must complete before any service usage** — enforced through `FirebaseBootstrapService.isReady()` checks throughout the codebase
- **Platform-specific configurations must stay synchronized** — `firebase_options.dart` must match `GoogleService-Info.plist` (iOS) and `google-services.json` (Android)
- **Cloud Functions environment variables use `defineString` parameters** — required for non-interactive Firebase CLI deployments in CI/CD pipelines
- **Hive is used exclusively for offline-first data persistence** — not for sensitive information which should use `flutter_secure_storage`
- **Feature flags follow naming convention** — boolean flags like `exibir_pagamento_ios` control UI visibility based on platform requirements