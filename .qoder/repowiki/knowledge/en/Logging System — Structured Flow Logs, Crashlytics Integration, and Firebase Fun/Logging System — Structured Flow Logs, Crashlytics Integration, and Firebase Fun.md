---
kind: logging_system
name: Logging System — Structured Flow Logs, Crashlytics Integration, and Firebase Functions Logging
category: logging_system
scope:
    - '**'
source_files:
    - flutter_app/lib/core/yahweh_flow_log.dart
    - flutter_app/lib/core/church_publish_flow_log.dart
    - flutter_app/lib/core/firebase_diagnostic_log.dart
    - flutter_app/lib/core/yahweh_catch_log.dart
    - flutter_app/lib/core/system_health/system_last_error_registry.dart
    - flutter_app/lib/services/crashlytics_service.dart
    - flutter_app/lib/services/yahweh_observability.dart
    - functions/src/index.ts
---

## What system/approach is used

The project implements a layered logging strategy across three tiers:

1. **Flutter client-side flow logging** — dedicated static logger classes (`YahwehFlowLog`, `ChurchPublishFlowLog`) that emit structured console output with module names and phases (START/SUCCESS/ERROR/OFFLINE/ONLINE/SYNC/RETRY).
2. **Error aggregation and crash reporting** — `YahwehCatchLog` centralizes exception capture, writing to stdout, debug print, an in-memory `SystemLastErrorRegistry`, and asynchronously reporting to Firebase Crashlytics via `CrashlyticsService`.
3. **Firebase Functions server-side logging** — uses the standard `functions.logger` API (info/warn/error) for structured JSON logs, with occasional `console.log`/`console.warn` in legacy or utility scripts.

There is no centralized log-level configuration framework; instead, each logger class encapsulates its own output behavior and integrates with platform-specific sinks (stdout, debugPrint, Crashlytics, functions.logger).

## Key files and packages

- `flutter_app/lib/core/yahweh_flow_log.dart` — primary flow logger with named modules (DASHBOARD, MEMBROS, EVENTOS, AVISOS, CHAT, PATRIMONIO, FINANCEIRO, AGENDA, CARTAO, CARTA, RELATORIO, UPLOAD)
- `flutter_app/lib/core/church_publish_flow_log.dart` — publish-phase specific logger for avisos/eventos/chat uploads
- `flutter_app/lib/core/firebase_diagnostic_log.dart` — Firebase diagnostic error logging with Crashlytics integration
- `flutter_app/lib/core/yahweh_catch_log.dart` — mandatory catch pattern for production premium apps
- `flutter_app/lib/core/system_health/system_last_error_registry.dart` — in-memory registry of last N errors (max 12 entries)
- `flutter_app/lib/services/crashlytics_service.dart` — Crashlytics wrapper with benign-error filtering
- `flutter_app/lib/services/yahweh_observability.dart` — observability facade wrapping Analytics, Performance, and Crashlytics
- `functions/src/index.ts` — main Cloud Functions entry using `functions.logger` for structured logging
- Legacy JS functions under `functions/lib/*.js` use `console.log`/`console.error` directly

## Architecture and conventions

### Client-side (Flutter)
- **Module-scoped logging**: Each major feature has dedicated start/success/error methods (e.g., `membrosStart()`, `membrosSuccess()`).
- **Phase-based flow tracking**: Publish flows follow a strict sequence: START → FIRESTORE OK → UPLOAD OK → SUCCESS/ERROR.
- **Structured output format**: Messages follow patterns like `MODULE PHASE` or `MODULE SYNC detail`, enabling grep-friendly parsing.
- **Debug vs production**: Uses `kDebugMode` to gate verbose `debugPrint` calls while always emitting `print()` for production console output.
- **Performance tracing**: `YahwehFlowLog.trace()` wraps async operations with automatic START/SUCCESS/ERROR emission and delegates timing to `YahwehObservability.traceAsync()`.

### Error handling convention
- The `YahwehCatchLog` class enforces a mandatory `catch (e, s) { YahwehCatchLog.log(e, s); }` pattern for all production code paths.
- Errors are recorded in three places simultaneously: stdout, debug console, in-memory registry, and Crashlytics (filtered by `CrashlyticsService.shouldReport()`).
- Benign errors are filtered out via `CrashlyticsBenignErrors.isBenign()` to prevent noise.

### Server-side (Firebase Functions)
- **Structured JSON logging**: All new TypeScript functions use `functions.logger.info/warn/error` with contextual objects as second parameters.
- **Legacy compatibility**: Older JavaScript functions still use `console.log`/`console.error` but are being migrated.
- **Contextual information**: Log messages include tenant IDs, operation names, and error details in structured format.

## Conventions and constraints

### Enforced patterns
- **Mandatory catch logging**: The comment in `yahweh_catch_log.dart` states this is an "obrigatório padrão produção premium" (mandatory production premium standard).
- **No generic masked messages**: `firebase_diagnostic_log.dart` explicitly requires logging real exceptions, never generic masked messages.
- **Crashlytics filtering**: Only non-benign errors are reported to Crashlytics to avoid session expiration and duplicate streams.

### Output conventions
- **Console output**: Always includes module name prefix and phase indicator (START/SUCCESS/ERROR/OFFLINE/ONLINE).
- **Timing logs**: Upload operations include detailed timing breakdowns (upload ms, firestore ms, total ms).
- **Retry tracking**: Retry attempts are logged with attempt numbers for operational visibility.
- **Offline mode detection**: Explicit OFFLINE/ONLINE phase logging for connectivity state changes.

### Platform-specific behavior
- **Web exclusion**: Crashlytics reporting is disabled on web (`!kIsWeb`) to avoid unnecessary overhead.
- **Platform targeting**: Crashlytics only enabled for Android and iOS platforms.
- **Debug gating**: Verbose stack traces and detailed diagnostics are gated behind `kDebugMode`.

### Migration status
- TypeScript functions under `functions/src/` use modern `functions.logger` API.
- Legacy JavaScript functions under `functions/lib/` still use `console.*` methods but are being gradually migrated.