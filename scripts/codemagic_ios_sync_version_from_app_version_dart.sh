#!/usr/bin/env bash
# Fonte única do marketing: lib/app_version.dart.
# Build number iOS em CI precisa ser único por upload (ASC erro 90189 se repetir).
# Estratégia:
#  1) CM_BUILD_NUMBER (se existir) como base;
#  2) sufixo +N do pubspec como base;
#  3) fallback 1.
# Em seguida, no Codemagic, elevamos para um número único com timestamp Unix
# (mesmo padrão usado no Controle Total para evitar "Redundant Binary Upload").
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

# Codemagic/TestFlight: garantir build number sempre único por execução.
if [ -n "${CI:-}" ] || [ -n "${CM_BUILD_ID:-}" ] || [ -n "${FCI_BUILD_ID:-}" ]; then
  TS="$(date +%s)"
  if [ "${#TS}" -gt "${#BN}" ] || { [ "${#TS}" -eq "${#BN}" ] && [ "$TS" -gt "$BN" ]; }; then
    echo "CI detectado: elevando build number para timestamp único ($TS)."
    BN="$TS"
  fi
fi

BASE_PUB="${VERSION_LINE%%+*}"
if [ -n "$BASE_PUB" ] && [ "$BUILD_NAME" != "$BASE_PUB" ]; then
  echo "AVISO: app_version.dart ($BUILD_NAME) ≠ base do pubspec ($BASE_PUB) — build usa app_version.dart + BN."
fi

printf '%s' "$BUILD_NAME" > /tmp/cm_ios_build_name
printf '%s' "$BN" > /tmp/cm_ios_build_number
echo "OK: /tmp/cm_ios_build_name=$BUILD_NAME /tmp/cm_ios_build_number=$BN"
