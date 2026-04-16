#!/usr/bin/env bash
# Certificados/perfis já injetados pela Codemagic (codemagic.yaml «ios_signing» + equipa).
# Gera /tmp/ExportOptions.plist a partir do .mobileprovision presente em Provisioning Profiles.
# Pré-requisitos: keychain initialize + /tmp/_asc_ok.pem
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f /tmp/_asc_ok.pem ]; then
  echo "ERRO: /tmp/_asc_ok.pem ausente — execute antes: Preparar PEM App Store Connect."
  exit 1
fi

_persist_asc_pem_to_cm_env() {
  [ -n "${CM_ENV:-}" ] && [ -f /tmp/_asc_ok.pem ] || return 0
  _ASC_DELIM="CMGYYWHASCPEM594E2F1END"
  {
    echo "APP_STORE_CONNECT_PRIVATE_KEY<<${_ASC_DELIM}"
    cat /tmp/_asc_ok.pem
    printf '\n%s\n' "${_ASC_DELIM}"
  } >> "$CM_ENV"
}

BUNDLE="${IOS_BUNDLE_ID:-com.gestaoyahwehios.app}"
PROFILES_HOME="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES_HOME"

echo "=== team_signing: procurar perfil App Store para bundle $BUNDLE ==="
ls -la "$PROFILES_HOME" 2>/dev/null || true

found=""
for f in "$PROFILES_HOME"/*.mobileprovision; do
  [ -f "$f" ] || continue
  if security cms -D -i "$f" 2>/dev/null | grep -qF "$BUNDLE"; then
    found="$f"
    echo "OK: perfil candidato: $(basename "$f")"
    break
  fi
done

if [ -z "${found}" ]; then
  echo ""
  echo "ERRO: nenhum .mobileprovision para «${BUNDLE}» em:"
  echo "  $PROFILES_HOME"
  echo "  1) codemagic.yaml deve ter environment.ios_signing (distribution_type + bundle_identifier ou referencias)."
  echo "  2) Na equipa Codemagic: Code signing identities — o perfil deve mostrar certificado associado (verde),"
  echo "     nao «Not uploaded». Carregue o .p12 «gestaoyahweh_dist» ou refaça Fetch profiles."
  exit 1
fi

cp "$found" /tmp/cm_raw.mobileprovision
security cms -D -i /tmp/cm_raw.mobileprovision > /tmp/cm_prov.plist
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' /tmp/cm_prov.plist)
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' /tmp/cm_prov.plist)
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print TeamIdentifier:0' /tmp/cm_prov.plist)

export CM_EXPORT_PROFILE_NAME="$PROFILE_NAME"
export CM_EXPORT_TEAM_ID="$TEAM_ID"
python3 << 'PY'
import os, plistlib
team = os.environ["CM_EXPORT_TEAM_ID"]
name = os.environ["CM_EXPORT_PROFILE_NAME"]
data = {
    "method": "app-store",
    "signingStyle": "manual",
    "teamID": team,
    "uploadSymbols": True,
    "provisioningProfiles": {"com.gestaoyahwehios.app": name},
}
with open("/tmp/ExportOptions.plist", "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML)
PY

echo "Perfil: name=${PROFILE_NAME} uuid=${PROFILE_UUID} team=${TEAM_ID}"
_persist_asc_pem_to_cm_env
echo "OK: team_signing — ExportOptions.plist a partir do perfil Codemagic."
