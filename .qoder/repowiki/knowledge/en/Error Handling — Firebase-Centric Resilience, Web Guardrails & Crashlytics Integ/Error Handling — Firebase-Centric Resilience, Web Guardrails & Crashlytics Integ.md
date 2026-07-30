---
kind: error_handling
name: Error Handling — Firebase-Centric Resilience, Web Guardrails & Crashlytics Integration
category: error_handling
scope:
    - '**'
source_files:
    - flutter_app/lib/utils/firestore_retry.dart
    - flutter_app/lib/utils/firestore_web_guard.dart
    - flutter_app/lib/core/firebase_bootstrap_service.dart
    - flutter_app/lib/services/crashlytics_benign_errors.dart
    - flutter_app/lib/core/firebase_user_facing_error.dart
    - flutter_app/lib/core/system_health/system_last_error_registry.dart
    - flutter_app/lib/main.dart
    - functions/src/index.ts
---

## What system/approach is used

The codebase implements a layered, Firebase-centric error handling strategy across Flutter (mobile/web) and Cloud Functions:
- **Structured exception types** for domain-specific failures (e.g. `FirebaseBootstrapException`, `ChurchRepositoryException`, `ResilientPublishQueuedException`).
- **Retry + recovery wrappers** for transient Firestore/Network errors (`runFirestoreWithRetry`, `FirestoreWebGuard.runWithWebRecovery`, `runChatWriteWithRecovery`).
- **Web-specific guardrails** via `FirestoreWebGuard` to detect SDK internal assertions, client termination, and concurrent snapshot storms, with soft/hard session recovery without page reload.
- **Crashlytics integration** with benign-error filtering (`CrashlyticsBenignErrors`) so expected auth/session/stream races are not reported as crashes.
- **User-facing message formatting** (`formatFirebaseErrorForUser`) that translates raw Firebase exceptions into localized, actionable messages.
- **Global error hooks** in `main.dart`: `FlutterError.onError`, `PlatformDispatcher.instance.onError`, and a friendly `ErrorWidget.builder` fallback UI.
- **System-level last-error registry** (`SystemLastErrorRegistry`) for admin health dashboards.

## Key files and packages
- `flutter_app/lib/utils/firestore_retry.dart` — generic retry wrapper for transient Firestore errors with exponential backoff.
- `flutter_app/lib/utils/firestore_web_guard.dart` — comprehensive web resilience layer: concurrency limiting, assertion detection, soft/hard recovery, write-path guards.
- `flutter_app/lib/core/firebase_bootstrap_service.dart` — centralized bootstrap/reconnect logic; defines `FirebaseBootstrapException` and `FirebaseHealthReport`.
- `flutter_app/lib/services/crashlytics_benign_errors.dart` — filters out benign errors (session expired, stream already listened, quota exceeded) before reporting to Crashlytics.
- `flutter_app/lib/core/firebase_user_facing_error.dart` — user-friendly Portuguese messages from raw Firebase/Platform/State errors.
- `flutter_app/lib/core/system_health/system_last_error_registry.dart` — in-memory ring buffer of recent errors for admin panels.
- `flutter_app/lib/main.dart` — global error handlers (`FlutterError.onError`, `PlatformDispatcher.onError`, `ErrorWidget.builder`).
- `functions/src/index.ts` — Cloud Functions entry point; functions throw explicit `Error(...)` with descriptive Portuguese messages for configuration/validation failures.

## Architecture and conventions
- **Transient vs. fatal classification**: Errors are classified by code/message patterns (`unavailable`, `deadline-exceeded`, `resource-exhausted`, `aborted`, `internal`, `unknown`, `permission-denied`, `unauthorized`, `failed-precondition`, `client has already been terminated`, `INTERNAL ASSERTION`). Transient errors trigger retries; fatal ones propagate up.
- **Web-first resilience**: On web, the SDK JS 12.x `WatchChangeAggregator` internal assertions and target-id conflicts are detected and recovered via `disableNetwork`/`enableNetwork` cycles — never via `terminate()` or `location.reload()`, preserving in-flight operations.
- **Concurrent read limiting**: `_maxWebConcurrentReads = 14` with a FIFO queue and short timeout ensures panel reads never overwhelm Firestore on web.
- **Benign error suppression**: A dedicated filter recognizes session expiration, stream lifecycle races, isolate serialization issues, and `No firebase app` initialization races, preventing noise in Crashlytics.
- **User messaging discipline**: All user-visible errors go through `formatFirebaseErrorForUser`, which preserves the real cause while sanitizing stack traces and technical jargon.
- **Observability coupling**: Every non-benign error path optionally calls `CrashlyticsService.record(...)` with a `reason` tag for traceability.

## Conventions and constraints
- **Never call `terminate()` on the Firestore client** during retry paths — documented explicitly in `FirestoreWebGuard` comments to avoid `failed-precondition: client has already been terminated` cascades.
- **Retry caps are bounded**: Firestore retry defaults to 5 attempts with exponential backoff; web recovery limits to 2–3 attempts to prevent cascading timeouts.
- **Benign error list is authoritative**: `CrashlyticsBenignErrors.isBenign` is the single source of truth for what should NOT be reported as a crash; new error types must be added there if they are expected.
- **User messages must be localized and actionable**: `formatFirebaseErrorForUser` returns Portuguese strings that guide the user toward a concrete next step (retry, reconnect, re-login).
- **Cloud Functions throw typed `Error(...)` with clear Portuguese messages** for misconfiguration (e.g. missing Mercado Pago token, invalid back_url), making them visible in logs and diagnostics rather than generic 500s.