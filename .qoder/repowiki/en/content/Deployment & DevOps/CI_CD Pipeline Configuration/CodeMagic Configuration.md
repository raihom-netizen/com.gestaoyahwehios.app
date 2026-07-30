# CodeMagic Configuration

<cite>
**Referenced Files in This Document**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)
- [codemagic_ios_install_signing.sh](file://scripts/codemagic_ios_install_signing.sh)
- [codemagic_ios_install_signing_api_only.sh](file://scripts/codemagic_ios_install_signing_api_only.sh)
- [codemagic_ios_prepare_build_ipa.sh](file://scripts/codemagic_ios_prepare_build_ipa.sh)
- [codemagic_ios_validate_export_options.py](file://scripts/codemagic_ios_validate_export_options.py)
- [codemagic_ios_write_export_options.py](file://scripts/codemagic_ios_write_export_options.py)
- [codemagic_ios_verify_env_apple_and_signing.sh](file://scripts/codemagic_ios_verify_env_apple_and_signing.sh)
- [codemagic_ios_fetch_profile_matching_p12.sh](file://scripts/codemagic_ios_fetch_profile_matching_p12.sh)
- [codemagic_ios_ensure_deployment_target_15.sh](file://scripts/codemagic_ios_ensure_deployment_target_15.sh)
- [codemagic_ios_bump_pods_deployment_to_14.sh](file://scripts/codemagic_ios_bump_pods_deployment_to_14.sh)
- [codemagic_ios_bump_pods_deployment_to_15.sh](file://scripts/codemagic_ios_bump_pods_deployment_to_15.sh)
- [codemagic_ios_pod_install.sh](file://scripts/codemagic_ios_pod_install.sh)
- [codemagic_ios_upload_crashlytics_dsyms.sh](file://scripts/codemagic_ios_upload_crashlytics_dsyms.sh)
- [codemagic_ios_normalize_ipa_for_asc.sh](file://scripts/codemagic_ios_normalize_ipa_for_asc.sh)
- [codemagic_ios_sync_version_from_app_version_dart.sh](file://scripts/codemagic_ios_sync_version_from_app_version_dart.sh)
- [codemagic_ios_read_asc_floor.sh](file://scripts/codemagic_ios_read_asc_floor.sh)
- [codemagic_ios_stamp_asc_floor.sh](file://scripts/codemagic_ios_stamp_asc_floor.sh)
- [codemagic_ios_asc_latest_build_number.sh](file://scripts/codemagic_ios_asc_latest_build_number.sh)
- [codemagic_ios_enable_push_notifications.py](file://scripts/codemagic_ios_enable_push_notifications.py)
- [codemagic_ios_enable_app_groups.py](file://scripts/codemagic_ios_enable_app_groups.py)
- [codemagic_ios_enable_sign_in_with_apple.py](file://scripts/codemagic_ios_enable_sign_in_with_apple.py)
- [codemagic_ios_ensure_widget_appstore_profile.py](file://scripts/codemagic_ios_ensure_widget_appstore_profile.py)
- [codemagic_ios_delete_appstore_profiles.py](file://scripts/codemagic_ios_delete_appstore_profiles.py)
- [codemagic_ios_profile_utils.py](file://scripts/codemagic_ios_profile_utils.py)
- [codemagic_ios_team_signing_prepare_exportoptions.sh](file://scripts/codemagic_ios_team_signing_prepare_exportoptions.sh)
- [codemagic_ios_pre_publish_90189_gate.sh](file://scripts/codemagic_ios_pre_publish_90189_gate.sh)
- [codemagic_ios_cp_ipa_safe.sh](file://scripts/codemagic_ios_cp_ipa_safe.sh)
- [codemagic_ios_p12_password_helpers.sh](file://scripts/codemagic_ios_p12_password_helpers.sh)
- [codemagic_ios_verify_profile_matches_p12.sh](file://scripts/codemagic_ios_verify_profile_matches_p12.sh)
- [codemagic_ios_verify_widget_profile.py](file://scripts/codemagic_ios_verify_widget_profile.py)
- [build_ios_ipa_macos.sh](file://scripts/build_ios_ipa_macos.sh)
- [prepare_codemagic_paste_from_bootstrap.ps1](file://IOS/prepare_codemagic_paste_from_bootstrap.ps1)
- [CODEMAGIC_APP_STORE_INTEGRATION.txt](file://IOS/CODEMAGIC_APP_STORE_INTEGRATION.txt)
- [CODEMAGIC_SIGNING_FIX.md](file://IOS/CODEMAGIC_SIGNING_FIX.md)
- [CODEMAGIC_INVALID_BINARY.md](file://IOS/CODEMAGIC_INVALID_BINARY.md)
- [CODEMAGIC_90189.md](file://IOS/CODEMAGIC_90189.md)
- [CODEMAGIC_FETCH_CONFIG.txt](file://IOS/CODEMAGIC_FETCH_CONFIG.txt)
- [CREDENCIAIS_APPLE_ATUAL.txt](file://IOS/CREDENCIAIS_APPLE_ATUAL.txt)
- [app_store_connect_issuer_id.txt](file://IOS/app_store_connect_issuer_id.txt)
- [ExportOptions.plist](file://flutter_app/ios/ExportOptions.plist)
- [Podfile](file://flutter_app/ios/Podfile)
- [GoogleService-Info.plist](file://flutter_app/ios/Runner/GoogleService-Info.plist)
- [google-services.json](file://flutter_app/android/app/google-services.json)
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)
- [key.properties.example](file://flutter_app/android/key.properties.example)
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [firebase.json](file://flutter_app/firebase.json)
- [YahwehTdjsonStatic.podspec](file://flutter_app/ios/Frameworks/YahwehTdjsonStatic.podspec)
- [TDLIB_README.txt](file://flutter_app/ios/Frameworks/TDLIB_README.txt)
- [download_tdlib.ps1](file://scripts/download_tdlib.ps1)
- [download_tdlib.sh](file://scripts/download_tdlib.sh)
- [setup_tdlib.ps1](file://scripts/setup_tdlib.ps1)
- [download_tdlib.dart](file://flutter_app/tool/download_tdlib.dart)
- [setup_tdlib.dart](file://flutter_app/tool/setup_tdlib.dart)
</cite>

## Update Summary
**Changes Made**
- Added TDLib framework integration section for Telegram library support
- Updated iOS build configuration to include Associated Domains capability for Universal Links
- Enhanced CI/CD pipeline documentation with TDLib setup and deployment steps
- Added new scripts and tools for TDLib management and configuration

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [TDLib Framework Integration](#tdlib-framework-integration)
7. [Associated Domains and Universal Links](#associated-domains-and-universal-links)
8. [Dependency Analysis](#dependency-analysis)
9. [Performance Considerations](#performance-considerations)
10. [Troubleshooting Guide](#troubleshooting-guide)
11. [Conclusion](#conclusion)
12. [Appendices](#appendices)

## Introduction
This document provides comprehensive CodeMagic configuration guidance for the Gestão Yahweh Premium Flutter application. It explains the codemagic.yaml structure, build targets, environment variables, secrets management, and platform-specific configurations for iOS and Android. The configuration now includes enhanced support for TDLib framework integration and Associated Domains capability activation for Universal Links functionality. It also covers signing certificates, provisioning profiles, App Store Connect integration, Flutter builds, native integrations, custom scripts, caching strategies, parallel builds, artifact management, troubleshooting, and performance optimization.

## Project Structure
The repository contains a Flutter app under flutter_app with native iOS and Android directories, plus a rich set of scripts under scripts to automate CodeMagic workflows. The root-level codemagic.yaml is used by CodeMagic to orchestrate builds across platforms. Key configuration artifacts include:
- Flutter app configuration (pubspec.yaml, firebase.json)
- iOS project files (Podfile, ExportOptions.plist, GoogleService-Info.plist)
- Android project files (build.gradle.kts, google-services.json, key properties)
- CodeMagic scripts for signing, validation, and publishing
- TDLib framework components for Telegram integration
- Associated Domains configuration for Universal Links support

```mermaid
graph TB
CM["CodeMagic Orchestrator"] --> Yaml["codemagic.yaml"]
Yaml --> BuildiOS["iOS Build Pipeline"]
Yaml --> BuildAndroid["Android Build Pipeline"]
BuildiOS --> ScriptsIOS["iOS Signing & Validation Scripts"]
BuildiOS --> TDLib["TDLib Framework Setup"]
BuildiOS --> AssociatedDomains["Associated Domains Config"]
BuildAndroid --> ScriptsAndroid["Android Signing & Build Scripts"]
ScriptsIOS --> ExportOpts["ExportOptions.plist"]
ScriptsIOS --> Podfile["Podfile"]
ScriptsIOS --> GSIOS["GoogleService-Info.plist"]
ScriptsAndroid --> Gradle["build.gradle.kts"]
ScriptsAndroid --> GSAndroid["google-services.json"]
BuildiOS --> ArtifactsIOS["IPA / DSYMs"]
BuildAndroid --> ArtifactsAndroid["AAB / APK"]
ArtifactsIOS --> ASC["App Store Connect"]
ArtifactsAndroid --> PlayStore["Google Play Console"]
TDLib --> TDFramework["libtdjson-static.xcframework"]
AssociatedDomains --> Capabilities["Universal Links Capability"]
```

**Diagram sources**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)
- [ExportOptions.plist](file://flutter_app/ios/ExportOptions.plist)
- [Podfile](file://flutter_app/ios/Podfile)
- [GoogleService-Info.plist](file://flutter_app/ios/Runner/GoogleService-Info.plist)
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)
- [google-services.json](file://flutter_app/android/app/google-services.json)
- [YahwehTdjsonStatic.podspec](file://flutter_app/ios/Frameworks/YahwehTdjsonStatic.podspec)

**Section sources**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [firebase.json](file://flutter_app/firebase.json)

## Core Components
- codemagic.yaml: Defines workflows, environments, triggers, and steps for building and deploying Flutter apps on iOS and Android.
- iOS signing and validation scripts: Automate certificate installation, profile matching, export options generation, and IPA normalization.
- Android build and signing: Gradle-based AAB/APK generation using keystore properties and Google services configuration.
- Flutter toolchain: pub get, analyze, test, and build commands orchestrated via CodeMagic steps.
- Secrets and environment variables: Managed through CodeMagic's secure storage and injected into build steps.
- TDLib framework integration: Telegram library setup and configuration for messaging capabilities.
- Associated Domains configuration: Universal Links support for deep linking functionality.

Key responsibilities:
- Environment setup: Install Flutter, CocoaPods, Java, and dependencies.
- Signing: Import P12, install provisioning profiles, configure export options.
- TDLib setup: Download and configure Telegram library framework.
- Associated Domains: Configure Universal Links capabilities.
- Build: Generate platform artifacts (IPA/AAB).
- Validate: Ensure signatures, entitlements, and metadata are correct.
- Publish: Upload to App Store Connect or Google Play.

**Section sources**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)
- [codemagic_ios_install_signing.sh](file://scripts/codemagic_ios_install_signing.sh)
- [codemagic_ios_validate_export_options.py](file://scripts/codemagic_ios_validate_export_options.py)
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)

## Architecture Overview
The CodeMagic pipeline orchestrates multi-platform builds with clear separation between Flutter logic and native platform concerns. iOS builds rely on Apple signing infrastructure and CocoaPods; Android builds use Gradle and Google services. Custom scripts encapsulate complex operations like profile matching, export options generation, artifact normalization, TDLib framework setup, and Associated Domains configuration.

```mermaid
sequenceDiagram
participant Dev as "Developer"
participant CM as "CodeMagic"
participant Yaml as "codemagic.yaml"
participant IOS as "iOS Build"
participant AND as "Android Build"
participant TDLib as "TDLib Setup"
participant AD as "Associated Domains"
participant ASC as "App Store Connect"
participant PLAY as "Google Play"
Dev->>CM : Push code / Trigger build
CM->>Yaml : Parse workflow
Yaml->>IOS : Setup Flutter + CocoaPods
IOS->>TDLib : Download & Configure TDLib
IOS->>AD : Enable Associated Domains
IOS->>IOS : Install signing (P12 + Profiles)
IOS->>IOS : Generate/Validate ExportOptions
IOS->>IOS : Build IPA + DSYMs
IOS-->>ASC : Upload IPA for distribution
Yaml->>AND : Setup JDK + Gradle
AND->>AND : Sync Google Services
AND->>AND : Sign and Build AAB/APK
AND-->>PLAY : Upload AAB for release
CM-->>Dev : Notify status + artifacts
```

**Diagram sources**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)
- [codemagic_ios_install_signing.sh](file://scripts/codemagic_ios_install_signing.sh)
- [codemagic_ios_validate_export_options.py](file://scripts/codemagic_ios_validate_export_options.py)
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)
- [download_tdlib.ps1](file://scripts/download_tdlib.ps1)
- [setup_tdlib.ps1](file://scripts/setup_tdlib.ps1)

## Detailed Component Analysis

### codemagic.yaml Workflow
- Workflows: Define separate pipelines for iOS and Android, including triggers (push, tag), environments, and steps.
- Environments: Specify Flutter version, Xcode, macOS, and Android SDK versions.
- Steps: Include script blocks for setup, build, sign, validate, and publish.
- Artifacts: Configure paths for IPA, AAB, logs, and DSYMs.

Best practices:
- Use environment variables for secrets (e.g., API keys, signing credentials).
- Cache dependencies (Flutter packages, CocoaPods, Gradle) to speed up builds.
- Parallelize independent tasks where possible.

**Section sources**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)

### iOS Signing and Provisioning
- Certificate import: P12 file and password provided via secrets.
- Profile matching: Script verifies that provisioning profile matches P12 and app bundle ID.
- Export options: Generated dynamically based on team, bundle ID, and signing mode.
- Deployment target: Ensures minimum iOS version compatibility.

Key scripts:
- Install signing: Imports P12 and installs profiles.
- Validate export options: Checks entitlements and signing configuration.
- Normalize IPA: Prepares IPA for App Store upload.

**Section sources**
- [codemagic_ios_install_signing.sh](file://scripts/codemagic_ios_install_signing.sh)
- [codemagic_ios_verify_profile_matches_p12.sh](file://scripts/codemagic_ios_verify_profile_matches_p12.sh)
- [codemagic_ios_validate_export_options.py](file://scripts/codemagic_ios_validate_export_options.py)
- [codemagic_ios_normalize_ipa_for_asc.sh](file://scripts/codemagic_ios_normalize_ipa_for_asc.sh)

### Android Build and Signing
- Gradle configuration: Uses build.gradle.kts for signing and packaging.
- Keystore properties: Defined in key.properties (example provided).
- Google services: google-services.json integrated for Firebase features.
- Build variants: Debug and release configurations supported.

Signing process:
- Keystore imported via secrets.
- Gradle signs AAB/APK using stored credentials.
- Artifact uploaded to Google Play.

**Section sources**
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)
- [key.properties.example](file://flutter_app/android/key.properties.example)
- [google-services.json](file://flutter_app/android/app/google-services.json)

### Flutter Toolchain Integration
- Pub get: Installs Dart packages.
- Analyze and test: Code quality checks and unit tests executed before build.
- Build commands: Generates platform-specific artifacts with optimized flags.

Optimization tips:
- Enable build caching for Flutter and platform dependencies.
- Use --no-pub for faster builds when dependencies are cached.
- Split large test suites into parallel jobs.

**Section sources**
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [codemagic.yaml](file://flutter_app/codemagic.yaml)

### App Store Connect Integration
- API key setup: Issuer ID and key file configured via secrets.
- Build number alignment: Scripts ensure consistent versioning between app and store.
- Pre-publish gate: Validates metadata and entitlements before upload.

Automation:
- Fetch latest build number from App Store Connect.
- Stamp version info into app bundle.
- Upload artifacts automatically after successful validation.

**Section sources**
- [codemagic_ios_asc_latest_build_number.sh](file://scripts/codemagic_ios_asc_latest_build_number.sh)
- [codemagic_ios_stamp_asc_floor.sh](file://scripts/codemagic_ios_stamp_asc_floor.sh)
- [codemagic_ios_pre_publish_90189_gate.sh](file://scripts/codemagic_ios_pre_publish_90189_gate.sh)

### Custom Build Scripts
- Pod installation: Ensures CocoaPods dependencies are installed with correct deployment targets.
- Crashlytics upload: DSYMs uploaded for crash reporting.
- Version synchronization: Aligns app version with Dart code.

Script categories:
- Signing and provisioning
- Validation and normalization
- Publishing and automation

**Section sources**
- [codemagic_ios_pod_install.sh](file://scripts/codemagic_ios_pod_install.sh)
- [codemagic_ios_upload_crashlytics_dsyms.sh](file://scripts/codemagic_ios_upload_crashlytics_dsyms.sh)
- [codemagic_ios_sync_version_from_app_version_dart.sh](file://scripts/codemagic_ios_sync_version_from_app_version_dart.sh)

### Environment Variables and Secrets Management
- CodeMagic secrets: Store sensitive data (API keys, passwords, certificates) securely.
- Environment injection: Variables available during build steps.
- Best practices: Never hardcode secrets; use variable substitution.

Common secrets:
- Apple Developer account credentials
- P12 certificate password
- Google services configuration
- Firebase service account keys

**Section sources**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)
- [CREDENCIAIS_APPLE_ATUAL.txt](file://IOS/CREDENCIAIS_APPLE_ATUAL.txt)
- [app_store_connect_issuer_id.txt](file://IOS/app_store_connect_issuer_id.txt)

## TDLib Framework Integration

### TDLib Setup and Configuration
The iOS CI/CD pipeline now includes comprehensive TDLib framework integration for Telegram messaging capabilities. TDLib (Telegram Database Library) provides native Telegram client functionality for the application.

**Updated** Enhanced iOS build pipeline with automated TDLib framework setup and configuration.

Key components:
- **Framework Installation**: Automated download and setup of libtdjson-static.xcframework
- **Podspec Configuration**: Custom podspec for TDLib integration with proper headers and dependencies
- **Build Integration**: Seamless integration with Flutter iOS build process
- **Platform Support**: Multi-architecture support (arm64, x86_64) for device and simulator builds

Setup Process:
1. **Download TDLib**: Automated download via PowerShell or shell scripts
2. **Framework Extraction**: Proper extraction and organization of framework files
3. **Podspec Creation**: Custom podspec configuration for CocoaPods integration
4. **Build Integration**: Automatic inclusion in iOS build process

```mermaid
flowchart TD
Start["TDLib Setup Start"] --> Download["Download TDLib Archive"]
Download --> Extract["Extract Framework Files"]
Extract --> Organize["Organize Framework Structure"]
Organize --> CreatePodspec["Create Custom Podspec"]
CreatePodspec --> Integrate["Integrate with CocoaPods"]
Integrate --> Build["Build with Flutter"]
Build --> Test["Test TDLib Functionality"]
Test --> Complete["Setup Complete"]
```

**Diagram sources**
- [download_tdlib.ps1](file://scripts/download_tdlib.ps1)
- [download_tdlib.sh](file://scripts/download_tdlib.sh)
- [setup_tdlib.ps1](file://scripts/setup_tdlib.ps1)
- [download_tdlib.dart](file://flutter_app/tool/download_tdlib.dart)
- [setup_tdlib.dart](file://flutter_app/tool/setup_tdlib.dart)

**Section sources**
- [YahwehTdjsonStatic.podspec](file://flutter_app/ios/Frameworks/YahwehTdjsonStatic.podspec)
- [TDLIB_README.txt](file://flutter_app/ios/Frameworks/TDLIB_README.txt)
- [download_tdlib.ps1](file://scripts/download_tdlib.ps1)
- [download_tdlib.sh](file://scripts/download_tdlib.sh)
- [setup_tdlib.ps1](file://scripts/setup_tdlib.ps1)
- [download_tdlib.dart](file://flutter_app/tool/download_tdlib.dart)
- [setup_tdlib.dart](file://flutter_app/tool/setup_tdlib.dart)

## Associated Domains and Universal Links

### Universal Links Configuration
The iOS build pipeline now includes automatic Associated Domains capability activation for Universal Links support, enabling seamless web-to-app navigation and deep linking functionality.

**Updated** Enhanced iOS build pipeline with automatic Associated Domains capability activation for Universal Links support.

Key Features:
- **Automatic Capability Activation**: Built-in support for Associated Domains entitlement
- **Domain Verification**: Automated apple-site-association file handling
- **Deep Linking**: Support for universal links from web content
- **Security**: Proper domain verification and security validation

Configuration Process:
1. **Capability Detection**: Automatic detection of Associated Domains requirement
2. **Entitlement Generation**: Dynamic generation of entitlements file
3. **Domain Registration**: Automated registration of associated domains
4. **Build Integration**: Seamless integration with iOS build process

```mermaid
sequenceDiagram
participant Dev as "Developer"
participant CM as "CodeMagic"
participant iOS as "iOS Build"
participant AD as "Associated Domains"
participant ASC as "App Store Connect"
Dev->>CM : Trigger iOS Build
CM->>iOS : Start Build Process
iOS->>AD : Check Associated Domains Config
AD->>AD : Generate Entitlements
AD->>AD : Register Domains
iOS->>iOS : Build with New Entitlements
iOS->>ASC : Upload with Universal Links Support
ASC-->>Dev : Build Success with Deep Linking
```

**Diagram sources**
- [codemagic_ios_enable_associated_domains.py](file://scripts/codemagic_ios_enable_associated_domains.py)
- [ExportOptions.plist](file://flutter_app/ios/ExportOptions.plist)

**Section sources**
- [codemagic_ios_enable_associated_domains.py](file://scripts/codemagic_ios_enable_associated_domains.py)
- [ExportOptions.plist](file://flutter_app/ios/ExportOptions.plist)

## Dependency Analysis
The CodeMagic pipeline depends on multiple external services and internal scripts:
- Flutter SDK and Dart packages
- CocoaPods for iOS dependencies
- Gradle for Android builds
- App Store Connect and Google Play for distribution
- Firebase for backend services
- TDLib framework for Telegram integration
- Associated Domains for Universal Links functionality

```mermaid
graph LR
Flutter["Flutter SDK"] --> Codemagic["CodeMagic"]
CocoaPods["CocoaPods"] --> Codemagic
Gradle["Gradle"] --> Codemagic
TDLib["TDLib Framework"] --> Codemagic
AssociatedDomains["Associated Domains"] --> Codemagic
ASC["App Store Connect"] <- --> Codemagic
Play["Google Play"] <- --> Codemagic
Firebase["Firebase Services"] --> App["Gestão Yahweh App"]
Codemagic --> App
```

**Diagram sources**
- [codemagic.yaml](file://flutter_app/codemagic.yaml)
- [Podfile](file://flutter_app/ios/Podfile)
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)
- [firebase.json](file://flutter_app/firebase.json)
- [YahwehTdjsonStatic.podspec](file://flutter_app/ios/Frameworks/YahwehTdjsonStatic.podspec)

**Section sources**
- [Podfile](file://flutter_app/ios/Podfile)
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)
- [firebase.json](file://flutter_app/firebase.json)

## Performance Considerations
- Caching strategies:
  - Cache Flutter packages (~/.pub-cache)
  - Cache CocoaPods (~/.cocoapods)
  - Cache Gradle dependencies (~/.gradle)
  - Cache TDLib framework downloads
- Parallel builds:
  - Run tests and analysis in parallel jobs
  - Split iOS and Android builds into separate workflows
  - Parallelize TDLib setup with other build steps
- Optimization techniques:
  - Use incremental builds where possible
  - Minimize dependency downloads
  - Optimize asset sizes and image formats
  - Leverage pre-built TDLib framework binaries

## Troubleshooting Guide
Common issues and solutions:
- Signing errors: Verify P12 password and profile matching
- Provisioning failures: Check bundle ID and entitlements
- Build timeouts: Increase resource limits or optimize dependencies
- App Store rejection: Validate metadata and binary requirements
- TDLib integration issues: Verify framework architecture compatibility
- Associated Domains problems: Check domain verification and entitlements

Debugging steps:
- Review build logs for specific error messages
- Test signing locally with same certificates
- Validate export options and entitlements
- Check network connectivity to external services
- Verify TDLib framework integrity and architecture
- Confirm Associated Domains configuration validity

**Section sources**
- [CODEMAGIC_SIGNING_FIX.md](file://IOS/CODEMAGIC_SIGNING_FIX.md)
- [CODEMAGIC_INVALID_BINARY.md](file://IOS/CODEMAGIC_INVALID_BINARY.md)
- [CODEMAGIC_90189.md](file://IOS/CODEMAGIC_90189.md)

## Conclusion
The CodeMagic configuration for Gestão Yahweh Premium provides a robust, automated pipeline for building and distributing Flutter applications across iOS and Android platforms. The enhanced configuration now includes comprehensive TDLib framework integration for Telegram messaging capabilities and Associated Domains support for Universal Links functionality. By leveraging custom scripts, secure secrets management, and optimized build processes, the system ensures reliable releases while maintaining high performance and developer productivity.

## Appendices

### iOS Build Configuration Examples
- Podfile configuration for dependencies
- ExportOptions.plist for signing and distribution
- GoogleService-Info.plist for Firebase integration
- TDLib framework integration setup
- Associated Domains configuration for Universal Links

**Section sources**
- [Podfile](file://flutter_app/ios/Podfile)
- [ExportOptions.plist](file://flutter_app/ios/ExportOptions.plist)
- [GoogleService-Info.plist](file://flutter_app/ios/Runner/GoogleService-Info.plist)
- [YahwehTdjsonStatic.podspec](file://flutter_app/ios/Frameworks/YahwehTdjsonStatic.podspec)

### Android Build Configuration Examples
- build.gradle.kts for signing and packaging
- key.properties.example for keystore configuration
- google-services.json for Firebase setup

**Section sources**
- [build.gradle.kts](file://flutter_app/android/app/build.gradle.kts)
- [key.properties.example](file://flutter_app/android/key.properties.example)
- [google-services.json](file://flutter_app/android/app/google-services.json)

### Secret Management Reference
- Apple credentials and issuer ID
- Certificate and profile management
- Service account keys for Firebase
- TDLib configuration secrets

**Section sources**
- [CREDENCIAIS_APPLE_ATUAL.txt](file://IOS/CREDENCIAIS_APPLE_ATUAL.txt)
- [app_store_connect_issuer_id.txt](file://IOS/app_store_connect_issuer_id.txt)
- [CODEMAGIC_FETCH_CONFIG.txt](file://IOS/CODEMAGIC_FETCH_CONFIG.txt)

### TDLib Framework Documentation
- Framework setup and configuration
- Integration with Flutter iOS builds
- Architecture compatibility requirements
- Troubleshooting common issues

**Section sources**
- [TDLIB_README.txt](file://flutter_app/ios/Frameworks/TDLIB_README.txt)
- [download_tdlib.ps1](file://scripts/download_tdlib.ps1)
- [setup_tdlib.ps1](file://scripts/setup_tdlib.ps1)

### Associated Domains Configuration
- Domain registration process
- Entitlement configuration
- Universal Links setup
- Testing and validation procedures

**Section sources**
- [codemagic_ios_enable_associated_domains.py](file://scripts/codemagic_ios_enable_associated_domains.py)
- [ExportOptions.plist](file://flutter_app/ios/ExportOptions.plist)