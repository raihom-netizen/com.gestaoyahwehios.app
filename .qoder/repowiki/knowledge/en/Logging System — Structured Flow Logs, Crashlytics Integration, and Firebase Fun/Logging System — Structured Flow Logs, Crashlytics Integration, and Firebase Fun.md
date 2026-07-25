---
kind: logging_system
name: Logging System — Structured Flow Logs, Crashlytics Integration, and Firebase Functions Logging
category: logging_system
scope:
    - '**'
source_files:
    - flutter_app/lib/core/yahweh_flow_log.dart
    - flutter_app/lib/core/yahweh_catch_log.dart
    - flutter_app/lib/core/church_publish_flow_log.dart
    - flutter_app/lib/core/firebase_diagnostic_log.dart
    - flutter_app/lib/services/yahweh_observability.dart
    - flutter_app/lib/debug/agent_debug_log.dart
    - functions/src/index.ts
---

The Gestão YAHWEH monorepo implements a layered logging strategy across its Flutter client and Firebase Cloud Functions backend, combining structured flow logs, crash reporting, performance tracing, and platform-native log sinks.

**Client-side (Flutter) logging layers**
- `YahwehFlowLog` (`flutter_app/lib/core/yahweh_flow_log.dart`) provides module-scoped START/SUCCESS/ERROR/RETRY/OFFLINE/ONLINE markers for major features (DASHBOARD, MEMBROS, EVENTOS, AVISOS, CHAT, PATRIMONIO, FINANCEIRO, AGENDA). Output goes to both `print()` and `debugPrint()` in debug mode, and errors are forwarded to `YahwehCatchLog`.
- `YahwehCatchLog` (`flutter_app/lib/core/yahweh_catch_log.dart`) is the mandatory production catch pattern: it prints the error and stack trace, records it via `SystemLastErrorRegistry`, and asynchronously reports to `CrashlyticsService`. It enforces a consistent `catch (e, s) { YahwehCatchLog.log(e, s); rethrow }` convention.
- `ChurchPublishFlowLog` (`flutter_app/lib/core/church_publish_flow_log.dart`) standardizes publish-phase logs for avisos/eventos/chat with explicit phases (START → FIRESTORE OK → UPLOAD OK → SUCCESS) plus timing, progress, retry, and offline/online mode markers.
- `FirebaseDiagnosticLog` (`flutter_app/lib/core/firebase_diagnostic_log.dart`) handles Firebase-specific diagnostics: raw exception logging (never masked messages), Firestore path/UID context for permission-denied errors, and publish-phase error forwarding to Crashlytics.
- `AgentDebugLog` (`flutter_app/lib/debug/agent_debug_log.dart`) emits NDJSON debug sessions over HTTP to a local ingest endpoint on web builds, tagged by sessionId/runId/hypothesisId/timestamp.
- `YahwehObservability` (`flutter_app/lib/services/yahweh_observability.dart`) is the observability facade that wires together AnalyticsService, PerformanceService (Firebase Performance traces per module), and CrashlyticsService. All trace calls go through `traceAsync` which wraps start/success/error flow logging around the operation.

**Server-side (Cloud Functions) logging**
- The TypeScript functions use `functions.logger` from `firebase-functions/v1` consistently with levels `.info()`, `.warn()`, and `.error()`, passing structured objects as second arguments (e.g., `{ tenantId, threadId, e }`). This produces JSON-structured logs in Google Cloud Logging.
- Legacy JS files in `functions/` still use `console.log`/`console.error`/`console.warn`, but new code follows the `functions.logger` convention.
- Error paths typically wrap operations in try/catch blocks that log the error via `functions.logger.error(...)` and then throw an `HttpsError` with a user-facing message.

**Sinks and destinations**
- Console output: `print()` + `debugPrint()` on the client; `functions.logger.*` on the server.
- Crash reporting: `CrashlyticsService.record(...)` is called for all significant errors, with optional `reason` tags like `firestore_error`, `storage_error`, `upload_error`, or module names.
- Performance metrics: Firebase Performance traces named per module (e.g., `flow_dashboard`, `flow_chat`, `flow_upload`) via `YahwehObservability.traceAsync`.
- System health registry: `SystemLastErrorRegistry.record(...)` keeps the last error per module for UI display.
- Debug ingestion: Web debug logs POST NDJSON to a local HTTP endpoint for live session replay.

**Conventions observed**
- Every async operation wrapped in `YahwehFlowLog.trace(module, fn)` emits START before and SUCCESS/ERROR after completion.
- Publish flows follow a fixed phase sequence: START → FIRESTORE_OK → UPLOAD_OK → SUCCESS, with dedicated error methods.
- Errors always include the original exception and stack trace; no generic masked messages are logged.
- Server-side logs attach contextual fields (tenantId, threadId, churchId, uid) as structured objects rather than string interpolation.