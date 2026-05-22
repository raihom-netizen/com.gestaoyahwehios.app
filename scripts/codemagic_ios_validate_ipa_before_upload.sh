#!/usr/bin/env bash
# Valida o .ipa antes do upload TestFlight — evita «Binário inválido» no App Store Connect.
# Uso: bash scripts/codemagic_ios_validate_ipa_before_upload.sh [caminho.ipa]
set -euo pipefail

ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
IPA="${1:-}"

if [[ -z "$IPA" ]]; then
  for cand in "$ROOT/build/ios/ipa/"*.ipa "$ROOT/flutter_app/build/ios/ipa/"*.ipa; do
    if [[ -f "$cand" ]]; then
      IPA="$cand"
      break
    fi
  done
fi

if [[ -z "$IPA" ]] || [[ ! -f "$IPA" ]]; then
  IPA="$(find "$ROOT" -name "*.ipa" -type f -not -path "*/.git/*" 2>/dev/null | head -n 1 || true)"
fi

if [[ -z "$IPA" ]] || [[ ! -f "$IPA" ]]; then
  echo "ERRO: nenhum .ipa para validar."
  exit 1
fi

echo "=== Validar IPA antes do upload ASC ==="
echo "IPA: $IPA"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -type d | head -n 1)"
if [[ -z "$APP" ]] || [[ ! -d "$APP" ]]; then
  echo "ERRO: Payload/*.app ausente no IPA."
  exit 1
fi

PLIST="$APP/Info.plist"
if [[ ! -f "$PLIST" ]]; then
  echo "ERRO: Info.plist ausente em $APP"
  exit 1
fi

# UIBackgroundModes: remote-notification exige aps-environment no entitlement assinado.
if /usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$PLIST" 2>/dev/null | grep -q remote-notification; then
  ENT="$(mktemp)"
  codesign -d --entitlements :- "$APP" 2>/dev/null >"$ENT" || true
  if ! grep -q 'aps-environment' "$ENT" 2>/dev/null; then
    echo ""
    echo "ERRO: Info.plist declara UIBackgroundModes remote-notification mas o binário"
    echo "       assinado NÃO tem aps-environment (Runner.entitlements / perfil)."
    echo "       A Apple rejeita como «Binário inválido» no TestFlight."
    echo "       Corrija: remova remote-notification do Info.plist OU regenere o perfil com Push."
    echo ""
    exit 1
  fi
  echo "OK: remote-notification + aps-environment presentes."
else
  echo "OK: Info.plist sem remote-notification (coerente com push desactivado)."
fi

# LSApplicationQueriesSchemes: http/https são proibidos (ITMS-90048).
if /usr/libexec/PlistBuddy -c "Print :LSApplicationQueriesSchemes" "$PLIST" &>/dev/null; then
  _idx=0
  while true; do
    _scheme="$(/usr/libexec/PlistBuddy -c "Print :LSApplicationQueriesSchemes:${_idx}" "$PLIST" 2>/dev/null)" || break
    case "$_scheme" in
      http|https)
        echo ""
        echo "ERRO: LSApplicationQueriesSchemes não pode incluir http nem https (ITMS-90048)."
        echo "       Encontrado: $_scheme"
        exit 1
        ;;
    esac
    _idx=$((_idx + 1))
  done
fi
echo "OK: LSApplicationQueriesSchemes sem http/https."

# Sign In with Apple: entitlement no binário vs pedido no repo.
ENT_FILE="$(mktemp)"
codesign -d --entitlements :- "$APP" 2>/dev/null >"$ENT_FILE" || true
REPO_ENT=""
for p in "$ROOT/flutter_app/ios/Runner/Runner.entitlements" "$ROOT/ios/Runner/Runner.entitlements"; do
  if [[ -f "$p" ]]; then
    REPO_ENT="$p"
    break
  fi
done
if [[ -n "$REPO_ENT" ]] && grep -q 'com.apple.developer.applesignin' "$REPO_ENT" 2>/dev/null; then
  if ! grep -q 'com.apple.developer.applesignin' "$ENT_FILE" 2>/dev/null; then
    echo ""
    echo "ERRO: Runner.entitlements pede Sign In with Apple mas o IPA assinado não inclui"
    echo "       com.apple.developer.applesignin — regenere CM_PROVISIONING_PROFILE."
    exit 1
  fi
  echo "OK: Sign In with Apple no IPA."
fi

echo "=== Validação IPA concluída — seguro para upload TestFlight ==="
