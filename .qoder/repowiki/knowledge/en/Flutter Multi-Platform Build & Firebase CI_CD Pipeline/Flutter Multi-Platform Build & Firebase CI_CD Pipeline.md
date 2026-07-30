---
kind: build_system
name: Flutter Multi-Platform Build & Firebase CI/CD Pipeline
category: build_system
scope:
    - '**'
source_files:
    - codemagic.yaml
    - flutter_app/codemagic.yaml
    - firebase.json
    - flutter_app/pubspec.yaml
    - functions/package.json
    - scripts/deploy_completo.ps1
    - functions/tsconfig.json
    - flutter_app/android/build.gradle.kts
---

This project uses a comprehensive multi-platform build system centered around Flutter for cross-platform app development (Web, iOS, Android, Windows, macOS) with Firebase as the backend. The build system is orchestrated through multiple layers of automation scripts and CI/CD pipelines.

**Primary Build Tools:**
- **Flutter SDK 3.44.1** with Dart SDK >=3.12.0 for the main application in `flutter_app/`
- **Gradle** (Kotlin DSL) for Android builds with custom repository configuration including local Maven fallback
- **Xcode/iOS toolchain** for iOS builds with CocoaPods dependency management
- **TypeScript/Node.js 22** for Firebase Cloud Functions compilation from `functions/src/` to `functions/lib/`

**CI/CD Architecture:**
- **Codemagic** is the primary CI/CD platform defined in both root `codemagic.yaml` and `flutter_app/codemagic.yaml`, supporting monorepo detection and dual deployment targets
- **GitHub Actions** workflows exist but are minimal (`main.yml` is empty), suggesting Codemagic handles the heavy lifting
- **Firebase CLI** manages hosting, functions deployment, and Firestore rules distribution

**Build Artifacts & Distribution:**
- iOS: IPA files built with App Store Connect API integration, TestFlight submission, and Firebase App Distribution
- Android: AAB (Android App Bundle) generation for Play Store deployment
- Web: Static site deployment to Firebase Hosting with optimized caching headers
- Functions: TypeScript compiled to JavaScript with source maps for debugging

**Version Management:**
- Single version string in `pubspec.yaml` (format: `11.2.305+2139`) shared across platforms
- Automated version synchronization between iOS build numbers and App Store Connect
- Build number floor tracking to prevent duplicate uploads (error 90189)

**Signing & Security:**
- Apple Distribution certificates managed via P12 files or App Store Connect API
- Provisioning profiles with App Groups support for widgets
- Firebase service accounts and Google Cloud credentials for automated deployments
- Code signing validation at multiple stages to prevent "Invalid Binary" errors

**Deployment Scripts:**
- Comprehensive PowerShell script ecosystem in `scripts/` directory for local development and production deployments
- One-command deployment via `deploy_completo.ps1` orchestrating all components
- Specialized scripts for iOS code signing, Firebase rules deployment, and storage CORS configuration
- Pre-flight checks and production gates to ensure deployment safety