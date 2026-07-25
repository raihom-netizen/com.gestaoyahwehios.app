---
kind: external_dependency
name: Apple App Store Connect (API Keys & Distribution)
slug: apple-app-store-connect
category: external_dependency
category_hints:
    - vendor_identity
    - auth_protocol
scope:
    - '**'
---

### Apple App Store Connect Integration
- **API Authentication**: Private key (.p8 files: `AuthKey_85X9UNAT43.p8`, `AuthKey_U3XPUHK47.p8`) with issuer ID and key ID
- **Signing Certificates**: Distribution certificates (.cer files) and provisioning profiles (.mobileprovision)
- **Bundle IDs**: `com.gestaoyahwehios.app` for iOS app, `br.com.gestaoyahweh.app` for alternate configuration
- **App Store Submission**: Automated via Codemagic with validation gates to prevent common rejections
- **TestFlight**: Distribution to tester groups through Firebase App Distribution integration
- **Version Management**: Build numbers synchronized with Dart version to avoid conflicts (error 90189 prevention)