---
kind: dependency_management
name: Multi-Platform Dependency Management (Flutter, Android Gradle, iOS CocoaPods, Node.js)
category: dependency_management
scope:
    - '**'
source_files:
    - flutter_app/pubspec.yaml
    - flutter_app/pubspec.lock
    - flutter_app/android/settings.gradle.kts
    - flutter_app/android/build.gradle.kts
    - flutter_app/android/app/build.gradle.kts
    - flutter_app/ios/Podfile
    - functions/package.json
    - functions/package-lock.json
---

This repository manages dependencies across four distinct ecosystems, each with its own manifest and lockfile strategy:

**Flutter (Dart/Flutter SDK)**
- Dependencies declared in `flutter_app/pubspec.yaml` using semantic version ranges (`^x.y.z`) against the public `pub.dev` registry.
- Deterministic builds enforced via `flutter_app/pubspec.lock`, which pins every transitive dependency to a specific version and SHA256 hash. The lockfile is committed to version control.
- Flutter SDK itself is referenced via `sdk: flutter` constraints; the environment section pins `sdk: ">=3.12.0 <4.0.0"`.
- A local Maven fallback directory (`android/local-maven`) is configured in `android/build.gradle.kts` as a first-resort repository for cases where Maven Central is unreliable, though it appears empty in this snapshot.
- Swift Package Manager is explicitly disabled (`enable-swift-package-manager: false`) in favor of CocoaPods for iOS native dependencies.

**Android (Gradle/Kotlin)**
- Plugin versions are centralized in `flutter_app/android/settings.gradle.kts` (AGP 8.11.1, Kotlin 2.2.20, Google Services 4.4.2, Crashlytics 3.0.3).
- Repository order is explicit: local-maven → google() → mavenCentral(), ensuring predictable resolution.
- Android SDK path is externalized to `local.properties`, pointing to an absolute path on the developer machine (`C:\dev\gestao-yahweh-toolchain\android-sdk`).
- A single direct dependency on `com.google.android.gms:play-services-ads-identifier:18.2.0` is declared in `app/build.gradle.kts`.

**iOS (CocoaPods)**
- Native dependencies managed through `flutter_app/ios/Podfile`, which uses `use_frameworks!` and `use_modular_headers!`.
- FirebaseCrashlytics is explicitly added as a pod outside of Flutter's auto-generation to ensure dSYM upload works in CI without Xcode phases.
- Deployment target pinned to iOS 15.5+ (required by Google ML Kit 0.15.x/0.13.x), enforced both in the Podfile platform declaration and in post_install build settings.
- No `Podfile.lock` is visible in the snapshot; pods are resolved at install time.

**Node.js / Firebase Cloud Functions**
- Server-side dependencies declared in `functions/package.json` with caret ranges (`^x.y.z`) against npm registry.
- Deterministic builds via committed `functions/package-lock.json` (lockfileVersion 3).
- Node runtime pinned to version 22 via the `engines` field.
- TypeScript compilation step (`tsc`) produces JavaScript output under `lib/` before deployment.

**Cross-cutting conventions**
- All package managers use caret (`^`) version ranges in manifests, allowing patch/minor updates while constraining major versions.
- Lockfiles (`pubspec.lock`, `package-lock.json`) are committed alongside manifests to guarantee reproducible builds across environments.
- Private registries or vendoring are not used; all packages resolve from public registries (pub.dev, npmjs.org, Maven Central, Google Maven) with one local Maven fallback directory.
- Platform-specific toolchains (Flutter SDK, Android SDK, Node 22, CocoaPods) are expected to be installed externally and referenced via configuration files rather than vendored.