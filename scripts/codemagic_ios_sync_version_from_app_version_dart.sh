#!/usr/bin/env bash
# Fonte única do marketing: lib/app_version.dart.
# App Store Connect (erro 90189): CFBundleVersion tem de ser MAIOR que qualquer upload anterior.
# Em CI: último número na ASC + deslocamento BUILD_NUMBER (Codemagic) — nunca repetir em Retry de Publishing.
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

if [ -z "$BUILD_NAME" ]; then
  echo "ERRO: não leu appVersion de $VER_FILE"
  exit 1
fi

is_ci() {
  [ -n "${CI:-}" ] || [ -n "${CM_BUILD_ID:-}" ] || [ -n "${FCI_BUILD_ID:-}" ]
}

_cm_offset() {
  # BUILD_NUMBER sobe em cada execução do workflow — evita colisão se dois builds lerem o mesmo LATEST.
  local n="${BUILD_NUMBER:-${PROJECT_BUILD_NUMBER:-1}}"
  case "$n" in
    ''|*[!0-9]*) n=1 ;;
  esac
  echo "$n"
}

if is_ci; then
  OFFSET="$(_cm_offset)"
  LATEST=0
  if LATEST="$(bash "$ROOT/scripts/codemagic_ios_asc_latest_build_number.sh" 2>/dev/null)"; then
    :
  else
    LATEST=0
    echo "AVISO: consulta ASC falhou — fallback só com timestamp + offset."
  fi
  case "$LATEST" in
    ''|*[!0-9]*) LATEST=0 ;;
  esac
  FLOOR=0
  FLOOR_FILE="$FP/ios/asc_build_number_floor.txt"
  if [ -f "$FLOOR_FILE" ]; then
    FLOOR="$(tr -d '\r\n[:space:]' < "$FLOOR_FILE" 2>/dev/null || echo 0)"
    case "$FLOOR" in
      ''|*[!0-9]*) FLOOR=0 ;;
    esac
  fi
  if [ "$FLOOR" -gt "$LATEST" ]; then
    LATEST="$FLOOR"
  fi
  TS="$(date +%s)"
  # Base = maior número conhecido (ASC, floor repo, timestamp).
  BASE="$LATEST"
  if [ "$FLOOR" -gt "$BASE" ]; then
    BASE="$FLOOR"
  fi
  if [ "$TS" -gt "$BASE" ]; then
    BASE="$TS"
  fi

  # Sempre estritamente > BASE; OFFSET (= BUILD_NUMBER Codemagic) evita colisão entre builds paralelos.
  BN=$(( BASE + 1 + OFFSET ))

  # CM_BUILD_ID único por execução — barreira extra se dois builds partilharem o mesmo OFFSET.
  if [ -n "${CM_BUILD_ID:-}" ] && [[ "${CM_BUILD_ID}" =~ ^[0-9]+$ ]]; then
    TAIL=$(( CM_BUILD_ID % 500 ))
    ALT=$(( BASE + 1 + OFFSET + TAIL ))
    if [ "$ALT" -gt "$BN" ]; then
      BN="$ALT"
    fi
  fi

  if [ "$BN" -le "$BASE" ]; then
    BN=$(( BASE + 1 ))
  fi
  if [ "$BN" -le "$LATEST" ]; then
    BN=$(( LATEST + 1 + OFFSET ))
  fi
  if [ "$BN" -le "$FLOOR" ]; then
    BN=$(( FLOOR + 1 + OFFSET ))
  fi

  echo "CI: CFBundleVersion=$BN (base=$BASE ASC=$LATEST floor_repo=$FLOOR offset=$OFFSET ts=$TS)"
  echo "     CM_BUILD_ID=${CM_BUILD_ID:-?} CM_BUILD_NUMBER=${CM_BUILD_NUMBER:-?}"
  echo "     NÃO usar Retry só no passo Publishing — gera o mesmo .ipa e erro 90189."
else
  BN="${BN_PUB:-1}"
  if [ -n "${CM_BUILD_NUMBER:-}" ]; then
    BN="$CM_BUILD_NUMBER"
    echo "Local: usando CM_BUILD_NUMBER=$BN"
  fi
  if [ -z "$BN" ]; then
    BN="1"
    echo "AVISO: build number vazio — usando 1"
  fi
fi

BASE_PUB="${VERSION_LINE%%+*}"
if [ -n "$BASE_PUB" ] && [ "$BUILD_NAME" != "$BASE_PUB" ]; then
  echo "AVISO: app_version.dart ($BUILD_NAME) ≠ base do pubspec ($BASE_PUB) — IPA usa app_version.dart."
fi

sed -i.bak "s/^version: .*/version: ${BUILD_NAME}+${BN}/" "$PUB" && rm -f "$PUB.bak"
if ! grep -q "+${BN}" "$PUB"; then
  echo "ERRO: build number +${BN} não aplicado em $PUB"
  exit 1
fi

printf '%s' "$BUILD_NAME" > /tmp/cm_ios_build_name
printf '%s' "$BN" > /tmp/cm_ios_build_number
echo "OK: marketing=$BUILD_NAME CFBundleVersion=$BN"
grep "^version:" "$PUB"
