#!/usr/bin/env bash
# Grava o CFBundleVersion deste build em asc_build_number_floor.txt — próximo build evita 90189 se a API ASC atrasar.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
LAYOUT="mono"
if [ -f /tmp/cm_yw_layout ]; then
  LAYOUT="$(tr -d '\r\n' < /tmp/cm_yw_layout)"
fi
case "$LAYOUT" in
  mono) FP="$ROOT/flutter_app" ;;
  root) FP="$ROOT" ;;
  *) FP="$ROOT/flutter_app" ;;
esac

FLOOR_FILE="$FP/ios/asc_build_number_floor.txt"
mkdir -p "$(dirname "$FLOOR_FILE")"

BN=""
if [ -f /tmp/cm_ios_build_number ]; then
  BN="$(tr -d '\r\n[:space:]' < /tmp/cm_ios_build_number)"
fi

if [ -z "$BN" ] || [[ ! "$BN" =~ ^[0-9]+$ ]]; then
  echo "AVISO: /tmp/cm_ios_build_number ausente — floor não actualizado."
  exit 0
fi

CURRENT=0
if [ -f "$FLOOR_FILE" ]; then
  CURRENT="$(tr -d '\r\n[:space:]' < "$FLOOR_FILE" 2>/dev/null || echo 0)"
  case "$CURRENT" in
    ''|*[!0-9]*) CURRENT=0 ;;
  esac
fi

if [ "$BN" -gt "$CURRENT" ]; then
  printf '%s\n' "$BN" > "$FLOOR_FILE"
  echo "OK: asc_build_number_floor.txt = $BN (anterior=$CURRENT)"
else
  echo "OK: floor ($CURRENT) já >= CFBundleVersion deste build ($BN)"
fi
