#!/usr/bin/env bash
# TDLib iOS automático.
# Por defeito no CI: fallback seguro (Yahweh Chat Firebase).
# Opt-in nativo: YAHWEH_TDLIB_IOS_TRY_NATIVE=1 e binário libtdjson.a válido.
set -euo pipefail

ROOT="${1:?Informe a raiz do repo}"
FLUTTER_DIR="${2:?Informe a pasta Flutter}"

cd "$FLUTTER_DIR"

echo "=== TDLib iOS auto ==="
chmod +x "$ROOT/scripts/codemagic_ios_apply_tdlib_fallback.sh" || true

TRY_NATIVE="${YAHWEH_TDLIB_IOS_TRY_NATIVE:-0}"

find_tdlib_binary() {
  local fw bin
  for fw in \
    ios/Frameworks/libtdjson-static.xcframework \
    ios/Frameworks/libtdjson.xcframework
  do
    if [ -d "$fw" ]; then
      bin="$(find "$fw" \( -name 'libtdjson.a' -o -name 'libtdjson' \) 2>/dev/null | head -n 1 || true)"
      if [ -n "$bin" ]; then
        echo "$bin"
        return 0
      fi
    fi
  done
  return 1
}

if [ "$TRY_NATIVE" = "1" ]; then
  echo "YAHWEH_TDLIB_IOS_TRY_NATIVE=1 — tentando setup do binário estático…"
  set +e
  dart run tool/setup_tdlib.dart --ios-only
  SETUP_EXIT=$?
  set -e
  BIN="$(find_tdlib_binary || true)"
  if [ "$SETUP_EXIT" -eq 0 ] && [ -n "${BIN:-}" ]; then
    echo "TDLib iOS: binário OK ($BIN) — mantendo plugin nativo."
    export YAHWEH_TDLIB_IOS_ENABLED=1
    echo "1" > /tmp/cm_yw_tdlib_ios_enabled
    exit 0
  fi
  echo "TDLib iOS: try-native falhou (setup_exit=${SETUP_EXIT:-?}, bin=${BIN:-ausente})."
fi

echo "TDLib iOS: fallback seguro (sem plugin nativo / sem flutter_libtdjson)."
export YAHWEH_TDLIB_IOS_ENABLED=0
export YAHWEH_TDLIB_FORCE_FALLBACK=1
echo "0" > /tmp/cm_yw_tdlib_ios_enabled
bash "$ROOT/scripts/codemagic_ios_apply_tdlib_fallback.sh" "$FLUTTER_DIR" --force
