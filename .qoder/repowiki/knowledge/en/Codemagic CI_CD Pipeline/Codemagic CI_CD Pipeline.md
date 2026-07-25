---
kind: external_dependency
name: Codemagic CI/CD Pipeline
slug: codemagic
category: external_dependency
category_hints:
    - vendor_identity
    - migration_status
scope:
    - '**'
---

### Codemagic Build & Deployment
- **iOS Builds**: Automated IPA generation, code signing, App Store Connect integration
- **Signing**: P12 certificates, provisioning profiles, App Store Connect API keys
- **Distribution**: Firebase App Distribution for testers, direct App Store Connect submission
- **Security**: Base64-encoded secrets for certificates and provisioning profiles
- **Validation**: Pre-publish gates to prevent App Store rejection (error 90189)
- **Artifacts**: IPA files, dSYM for Crashlytics, build logs
- **Integration**: Monorepo-aware with shared scripts between root and flutter_app directories