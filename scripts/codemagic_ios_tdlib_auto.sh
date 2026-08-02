#!/usr/bin/env bash
# TDLib iOS automático: tenta setup do binário estático; se OK, mantém plugin;
# senão aplica fallback seguro (Yahweh Chat Firebase / Telegram embutido).
set -euo pipefail

ROOT="${1:?Informe a raiz do repo}"
FLUTTER_DIR="${2:?Informe a pasta Flutter}"

cd "$FLUTTER_DIR"

echo "=== TDLib iOS auto ==="
set +e
dart run tool/setup_tdlib.dart --ios-only
SETUP_EXIT=$?
set -e

XCFRAMEWORK=""
if [ -d ios/Frameworks/libtdjson-static.xcframework ]; then
  XCFRAMEWORK="ios/Frameworks/libtdjson-static.xcframework"
elif [ -d ios/Frameworks/libtdjson.xcframework ]; then
  XCFRAMEWORK="ios/Frameworks/libtdjson.xcframework"
fi

if [ "$SETUP_EXIT" -eq 0 ] && [ -n "$XCFRAMEWORK" ]; then
  echo "TDLib iOS: binário encontrado ($XCFRAMEWORK) — mantendo plugin nativo."
  export YAHWEH_TDLIB_IOS_ENABLED=1
  echo "1" > /tmp/cm_yw_tdlib_ios_enabled
  exit 0
fi

echo "TDLib iOS: binário/setup indisponível — fallback seguro (sem plugin nativo)."
export YAHWEH_TDLIB_IOS_ENABLED=0
echo "0" > /tmp/cm_yw_tdlib_ios_enabled
bash "$ROOT/scripts/codemagic_ios_apply_tdlib_fallback.sh" "$FLUTTER_DIR"
