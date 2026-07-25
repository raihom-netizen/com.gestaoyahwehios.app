---
kind: external_dependency
name: Google Sign-In Authentication
slug: google-sign-in
category: external_dependency
category_hints:
    - auth_protocol
    - vendor_identity
scope:
    - '**'
---

### Google Sign-In Integration
- **Android Configuration**: OAuth client IDs configured in `google-services.json` with multiple certificate hashes
- **iOS Configuration**: Reversed client ID `com.googleusercontent.apps.157235497908-m9fdpqeb6rj8gj6e1fsi9mfjpja2s5bg`
- **Web Support**: Firebase JS SDK integration for web sign-in
- **Multi-platform**: Unified authentication across Android, iOS, and Web platforms
- **Security**: Certificate hash validation for Android release builds