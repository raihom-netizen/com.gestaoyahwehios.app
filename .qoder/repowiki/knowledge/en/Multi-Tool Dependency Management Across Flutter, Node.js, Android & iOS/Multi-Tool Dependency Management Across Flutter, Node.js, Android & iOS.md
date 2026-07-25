---
kind: dependency_management
name: Multi-Tool Dependency Management Across Flutter, Node.js, Android & iOS
category: dependency_management
scope:
    - '**'
source_files:
    - flutter_app/pubspec.yaml
    - flutter_app/pubspec.lock
    - functions/package.json
    - functions/package-lock.json
    - flutter_app/android/settings.gradle.kts
    - flutter_app/android/build.gradle.kts
    - flutter_app/ios/Podfile
    - _ecofire_ref/Ecofire_Independente/flutter_app/pubspec.yaml
---

This monorepo manages dependencies through four distinct package managers, each with its own manifest and lockfile strategy:

**Flutter (pub.dev)** — `flutter_app/pubspec.yaml` declares all Dart/Flutter dependencies with caret (`^`) version ranges. The resolved versions are pinned in `flutter_app/pubspec.lock`, which is committed to the repository so builds are reproducible across machines and CI. The SDK constraint is `>=3.12.0 <4.0.0`. Dependencies are sourced from `https://pub.dev` (hosted) with no private registry or `pubspec_overrides.yaml` usage observed. A secondary Flutter project `_ecofire_ref/Ecofire_Independente/flutter_app/pubspec.yaml` maintains a separate dependency set for an independent site build.

**Node.js / Firebase Functions (npm)** — `functions/package.json` pins runtime to `node: 22` via `engines`. Dependencies use caret ranges (`^`). The lockfile `functions/package-lock.json` (lockfileVersion 3) is committed, ensuring deterministic installs. No `.npmrc`, `package-lock.json` overrides, or private registries are present; packages resolve from the default npm registry.

**Android (Gradle)** — `flutter_app/android/settings.gradle.kts` defines plugin versions centrally (AGP 8.11.1, Kotlin 2.2.20, Google Services 4.4.2, Crashlytics 3.0.3). `flutter_app/android/build.gradle.kts` adds a local Maven fallback at `local-maven` before `google()` and `mavenCentral()`, used to host locally built artifacts when public repos are unavailable. No Gradle version catalog or BOM is used; versions are declared inline.

**iOS (CocoaPods)** — `flutter_app/ios/Podfile` sets `platform :ios, '15.5'` and uses `use_frameworks!` with modular headers. CocoaPods is invoked through Flutter's `flutter_install_all_ios_pods` helper. There is no committed `Podfile.lock`; pods are installed fresh per build, relying on semantic version resolution by CocoaPods.

**Lockfile & reproducibility conventions:**
- `pubspec.lock` and `package-lock.json` are committed, pinning exact transitive versions for Flutter and Node.js.
- No `Podfile.lock` is tracked; iOS native dependencies are resolved at install time.
- No `gradle.lockfile` or version catalogs are used for Android.
- No vendoring of third-party code exists; all packages are fetched remotely at build time.

**Private / offline handling:**
- The Android `local-maven` directory is a documented fallback for unstable network conditions or tag mismatches against Maven Central.
- TDLib integration is intentionally excluded from production `pubspec.yaml`; binary setup is deferred to a CI step (`tool/setup_tdlib.dart --ios-only`) rather than being committed as a vendored artifact.

**CI-driven updates:**
- Codemagic pipelines (`codemagic.yaml` in root and `flutter_app/codemagic.yaml`) drive builds and deployments but do not perform automated dependency updates; dependency changes are made manually and committed alongside code.