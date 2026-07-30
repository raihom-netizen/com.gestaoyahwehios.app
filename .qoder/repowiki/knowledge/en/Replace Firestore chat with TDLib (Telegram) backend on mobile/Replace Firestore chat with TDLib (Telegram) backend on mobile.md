---
kind: design
name: Replace Firestore chat with TDLib (Telegram) backend on mobile
source: session
category: adr
---

# Replace Firestore chat with TDLib (Telegram) backend on mobile

_Source: coding plans from commit period 45f1c25 → 7ad4946 — records intent at planning time; the implementation may lag or differ._

**Status:** accepted

## Context
The existing Firestore-based chat engine was slow and lacked native Telegram features. The app needed real-time messaging, media handling, group management, and typing indicators that would be difficult to replicate over Firestore.

## Decision drivers
- native Telegram performance
- real-time streaming via TDLib
- group chat support
- media upload/download speed

## Considered options
- **TDLib (Telegram) backend on mobile + Firestore fallback on web** — pros: Native Telegram performance, built-in groups/media/typing, faster uploads; web falls back to Firestore without breaking functionality
- **Keep Firestore-only chat** _(rejected)_ — pros: Simpler deployment, no native dependencies; cons: Slower real-time sync, no native Telegram features, poor media handling, no group management
- **Embed Telegram Web Client for all platforms** _(rejected)_ — pros: No native code needed; cons: Poor UX compared to native app, cannot integrate deep links or push notifications into the app flow

## Decision
Adopt TDLib as the primary chat backend on Android/iOS via `libtdjson: 0.3.0`, with a new `tdlib_chat_adapter.dart` mapping TDLib types to existing `ChatThread`/`ChatMessage` models. Web falls back to Firestore or embedded Telegram Web Client. Departments map to Telegram groups created automatically.

## Consequences
Mobile apps gain native Telegram performance and features. Web users get a degraded experience (Firestore or web embed). Existing Firestore chat data is not migrated — fresh start. CI must generate TDLib binaries (`tool/setup_tdlib.dart`) during build. Deep links and push notifications are wired through FCM regardless of backend.