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
  TS="$(date +%s)"
  # Sempre > último enviado; offset garante unicidade entre builds simultâneos.
  BN=$(( LATEST + OFFSET ))
  if [ "$BN" -le "$LATEST" ]; then
    BN=$(( LATEST + 1 ))
  fi
  if [ "$BN" -lt "$TS" ]; then
    BN=$(( TS + OFFSET ))
  fi
  echo "CI: CFBundleVersion=$BN (ASC último=$LATEST + offset Codemagic=$OFFSET; ts mínimo=$TS)"
  echo "     CM_BUILD_ID=${CM_BUILD_ID:-?} — NÃO usar Retry só em Publishing (90189)."
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
