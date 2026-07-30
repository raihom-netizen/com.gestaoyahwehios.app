---
kind: dependency_management
name: Multi-Tool Dependency Management (Flutter pub, npm, CocoaPods, Gradle)
category: dependency_management
scope:
    - '**'
source_files:
    - flutter_app/pubspec.yaml
    - flutter_app/pubspec.lock
    - flutter_app/.flutter-plugins-dependencies
    - flutter_app/android/build.gradle.kts
    - flutter_app/android/settings.gradle.kts
    - flutter_app/ios/Podfile
    - functions/package.json
    - functions/package-lock.json
    - scripts/package.json
    - scripts/package-lock.json
    - security_rules_test_firestore/package.json
    - security_rules_test_firestore/package-lock.json
---

This repository manages dependencies across four distinct ecosystems, each with its own tooling and lockfile strategy:

**Flutter (Dart) — `flutter_app/`**
- Dependencies declared in `pubspec.yaml` under `dependencies` and `dev_dependencies`, using caret ranges (`^x.y.z`) for most packages.
- Deterministic builds via `pubspec.lock`, which is committed to version control and records exact resolved versions, SHA256 hashes, and source URLs from `https://pub.dev`.
- Platform-specific native plugins are tracked by the generated `.flutter-plugins-dependencies` file (iOS, Android, macOS, Linux, Windows, Web), listing per-platform plugin paths and native build flags.
- iOS native dependencies are managed through CocoaPods via `Podfile`; the Podfile explicitly sets `platform :ios, '15.5'`, disables stats, and pins `FirebaseCrashlytics` as a direct pod. A `Podfile.lock` would normally be committed but is absent here.
- Android uses Gradle Kotlin DSL: `android/build.gradle.kts` declares repositories with a local Maven fallback (`local-maven`) before Google/Maven Central; `android/settings.gradle.kts` pins plugin versions (AGP 8.11.1, Kotlin 2.2.20, Google Services 4.4.2, Crashlytics 3.0.3).
- Flutter SDK constraint is `>=3.12.0 <4.0.0`; Swift Package Manager is explicitly disabled via `config.enable-swift-package-manager: false`.

**Node.js / Firebase Functions — `functions/`**
- Declared in `package.json` with `engines.node: "22"` pinning the runtime.
- Dependencies use caret ranges (`firebase-admin ^13.7.0`, `firebase-functions ^7.2.5`, `googleapis ^140.0.0`, etc.).
- Deterministic resolution via `package-lock.json` (lockfileVersion 3), committed to the repo.
- Build script compiles TypeScript (`tsc`) to `lib/index.js`; devDependencies include TypeScript and type definitions.

**Utility scripts — `scripts/`**
- Separate `package.json` for data migration/import utilities (`csv-parse ^5.5.6`, `firebase-admin ^12.7.0`), with its own `package-lock.json`.

**Security rules testing — `security_rules_test_firestore/`**
- Isolated test package with `@firebase/rules-unit-testing ^4.0.1` and `firebase ^11.6.0` as devDependencies, with its own `package-lock.json`.

**CI/CD integration**
- GitHub Actions workflows exist (`main.yml`, `deploy-web.yml`, `codemagic_ios_trigger.yml`) but the primary CI is Codemagic (`codemagic.yaml` at root), which orchestrates Flutter builds, iOS signing, and deployment.
- The CodeMagic configuration references environment variables for Apple signing keys and secrets rather than vendoring them.

**Key conventions observed:**
- All lockfiles (`pubspec.lock`, all `package-lock.json` files) are committed alongside their manifests, ensuring reproducible builds across environments.
- Version ranges use caret (`^`) semantics for flexibility while lockfiles pin exact versions.
- No vendoring of third-party code (no `vendor/`, `node_modules/` is not committed except where it appears transiently); dependencies are downloaded at build time.
- Private registries are not configured in any manifest; all packages resolve from public registries (pub.dev, npmjs.org, Google/Maven Central).
- Native platform dependencies are kept separate from language-level dependency management (CocoaPods for iOS, Gradle for Android, pub for Dart, npm for Node).