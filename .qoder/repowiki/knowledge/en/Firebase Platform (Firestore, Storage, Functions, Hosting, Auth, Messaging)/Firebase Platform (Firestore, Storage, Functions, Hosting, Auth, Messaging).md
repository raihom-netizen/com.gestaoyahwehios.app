---
kind: external_dependency
name: Firebase Platform (Firestore, Storage, Functions, Hosting, Auth, Messaging)
slug: firebase
category: external_dependency
category_hints:
    - vendor_identity
    - auth_protocol
    - client_constraint
scope:
    - '**'
---

### Firebase Platform
- **Core Services**: Firestore database, Cloud Storage, Cloud Functions, Hosting, Authentication, FCM messaging, Analytics, Crashlytics, Performance Monitoring
- **Project ID**: `gestaoyahweh-21e23` (configured in `.firebaserc`)
- **Hosting Site**: `gestaoyahweh-21e23` with public assets in `flutter_app/build/web`
- **Cloud Functions**: Node 22 runtime, TypeScript compilation, deployed to `us-central1` + `southamerica-east1`
- **Storage Bucket**: `gestaoyahweh-21e23.firebasestorage.app`
- **Multi-tenant Architecture**: All data under `igrejas/{churchId}/` paths for church isolation
- **Web Integration**: Firebase JS SDK for web push notifications, IndexedDB persistence enabled
- **Mobile Integration**: Google Sign-In, Apple Sign-In, FCM for push notifications
- **Known Issues**: `firebaserules.googleapis.com` API returns HTTP 503 during deployment (quota/availability issues)