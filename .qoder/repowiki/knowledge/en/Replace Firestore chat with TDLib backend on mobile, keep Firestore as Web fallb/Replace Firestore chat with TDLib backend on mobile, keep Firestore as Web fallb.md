---
kind: design
name: Replace Firestore chat with TDLib backend on mobile, keep Firestore as Web fallback
source: session
category: adr
---

# Replace Firestore chat with TDLib backend on mobile, keep Firestore as Web fallback

_Source: coding plans from commit period fd55706 → 45f1c25 — records intent at planning time; the implementation may lag or differ._

**Status:** accepted

## Context
The existing Firestore-based chat engine was slow and lacked real-time features; the app needed a faster messaging backend while preserving the existing Yahweh UI layer.

## Decision drivers
- real-time messaging performance
- native Telegram integration via TDLib
- Web platform FFI limitations
- UI reuse without rewriting screens

## Considered options
- **TDLib backend on mobile + Firestore fallback on Web** — pros: Leverages existing TDLib integration for fast native messaging; keeps UI unchanged via adapter layer; Web falls back to Firestore since TDLib FFI is unavailable
- **Keep Firestore-only chat across all platforms** _(rejected)_ — pros: Simpler codebase, no new dependency; cons: Slower real-time sync, no native Telegram features, no group management parity
- **Embed Telegram Web Client on all platforms** _(rejected)_ — pros: Single code path, full Telegram feature set; cons: Requires WebView/FFI workarounds on mobile, loses native UX feel

## Decision
Implement `tdlib_chat_adapter.dart` mapping TDLib types to existing `ChatThread`/`ChatMessage` models, route all read/write through it when authenticated, and fall back to Firestore on Web where TDLib FFI is unavailable. Departments map to Telegram groups created automatically.

## Consequences
Mobile users get near-instant Telegram-native messaging with typing indicators and read receipts. Web users stay on Firestore or can be redirected to Telegram Web. Existing Firestore chat data is not migrated — fresh start. The adapter layer isolates backend changes from the UI.