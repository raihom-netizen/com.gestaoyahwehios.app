#!/usr/bin/env bash
# Último CFBundleVersion conhecido já enviado à App Store Connect (evita 90189).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
FLOOR_FILE=""
for cand in "$ROOT/flutter_app/ios/asc_build_number_floor.txt" "$ROOT/ios/asc_build_number_floor.txt"; do
  if [[ -f "$cand" ]]; then
    FLOOR_FILE="$cand"
    break
  fi
done
if [[ -z "$FLOOR_FILE" || ! -f "$FLOOR_FILE" ]]; then
  echo 0
  exit 0
fi
FLOOR="$(tr -d '\r\n[:space:]' < "$FLOOR_FILE")"
case "$FLOOR" in
  ''|*[!0-9]*) echo 0 ;;
  *) echo "$FLOOR" ;;
esac
