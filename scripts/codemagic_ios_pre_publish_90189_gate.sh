#!/usr/bin/env bash
# Última barreira antes do upload ASC — bloqueia 90189 Redundant Binary Upload.
# NÃO adianta «Retry» só no passo Publishing: o .ipa mantém o mesmo CFBundleVersion.
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"

echo "══════════════════════════════════════════════════════════════"
echo " Gate anti-90189 — validação final antes do App Store Connect"
echo " Se falhar aqui: Start new build (workflow completo). NÃO Retry Publishing."
echo "══════════════════════════════════════════════════════════════"

bash "$ROOT/scripts/codemagic_ios_validate_ipa_before_upload.sh"

# Lê o CFBundleVersion REAL do .ipa (autoritativo) — não confia só no /tmp/cm_ios_build_number.
IPA=""
for cand in "$ROOT/flutter_app/build/ios/ipa/GestaoYahweh.ipa" "$ROOT/build/ios/ipa/GestaoYahweh.ipa" "$ROOT/GestaoYahweh.ipa"; do
  if [[ -f "$cand" ]]; then IPA="$cand"; break; fi
done
if [[ -z "$IPA" ]]; then
  IPA="$(find "$ROOT" -name "GestaoYahweh.ipa" -type f -not -path "*/.git/*" 2>/dev/null | head -n 1 || true)"
fi

BN=""
if [[ -n "$IPA" && -f "$IPA" ]]; then
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  unzip -q "$IPA" -d "$WORK" 2>/dev/null || true
  APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -n 1 || true)"
  if [[ -n "$APP" && -f "$APP/Info.plist" ]]; then
    BN="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null | tr -d '\r\n[:space:]' || true)"
  fi
fi
if [[ -z "$BN" || ! "$BN" =~ ^[0-9]+$ ]] && [[ -f /tmp/cm_ios_build_number ]]; then
  BN="$(tr -d '\r\n[:space:]' < /tmp/cm_ios_build_number)"
fi

LATEST=0
if LATEST="$(bash "$ROOT/scripts/codemagic_ios_asc_latest_build_number.sh" 2>/dev/null)"; then
  case "$LATEST" in
    ''|*[!0-9]*) LATEST=0 ;;
  esac
fi

if [[ -n "$BN" && "$LATEST" -gt 0 && "$BN" -le "$LATEST" ]]; then
  echo ""
  echo "ERRO 90189 (evitado): CFBundleVersion do .ipa ($BN) ≤ ASC ($LATEST). Abortar upload."
  echo "       Não use «Retry» só no passo Publishing — o binário é idêntico."
  echo "       Na Codemagic: Start new build (workflow completo) para gerar CFBundleVersion > $LATEST."
  exit 1
fi

if [[ -n "$BN" ]]; then
  echo "OK: pronto para Publishing (CFBundleVersion do IPA=$BN > ASC=$LATEST)."
else
  echo "AVISO: CFBundleVersion não resolvido — validação 90189 limitada ao passo anterior."
fi
