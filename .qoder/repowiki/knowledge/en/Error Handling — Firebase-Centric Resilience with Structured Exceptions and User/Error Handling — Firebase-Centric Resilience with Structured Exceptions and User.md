---
kind: error_handling
name: Error Handling — Firebase-Centric Resilience with Structured Exceptions and User-Facing Messages
category: error_handling
scope:
    - '**'
source_files:
    - flutter_app/lib/core/firebase_user_facing_error.dart
    - flutter_app/lib/utils/firestore_web_guard.dart
    - flutter_app/lib/core/firebase_bootstrap_service.dart
    - flutter_app/lib/core/system_health/system_last_error_registry.dart
    - functions/src/index.ts
---

## What system/approach is used

The monorepo uses a **Firebase-centric error model** across both the Flutter client (`flutter_app/lib`) and the Cloud Functions backend (`functions/src`). Errors are propagated as:
- **Typed Dart exceptions** (custom `Exception` classes) in the Flutter app, wrapped by a central formatter that translates raw Firebase/Platform errors into user-friendly Portuguese messages.
- **`functions.https.HttpsError`** thrown from every callable HTTP endpoint in the Node.js backend, using the standard Firebase error codes (`unauthenticated`, `invalid-argument`, `permission-denied`, `not-found`, `internal`).
- A **web-specific resilience layer** (`FirestoreWebGuard`) that detects transient SDK assertion failures and client termination on the web platform and performs soft recovery without terminating the Firestore singleton.

There is no centralized middleware or global `try/catch` handler; instead, each layer (bootstrap, publish, chat, panel reads) encapsulates its own retry/recovery logic around the specific failure modes it expects.

## Key files and packages

- **Flutter client**
  - `flutter_app/lib/core/firebase_user_facing_error.dart` — `formatFirebaseErrorForUser()` maps `FirebaseAuthException`, `FirebaseException`, `PlatformException`, `TimeoutException`, `SocketException`, and internal Firestore web assertions to localized user messages.
  - `flutter_app/lib/utils/firestore_web_guard.dart` — `FirestoreWebGuard` class: limits concurrent web reads, detects `INTERNAL ASSERTION` / `client has already been terminated` / target-id conflicts, provides `runWithWebRecovery`, `runChatWriteWithRecovery`, and soft/hard session recovery without calling `terminate()`.
  - `flutter_app/lib/core/firebase_bootstrap_service.dart` — `FirebaseBootstrapService` and `FirebaseBootstrapException` implement single-flight initialization, health checks per subsystem (auth, firestore, storage, functions, fcm), and guarded execution with exponential backoff for transient failures.
  - `flutter_app/lib/core/system_health/system_last_error_registry.dart` — in-memory ring buffer of the last N errors (`SystemLastErrorEntry`) consumed by the admin "system health" page.
  - Domain-specific exception types: `ChurchPanelModuleRemovedException`, `ResilientPublishQueuedException`, `ChurchRepositoryException`, `ChurchTenantMediaException`, `FinanceComprovanteQueuedLocally`, `MemberProfilePhotoQueuedLocally`.

- **Cloud Functions backend**
  - `functions/src/index.ts` (7200+ lines) — every callable function validates auth/roles and throws `functions.https.HttpsError` with explicit codes; catch blocks rewrap unknown errors as `internal`.
  - Individual domain modules (`churchMercadoPago.ts`, `certificadosLote.ts`, `churchChatAdminPurge.ts`, etc.) follow the same pattern: early parameter validation → role checks → throw typed `HttpsError`.

## Architecture and conventions

1. **Client-side error classification**
   - All Firebase/Platform exceptions flow through `formatFirebaseErrorForUser()`, which distinguishes network timeouts, socket errors, auth quota exceeded, permission denied, Storage unauthenticated/object-not-found, and Firestore web internal assertions. Non-Firebase errors are truncated to ≤200 chars.
   - Web-only transient errors (`isInternalAssertionError`, `isClientTerminated`, `isTargetIdConflict`) are detected via string matching against known SDK messages and handled by `FirestoreWebGuard` rather than surfacing to the UI.

2. **Bootstrapping and health gating**
   - `FirebaseBootstrapService.initialize()` runs once, returns a `FirebaseBootstrapResult` with an embedded `FirebaseHealthReport`. Failure paths wrap the root cause in `FirebaseBootstrapException` carrying a stable `code` (e.g. `auth_quota_exceeded`, `no_firebase_app`, `timeout`) and a precomputed `userMessage`.
   - `healthCheck()` probes each subsystem independently, caching results for ~45 s to avoid repeated probes.

3. **Retry and recovery patterns**
   - `FirebaseBootstrapService.runGuarded()` wraps any operation with up to 3 attempts, exponential backoff, benign-error short-circuiting, and automatic re-init when `_isNoFirebaseApp` is detected.
   - `FirestoreWebGuard.runWithWebRecovery()` limits web retries to 2 attempts (to avoid cascading `INTERNAL ASSERTION` storms) and triggers soft/hard session recovery between attempts.
   - Chat writes use `runChatWriteWithRecovery()` with up to 5 attempts and a WhatsApp-style retry curve.

4. **Backend error contract**
   - Every callable begins with `if (!context.auth) throw new HttpsError("unauthenticated", ...)` and validates required fields before any DB access.
   - Role checks use helper predicates (`canManageTenant`, `callerBelongsToTenant`, `isAdminPanelActor`) and throw `permission-denied` when violated.
   - Unknown exceptions are caught and rethrown as `HttpsError("internal", message)`, preserving the original message for diagnostics.

5. **Observability**
   - `CrashlyticsService.record()` is called selectively based on `shouldReport()` heuristics to avoid noise from benign/transient errors.
   - `SystemLastErrorRegistry` keeps the last 12 entries in-process for the admin health dashboard.

## Conventions and constraints observed

- **Never call `Firestore.terminate()` on the web.** The `FirestoreWebGuard` comments explicitly forbid it because it kills the singleton and causes `failed-precondition: client has already been terminated` cascades. Recovery uses `disableNetwork`/`enableNetwork` cycles instead.
- **All callable endpoints must throw `functions.https.HttpsError`** with one of the documented codes; raw `throw new Error(...)` is only used internally and recaught to produce an `internal` response.
- **User-facing messages are always produced by a formatter**, never by concatenating raw error strings at call sites. The formatter centralizes localization (Portuguese) and truncation.
- **Transient web SDK errors are classified, not surfaced**: `INTERNAL ASSERTION`, `WatchChangeAggregator`, `PersistentListenStream`, and `Target ID already exists` are treated as recoverable and trigger soft session recovery rather than UI banners.
- **Exceptions are domain-scoped Dart `Exception` implementations** (not `Error`), carrying structured metadata (`code`, `userMessage`, `cause`, optional `health` report) so callers can distinguish actionable failures from queued/offline states.