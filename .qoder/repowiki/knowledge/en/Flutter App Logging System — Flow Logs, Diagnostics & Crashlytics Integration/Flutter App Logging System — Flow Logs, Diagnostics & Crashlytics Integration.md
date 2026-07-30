---
kind: logging_system
name: Flutter App Logging System — Flow Logs, Diagnostics & Crashlytics Integration
category: logging_system
scope:
    - '**'
source_files:
    - flutter_app/lib/core/yahweh_flow_log.dart
    - flutter_app/lib/core/yahweh_catch_log.dart
    - flutter_app/lib/core/firebase_diagnostic_log.dart
    - flutter_app/lib/core/church_publish_flow_log.dart
    - flutter_app/lib/services/yahweh_observability.dart
    - flutter_app/lib/services/crashlytics_service.dart
    - flutter_app/lib/core/system_health/system_last_error_registry.dart
    - flutter_app/lib/debug/agent_debug_log.dart
---

## What system/approach is used

The Flutter application implements a layered, in-process logging strategy built on top of Dart's `print`/`debugPrint`, with structured flow logs, diagnostic error logging, and integration to Firebase Crashlytics for production error reporting. There is no external logging framework (e.g., `package:logging`); instead the app defines its own lightweight logger classes that centralize output format, module tagging, and crash reporting.

Cloud Functions (Node.js) use plain `console.log` / `console.error` / `console.warn` without a structured logging library.

## Key files and packages

- `flutter_app/lib/core/yahweh_flow_log.dart` — Module-scoped START/SUCCESS/ERROR/OFFLINE/ONLINE/SYNC/RETRY flow logger with named helpers per feature (DASHBOARD, MEMBROS, EVENTOS, AVISOS, CHAT, PATRIMONIO, FINANCEIRO, AGENDA, UPLOAD, etc.).
- `flutter_app/lib/core/yahweh_catch_log.dart` — Mandatory `catch(e,s)` helper that prints tag + exception + stack, records into `SystemLastErrorRegistry`, and reports to Crashlytics.
- `flutter_app/lib/core/firebase_diagnostic_log.dart` — Diagnostic logger for Firebase-specific errors (`logFirebaseDiagnostic`, `logChatFirestoreAccess`, `logFirebasePublishPhase`) that conditionally forwards to Crashlytics.
- `flutter_app/lib/core/church_publish_flow_log.dart` — Publication-phase logger for avisos/eventos/chat/media uploads with explicit phase markers (START → FIRESTORE OK → UPLOAD OK → SUCCESS).
- `flutter_app/lib/services/yahweh_observability.dart` — Observability facade wrapping AnalyticsService, PerformanceService, and Crashlytics; exposes `traceAsync` and typed trace helpers per module.
- `flutter_app/lib/services/crashlytics_service.dart` — Crashlytics wrapper with benign-error filtering and platform gating (disabled on web).
- `flutter_app/lib/core/system_health/system_last_error_registry.dart` — In-memory ring buffer of recent errors exposed to an admin health UI.
- `flutter_app/lib/debug/agent_debug_log.dart` — NDJSON debug session logger for web agent diagnostics.
- Cloud Functions: all `.js` files under `functions/` and `functions/lib/` use `console.log` / `console.error` / `console.warn` directly.

## Architecture and conventions

1. **Flow-level structured logs** — Every major operation goes through `YahwehFlowLog.start()` / `success()` / `error()`, producing lines like `MODULE START`, `MODULE SUCCESS`, `MODULE ERROR`. A `trace(module, fn)` wrapper automatically emits start/success/error and delegates timing to `YahwehObservability.traceAsync` (Firebase Performance). Named helpers exist for each domain (e.g. `dashboardStart`, `chatMessageCreated`, `financeiroUploadOk`).

2. **Mandatory catch pattern** — `YahwehCatchLog.log(e, s, tag:)` is the prescribed way to handle exceptions: it prints `ERROR <tag>`, the exception, and the full stack; records into `SystemLastErrorRegistry`; and asynchronously reports to Crashlytics via `CrashlyticsService.record`. The comment marks this as "padrão obrigatório produção premium".

3. **Firebase diagnostics** — `firebase_diagnostic_log.dart` provides three focused helpers:
   - `logFirebaseDiagnostic(error, stack?, context?)` — prints in debug mode and forwards to Crashlytics when `shouldReport` passes.
   - `logChatFirestoreAccess({path, churchId, error?})` — emits path/churchId/uid/error for permission-denied or read failures.
   - `logFirebasePublishPhase(phase, context, error?, stack?)` — wraps publish-phase logging with optional Crashlytics forwarding.

4. **Publish-phase logging** — `ChurchPublishFlowLog` enforces a consistent sequence for publishing operations (aviso, evento, chat, member photo): `*Start` → `*FirestoreOk` → `*UploadOk` → `*FinalOk` / `*Error`, plus `uploadTiming`, `offlineMode`, `onlineMode`, `retryAttempt`, and `phase(label)` markers.

5. **Observability facade** — `YahwehObservability.ensureInitialized()` initializes PublicSiteAnalytics, AnalyticsService, and PerformanceService. Typed trace helpers (`traceDashboard`, `traceChat`, `traceAvisos`, `traceEventos`, `tracePatrimonio`, `traceFinanceiro`, `traceUpload`, `traceSyncFlush`, `traceLogin`) wrap async work with Firebase Performance metrics. Error recording helpers (`recordFirestoreError`, `recordStorageError`, `recordUploadError`) funnel into Crashlytics.

6. **In-memory error registry** — `SystemLastErrorRegistry` keeps up to 12 recent errors (module, message, context, timestamp, stackTrace) for an admin health panel, printing in debug mode.

7. **Platform-aware output** — All print statements are mirrored to `debugPrint` when `kDebugMode` is true. Crashlytics is disabled on web and only active on Android/iOS.

8. **Cloud Functions logging** — Node.js functions rely on unstructured `console.log` / `console.error` / `console.warn` calls scattered throughout business logic files. No centralized logger or log level configuration exists in the server side.

## Conventions and constraints

- **Every catch must go through `YahwehCatchLog`** — documented as an enforced production standard in `yahweh_catch_log.dart`.
- **Flow boundaries must be logged** — modules should call `start()` before work and `success()`/`error()` after, using either the generic API or the named helpers.
- **Publish flows must follow the phase sequence** — `ChurchPublishFlowLog` enforces START → Firestore OK → Upload OK → Final OK/Error for aviso/evento/chat/photo operations.
- **Firebase errors must use diagnostic helpers** — `logFirebaseDiagnostic`, `logChatFirestoreAccess`, `logFirebasePublishPhase` are the prescribed entry points for Firebase-related errors.
- **Crashlytics filtering** — `CrashlyticsService.shouldReport` filters out benign errors (e.g., expired sessions, duplicate streams, recoverable bootstrap failures); fatal crashes bypass benign filtering.
- **No global log level** — there is no centralized log level switch; output is controlled by `kDebugMode` for `debugPrint` mirroring and by whether Crashlytics is enabled per platform.
- **Cloud Functions have no structured logging** — `console.*` calls are ad-hoc and not routed through a common formatter or sink.