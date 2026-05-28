#!/usr/bin/env bash
# Fonte única do marketing: lib/app_version.dart.
# App Store Connect (erro 90189): cada upload iOS precisa de CFBundleVersion NOVO.
# Em CI: SEMPRE timestamp Unix (+ desempate CM_BUILD_ID) — NUNCA CM_BUILD_NUMBER nem +pubspec.
# Padrão alinhado ao Controle Total (pubspec version: X.Y.Z+UNIQUE antes do flutter build ipa).
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

if is_ci; then
  BN="$(date +%s)"
  if [ -n "${CM_BUILD_ID:-}" ]; then
    # Evita colisão se dois builds dispararem no mesmo segundo.
    BN=$(( BN + (CM_BUILD_ID % 1000) ))
  fi
  echo "CI: CFBundleVersion único = $BN"
  echo "     (ignora CM_BUILD_NUMBER=${CM_BUILD_NUMBER:-<vazio>} e pubspec +${BN_PUB:-?} — evita 90189)"
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

# Grava no pubspec para flutter build ipa (com ou sem --build-number) usar o mesmo +N.
sed -i.bak "s/^version: .*/version: ${BUILD_NAME}+${BN}/" "$PUB" && rm -f "$PUB.bak"
if ! grep -q "+${BN}" "$PUB"; then
  echo "ERRO: build number +${BN} não aplicado em $PUB"
  exit 1
fi

printf '%s' "$BUILD_NAME" > /tmp/cm_ios_build_name
printf '%s' "$BN" > /tmp/cm_ios_build_number
echo "OK: marketing=$BUILD_NAME CFBundleVersion=$BN"
grep "^version:" "$PUB"
