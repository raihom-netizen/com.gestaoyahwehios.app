# Session Management

<cite>
**Referenced Files in This Document**
- [main.dart](file://flutter_app/lib/main.dart)
- [firebase_options.dart](file://flutter_app/lib/firebase_options.dart)
- [url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [masterPlatformAuth.ts](file://functions/src/masterPlatformAuth.ts)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)
- [firebase.json](file://flutter_app/firebase.json)
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Conclusion](#conclusion)
10. [Appendices](#appendices)

## Introduction
This document explains session management for Gestão Yahweh Premium across Flutter web, mobile, and desktop platforms. It covers the Firebase Auth lifecycle, token handling, cross-platform synchronization, automatic re-authentication, session timeouts, concurrent sessions, logout flows, and recovery strategies. It also provides security best practices for token storage, session hijacking prevention, and platform-specific considerations.

## Project Structure
The application is a multi-platform Flutter app with Firebase integration and Cloud Functions supporting session-related operations. Key areas:
- Flutter entry point and initialization
- Firebase configuration per environment
- Web URL strategy to support deep links and resume behavior
- Cloud Functions for session synchronization and platform auth utilities
- Security rules governing Firestore and Storage access based on authenticated sessions

```mermaid
graph TB
subgraph "Flutter App"
A["main.dart"]
B["firebase_options.dart"]
C["url_strategy_web.dart"]
D["pubspec.yaml"]
end
subgraph "Firebase Backend"
E["firestore.rules"]
F["storage.rules"]
G["firebase.json"]
end
subgraph "Cloud Functions"
H["membroSessionSync.ts"]
I["masterPlatformAuth.ts"]
end
A --> B
A --> C
A --> D
A --> E
A --> F
A --> G
A --> H
A --> I
```

**Diagram sources**
- [main.dart](file://flutter_app/lib/main.dart)
- [firebase_options.dart](file://flutter_app/lib/firebase_options.dart)
- [url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)
- [firebase.json](file://flutter_app/firebase.json)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [masterPlatformAuth.ts](file://functions/src/masterPlatformAuth.ts)

**Section sources**
- [main.dart](file://flutter_app/lib/main.dart)
- [firebase_options.dart](file://flutter_app/lib/firebase_options.dart)
- [url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)
- [firebase.json](file://flutter_app/firebase.json)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [masterPlatformAuth.ts](file://functions/src/masterPlatformAuth.ts)

## Core Components
- Firebase Authentication state persistence:
  - Mobile/Desktop: managed by platform-native secure storage via firebase_auth plugin.
  - Web: persisted through browser storage mechanisms; ensure same-site cookies and secure headers are configured.
- Token management:
  - Access tokens are short-lived; refresh tokens enable silent renewal.
  - Custom claims and tenant context should be refreshed when needed.
- Cross-platform session sync:
  - Cloud Function synchronizes member session metadata and enforces policies.
- Local storage strategies:
  - Avoid storing raw tokens in app-local storage; rely on Firebase SDK-managed persistence.
  - Use secure storage only for non-sensitive UI state (e.g., last user id).
- Secure token handling:
  - Validate tokens server-side using Firebase Admin SDK or callable functions.
  - Enforce least privilege via Firestore/Storage rules.

**Section sources**
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [masterPlatformAuth.ts](file://functions/src/masterPlatformAuth.ts)

## Architecture Overview
The session architecture spans client initialization, authentication, token refresh, and backend enforcement.

```mermaid
sequenceDiagram
participant App as "Flutter App"
participant FA as "Firebase Auth"
participant Store as "Local Persistence"
participant Func as "Cloud Functions"
participant Rules as "Firestore/Storage Rules"
App->>FA : Initialize Auth (platform-specific)
FA-->>Store : Restore session (secure storage / browser)
App->>FA : Get current user and tokens
FA-->>App : User + ID token
App->>Rules : Access data with ID token
Rules-->>App : Allow/Deny based on claims and rules
App->>Func : Call session sync function
Func-->>App : Update session metadata / policy
FA->>FA : Silent token refresh when needed
```

**Diagram sources**
- [main.dart](file://flutter_app/lib/main.dart)
- [firebase_options.dart](file://flutter_app/lib/firebase_options.dart)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)

## Detailed Component Analysis

### Firebase Auth Initialization and State Restoration
- The app initializes Firebase and sets up platform-specific behaviors:
  - On web, URL strategy ensures consistent routing and deep link handling.
  - On mobile/desktop, native secure storage persists auth state.
- Ensure persistence settings align with platform capabilities and security requirements.

```mermaid
flowchart TD
Start(["App Start"]) --> InitFB["Initialize Firebase"]
InitFB --> SetPersistence["Configure Auth Persistence"]
SetPersistence --> CheckUser{"Existing Session?"}
CheckUser --> |Yes| Restore["Restore User from Secure Storage"]
CheckUser --> |No| Guest["Guest Mode / Login Required"]
Restore --> Ready["Ready with Auth State"]
Guest --> Ready
```

**Diagram sources**
- [main.dart](file://flutter_app/lib/main.dart)
- [firebase_options.dart](file://flutter_app/lib/firebase_options.dart)
- [url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)

**Section sources**
- [main.dart](file://flutter_app/lib/main.dart)
- [firebase_options.dart](file://flutter_app/lib/firebase_options.dart)
- [url_strategy_web.dart](file://flutter_app/lib/url_strategy_web.dart)

### Automatic Re-authentication and Token Refresh
- Firebase Auth automatically refreshes short-lived ID tokens.
- For sensitive operations, call getToken() to obtain a fresh token and pass it to backend calls.
- Implement retry logic for transient network errors during token refresh.

```mermaid
sequenceDiagram
participant Client as "Flutter App"
participant Auth as "Firebase Auth"
participant Server as "Backend API"
Client->>Auth : getToken(forceRefresh=false)
Auth-->>Client : ID token (cached if valid)
Client->>Server : Request with ID token
Server-->>Client : 401 Unauthorized (token expired)
Client->>Auth : getToken(forceRefresh=true)
Auth-->>Client : New ID token
Client->>Server : Retry request with new token
Server-->>Client : Success
```

**Diagram sources**
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [masterPlatformAuth.ts](file://functions/src/masterPlatformAuth.ts)

**Section sources**
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [masterPlatformAuth.ts](file://functions/src/masterPlatformAuth.ts)

### Cross-Platform Session Synchronization
- Cloud Function synchronizes session metadata and enforces tenant-specific policies.
- Use callable functions to update session state and propagate changes across devices.

```mermaid
sequenceDiagram
participant DeviceA as "Device A"
participant DeviceB as "Device B"
participant Func as "membroSessionSync.ts"
participant DB as "Firestore"
DeviceA->>Func : Update session metadata
Func->>DB : Write session record
DeviceB->>DB : Listen to session changes
DB-->>DeviceB : Realtime update
DeviceB-->>DeviceB : Apply session policy
```

**Diagram sources**
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)

**Section sources**
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)

### Logout Flow
- Clear local state and sign out from Firebase Auth.
- Invalidate any cached tokens and redirect to login screen.
- Optionally revoke refresh tokens server-side for enhanced security.

```mermaid
sequenceDiagram
participant UI as "Logout UI"
participant Auth as "Firebase Auth"
participant Cache as "Local Cache"
participant Server as "Backend"
UI->>Auth : SignOut()
Auth-->>Cache : Clear local tokens/state
UI->>Server : Notify logout (optional)
Server-->>UI : Acknowledge
UI-->>UI : Redirect to Login
```

**Section sources**
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)

### Session Timeout Handling
- Detect idle time and prompt re-authentication for sensitive actions.
- Use Firebase Auth state changes to handle unexpected logouts due to token revocation.

```mermaid
flowchart TD
IdleStart["Idle Timer Start"] --> Activity{"Activity Detected?"}
Activity --> |Yes| Reset["Reset Idle Timer"]
Activity --> |No| Timeout{"Timeout Reached?"}
Timeout --> |No| IdleStart
Timeout --> |Yes| Prompt["Prompt Re-authentication"]
Prompt --> Reauth{"Re-auth Successful?"}
Reauth --> |Yes| Resume["Resume Session"]
Reauth --> |No| Logout["Force Logout"]
```

**Section sources**
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)

### Concurrent Session Management
- Track active sessions per user and enforce limits if required.
- Use Cloud Functions to manage session records and detect conflicts.

```mermaid
sequenceDiagram
participant User as "User"
participant Func as "membroSessionSync.ts"
participant DB as "Firestore"
User->>Func : Create session
Func->>DB : Increment session count
User->>Func : Destroy session
Func->>DB : Decrement session count
DB-->>User : Current session status
```

**Section sources**
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)

### Session Recovery
- Handle app restarts by restoring Firebase Auth state.
- Recover from network failures by retrying token refresh and re-subscribing to listeners.

```mermaid
flowchart TD
Restart["App Restart"] --> RestoreState["Restore Firebase Auth State"]
RestoreState --> NetworkOK{"Network Available?"}
NetworkOK --> |Yes| SyncData["Sync Data with Backend"]
NetworkOK --> |No| OfflineMode["Enter Offline Mode"]
SyncData --> Ready["Ready"]
OfflineMode --> Ready
```

**Section sources**
- [main.dart](file://flutter_app/lib/main.dart)
- [firebase_options.dart](file://flutter_app/lib/firebase_options.dart)

## Dependency Analysis
Key dependencies and their roles in session management:
- Flutter app depends on Firebase Auth for identity and token management.
- Cloud Functions provide session synchronization and policy enforcement.
- Security rules enforce access control based on authenticated sessions.

```mermaid
graph LR
App["Flutter App"] --> Auth["Firebase Auth"]
App --> Rules["Security Rules"]
App --> Funcs["Cloud Functions"]
Funcs --> DB["Firestore"]
Rules --> DB
```

**Diagram sources**
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)

**Section sources**
- [pubspec.yaml](file://flutter_app/pubspec.yaml)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)

## Performance Considerations
- Minimize token refresh calls by caching tokens where appropriate.
- Use real-time listeners judiciously to avoid excessive bandwidth usage.
- Implement offline-first strategies with local caching and background sync.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and resolutions:
- Session not persisting on web: Verify cookie settings and CORS configuration.
- Token expiration errors: Implement retry logic with forceRefresh.
- Unauthorized access: Review Firestore/Storage rules and custom claims.
- Session sync failures: Check Cloud Function logs and error handling.

**Section sources**
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)
- [membroSessionSync.ts](file://functions/src/membroSessionSync.ts)

## Conclusion
Effective session management in Gestão Yahweh Premium relies on Firebase Auth’s robust persistence, secure token handling, and Cloud Functions for synchronization. By following the patterns and best practices outlined here, you can ensure a seamless and secure user experience across all platforms.

[No sources needed since this section summarizes without analyzing specific files]

## Appendices
- Security Best Practices:
  - Never store raw tokens in app-local storage.
  - Use HTTPS and secure cookies on web.
  - Implement role-based access control with custom claims.
- Platform-Specific Notes:
  - Web: Configure SameSite cookies and CSP headers.
  - Mobile: Leverage platform secure storage.
  - Desktop: Follow OS-specific secure storage guidelines.

[No sources needed since this section provides general guidance]