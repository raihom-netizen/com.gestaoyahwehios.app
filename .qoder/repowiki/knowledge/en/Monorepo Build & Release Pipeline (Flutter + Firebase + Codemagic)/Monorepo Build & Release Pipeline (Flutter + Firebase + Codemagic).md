---
kind: build_system
name: Monorepo Build & Release Pipeline (Flutter + Firebase + Codemagic)
category: build_system
scope:
    - '**'
source_files:
    - codemagic.yaml
    - flutter_app/codemagic.yaml
    - firebase.json
    - flutter_app/pubspec.yaml
    - functions/package.json
    - functions/tsconfig.json
    - scripts/deploy_completo.ps1
    - scripts/build_android_aab.ps1
---

This repository uses a multi-stage build and release system centered on Flutter for the cross-platform app, Firebase for hosting/functions/rules, and Codemagic for iOS CI/CD. The pipeline is orchestrated by PowerShell scripts on developer machines and a YAML-driven Codemagic workflow for automated iOS builds and TestFlight uploads.

**Systems and tools**
- Flutter 3.44.1 with pubspec.yaml as the single source of truth for dependencies and version (`flutter_app/pubspec.yaml`).
- Firebase CLI (`firebase.json`) configures functions source, hosting public directory (`flutter_app/build/web`), Firestore rules/indexes, Storage rules, and emulators.
- Codemagic `codemagic.yaml` defines an iOS-only workflow that handles signing, CocoaPods, IPA build, dSYM upload to Crashlytics, App Distribution, and App Store Connect submission.
- A parallel `flutter_app/codemagic.yaml` supports building when Flutter lives at repo root instead of `flutter_app/`, detecting layout automatically.
- Node.js/TypeScript Cloud Functions under `functions/` compiled via `tsc` to `lib/` with `package.json` scripts for deploy and emulators.

**Key files and packages**
- `codemagic.yaml` — monorepo-aware iOS workflow: keychain setup, ASC API PEM preparation, App Groups/Push/Sign-In-with-Apple capability enablement, profile matching against P12, ExportOptions generation, Flutter IPA build, dSYM upload, Firebase App Distribution, and App Store Connect publishing.
- `flutter_app/codemagic.yaml` — alternative workflow for non-monorepo layout with the same signing and publishing steps.
- `firebase.json` — hosting rewrites to Cloud Functions, cache headers per asset type, and emulator ports.
- `flutter_app/pubspec.yaml` — Flutter SDK constraint, dependency versions, assets list (including `.env.example`), and launcher icons configuration.
- `functions/package.json` — Node 22 engine, TypeScript build, Firebase Admin/Functions deps, and migration/utility scripts.
- `functions/tsconfig.json` — CommonJS output to `lib/`, ES2020 target, source maps enabled.
- `scripts/deploy_completo.ps1` — single entry point that splats flags into `deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1`, orchestrating Firestore rules, Functions, Web, Android AAB, and iOS ZIP in one run.
- `scripts/build_android_aab.ps1` — quick AAB builder using `flutter build appbundle --release` with optional release keystore via `android/key.properties`.

**Architecture and conventions**
- Monorepo layout: Flutter app under `flutter_app/`, Cloud Functions under `functions/`, shared automation under `scripts/`. CI detects whether Flutter is at root or in `flutter_app/` and adapts paths accordingly.
- Versioning: marketing version and build number are aligned across platforms. iOS build number is derived from the last App Store Connect build plus an offset; Android Play uses `+pubspec` increment. The script `codemagic_ios_sync_version_from_app_version_dart.sh` keeps iOS in sync with `lib/app_version.dart`.
- Signing: two modes supported — manual P12 + provisioning profile secrets (`CM_CERTIFICATE`, `CM_PROVISIONING_PROFILE`) and API-only mode using App Store Connect keys. Profile-P12 mismatch is detected early via `codemagic_ios_verify_profile_matches_p12.sh` before any heavy build step.
- Hosting: Flutter web output goes to `flutter_app/build/web`; Firebase hosting rewrites specific routes to Cloud Functions and serves static assets with long immutable cache headers while keeping HTML/JS fresh.
- Rules deployment: Firestore and Storage rules live at repo root (`firestore.rules`, `storage.rules`) and are published through Firebase CLI or GCP APIs via helper scripts.

**Conventions and constraints**
- iOS builds are manual-only in Codemagic (no `triggering` section); developers must start builds explicitly.
- `.env` is gitignored and never listed as a Flutter asset; only `.env.example` is committed and included.
- Swift Package Manager is disabled for Flutter (`enable-swift-package-manager: false`) because it breaks CocoaPods/FirebaseCrashlytics installation in CI.
- App Store Connect uploads use Codemagic's native `app_store_connect` publishing block; retrying only the Publishing stage is forbidden because it produces HTTP 90189 "Redundant Binary Upload" due to identical CFBundleVersion.
- dSYM upload to Firebase Crashlytics is mandatory (`CM_CRASHLYTICS_DSYM_REQUIRED=1`) before publishing.
- Android production builds require `android/key.properties` and a signed keystore; debug-signed AABs are rejected by Play Store.
- Functions require Node 22 and are built with `npm run build` (`tsc`) before deployment.