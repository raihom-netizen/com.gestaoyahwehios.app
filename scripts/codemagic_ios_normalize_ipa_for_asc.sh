#!/usr/bin/env bash
# App Store Connect / publicador Codemagic falham com .ipa cujo nome tem espaços ou "ã"
# (ex.: "Gestão Yahweh - Igrejas.ipa"). Normaliza para um único ficheiro ASCII.
#
# Uso: bash scripts/codemagic_ios_normalize_ipa_for_asc.sh
set -eu

SAFE_NAME="${CM_IOS_IPA_SAFE_NAME:-GestaoYahweh.ipa}"
ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
FPROOT="$ROOT"
if [ -f /tmp/cm_yw_layout ] && [ "$(tr -d '\r\n' < /tmp/cm_yw_layout)" = "mono" ]; then
  FPROOT="$ROOT/flutter_app"
fi

normalize_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  local src=""
  src="$(find "$dir" -maxdepth 1 -name '*.ipa' -type f 2>/dev/null | head -n 1 || true)"
  [ -n "$src" ] || return 0
  local dest="$dir/$SAFE_NAME"
  echo "=== Normalizar IPA em $dir ==="
  if [ "$(basename "$src")" = "$SAFE_NAME" ]; then
    echo "OK: ja e $SAFE_NAME"
  else
    rm -f "$dest"
    mv "$src" "$dest"
    echo "Renomeado: $(basename "$src") -> $SAFE_NAME"
  fi
  find "$dir" -maxdepth 1 -name '*.ipa' -type f ! -name "$SAFE_NAME" -delete 2>/dev/null || true
}

normalize_dir "$FPROOT/build/ios/ipa"
normalize_dir "$ROOT/build/ios/ipa"
normalize_dir "$ROOT/flutter_app/build/ios/ipa"

# Raiz do clone (publicador por vezes resolve aqui)
for f in "$ROOT"/*.ipa; do
  [ -f "$f" ] || continue
  if [ "$(basename "$f")" != "$SAFE_NAME" ]; then
    rm -f "$ROOT/$SAFE_NAME"
    mv "$f" "$ROOT/$SAFE_NAME"
    echo "Raiz: $(basename "$f") -> $SAFE_NAME"
  fi
done

PRIMARY="$FPROOT/build/ios/ipa/$SAFE_NAME"
if [ ! -f "$PRIMARY" ]; then
  PRIMARY="$(find "$ROOT" -name "$SAFE_NAME" -type f -not -path '*/.git/*' 2>/dev/null | head -n 1 || true)"
fi
if [ -z "$PRIMARY" ] || [ ! -f "$PRIMARY" ]; then
  echo "ERRO: nenhum $SAFE_NAME apos normalizacao."
  find "$ROOT" -name '*.ipa' -not -path '*/.git/*' 2>/dev/null | head -20 || true
  exit 1
fi

printf '%s\n' "$PRIMARY" > "$ROOT/.cm_yw_last_ipa_path"
[ -d "$FPROOT" ] && printf '%s\n' "$PRIMARY" > "$FPROOT/.cm_last_ipa_path"

echo "IPA ASC (ASCII): $PRIMARY"
ls -la "$FPROOT/build/ios/ipa" 2>/dev/null || true
ls -la "$ROOT/build/ios/ipa" 2>/dev/null || true
