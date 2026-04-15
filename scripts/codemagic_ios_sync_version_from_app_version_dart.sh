#!/usr/bin/env bash
# Fonte única do marketing: lib/app_version.dart; build number do pubspec (+ CM_BUILD_NUMBER se definido).
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
cd "$ROOT"
case "$(cat /tmp/cm_yw_layout)" in
  mono) FP="$ROOT/flutter_app" ;;
  root) FP="$ROOT" ;;
  *) echo "ERRO: /tmp/cm_yw_layout"; exit 1 ;;
esac

VER_FILE="$FP/lib/app_version.dart"
PUB="$FP/pubspec.yaml"
BUILD_NAME="$(grep "const String appVersion" "$VER_FILE" | head -1 | sed "s/.*appVersion = '//;s/'.*//")"
VERSION_LINE="$(grep '^version:' "$PUB" | head -1 | sed 's/^version:[[:space:]]*//;s/[[:space:]]*$//')"
BN_PUB="${VERSION_LINE##*+}"
BN="${BN_PUB}"
if [ -n "${CM_BUILD_NUMBER:-}" ]; then
  BN="$CM_BUILD_NUMBER"
  echo "Usando CM_BUILD_NUMBER=$BN (sobrescreve sufixo + do pubspec)."
fi
if [ -z "$BUILD_NAME" ]; then
  echo "ERRO: não leu appVersion de $VER_FILE"
  exit 1
fi
if [ -z "$BN" ]; then
  BN="1"
  echo "AVISO: build number vazio — usando 1"
fi

BASE_PUB="${VERSION_LINE%%+*}"
if [ -n "$BASE_PUB" ] && [ "$BUILD_NAME" != "$BASE_PUB" ]; then
  echo "AVISO: app_version.dart ($BUILD_NAME) ≠ base do pubspec ($BASE_PUB) — build usa app_version.dart + BN."
fi

printf '%s' "$BUILD_NAME" > /tmp/cm_ios_build_name
printf '%s' "$BN" > /tmp/cm_ios_build_number
echo "OK: /tmp/cm_ios_build_name=$BUILD_NAME /tmp/cm_ios_build_number=$BN"
