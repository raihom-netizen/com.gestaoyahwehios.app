---
kind: external_dependency
name: Telegram TDLib (Optional Chat Engine Backend)
slug: telegram-tdlib
category: external_dependency
category_hints:
    - sdk_real_api
    - framework_behavior
scope:
    - '**'
---

### Telegram TDLib Integration
- **Purpose**: Optional backend engine for chat functionality, providing native Telegram messaging capabilities
- **Architecture**: Pluggable chat engine with Firestore as primary and TDLib as fallback/alternative
- **Isolation**: Each church has separate TDLib sessions in `tdlib/{churchId}/db` and `tdlib/{churchId}/files`
- **Features**: Full messaging API (send, reply, edit, delete, forward), media support, group management, read receipts
- **Build Status**: Disabled in production pubspec due to iOS binary issues (`flutter_libtdjson / libtdjson.a` missing)
- **Activation**: Requires manual setup via `dart run tool/setup_tdlib.dart --ios-only` in CI pipeline
- **Fallback**: Automatically falls back to Firestore-based chat when TDLib unavailable
- **Web Support**: Falls back to Telegram Web embed via `telegram_web_embed.dart`