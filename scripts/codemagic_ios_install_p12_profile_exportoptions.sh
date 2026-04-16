#!/usr/bin/env bash
# Instala P12 no keychain, copia .mobileprovision, gera /tmp/ExportOptions.plist e persiste PEM no CM_ENV.
# Pré-requisitos: keychain initialize + /tmp/_asc_ok.pem (passos anteriores).
set -eu

if [ -z "${CM_CERTIFICATE:-}" ] && [ -n "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  export CM_CERTIFICATE="$CERTIFICATE_PRIVATE_KEY"
  echo "AVISO: CM_CERTIFICATE vazio — a usar CERTIFICATE_PRIVATE_KEY."
fi

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

_CM_PROV_COMPACT="$(printf '%s' "${CM_PROVISIONING_PROFILE}" | tr -d '\n\r\t ')"
if [ -z "${_CM_PROV_COMPACT}" ]; then
  echo "ERRO: CM_PROVISIONING_PROFILE vazio apos normalizar."
  exit 1
fi
if ! printf '%s' "${_CM_PROV_COMPACT}" | base64 -D > /tmp/cm_raw.mobileprovision 2>/tmp/_prov_b64.err; then
  echo "ERRO: CM_PROVISIONING_PROFILE nao decodifica em Base64 valido."
  cat /tmp/_prov_b64.err 2>/dev/null || true
  exit 1
fi
if [ ! -s /tmp/cm_raw.mobileprovision ]; then
  echo "ERRO: perfil decodificado vazio."
  exit 1
fi

security cms -D -i /tmp/cm_raw.mobileprovision > /tmp/cm_prov.plist
PROFILE_UUID=$(/usr/libexec/PlistBuddy -c 'Print UUID' /tmp/cm_prov.plist)
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c 'Print Name' /tmp/cm_prov.plist)
TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print TeamIdentifier:0' /tmp/cm_prov.plist)
PROFILES_HOME="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES_HOME"
cp /tmp/cm_raw.mobileprovision "${PROFILES_HOME}/${PROFILE_UUID}.mobileprovision"

_CM_P12_COMPACT="$(printf '%s' "${CM_CERTIFICATE}" | tr -d '\n\r\t ')"
if [ -z "${_CM_P12_COMPACT}" ]; then
  echo "ERRO: CM_CERTIFICATE vazio apos normalizar."
  exit 1
fi
if ! printf '%s' "${_CM_P12_COMPACT}" | base64 -D > /tmp/cm_distribution.p12 2>/tmp/_p12_b64.err; then
  echo "ERRO: CM_CERTIFICATE (P12) nao decodifica em Base64 valido."
  cat /tmp/_p12_b64.err 2>/dev/null || true
  exit 1
fi
if [ ! -s /tmp/cm_distribution.p12 ]; then
  echo "ERRO: P12 decodificado vazio."
  exit 1
fi

# Fail-fast com mensagem clara (evita "MAC verification failed" opaco do keychain).
echo "A verificar senha do P12 (Apple Distribution) antes do keychain..."
if [ -n "${CM_CERTIFICATE_PASSWORD:-}" ]; then
  export CM_CERTIFICATE_PASSWORD
  if ! openssl pkcs12 -in /tmp/cm_distribution.p12 -passin env:CM_CERTIFICATE_PASSWORD -noout 2>/tmp/_p12_openssl.err; then
    echo ""
    echo "ERRO: CM_CERTIFICATE_PASSWORD nao abre o ficheiro CM_CERTIFICATE (.p12)."
    echo "       (OpenSSL: senha errada, P12 corrompido ou nao e Apple Distribution.)"
    echo "       Corrija o secret CM_CERTIFICATE_PASSWORD no Codemagic (grupo appstore_credentials)."
    echo "       Use a MESMA senha definida ao exportar o .p12 «Apple Distribution» no Keychain (Mac)."
    echo "       Nao use a senha de um certificado de DESENVOLVIMENTO criado na UI da Codemagic."
    cat /tmp/_p12_openssl.err 2>/dev/null || true
    exit 1
  fi
else
  if ! openssl pkcs12 -in /tmp/cm_distribution.p12 -nodes -passin pass: -noout 2>/tmp/_p12_openssl.err; then
    echo ""
    echo "ERRO: o P12 exige senha (ou esta invalido). Defina CM_CERTIFICATE_PASSWORD no Codemagic."
    echo "       Se exportou o .p12 com password no Keychain, copie essa password para o secret."
    cat /tmp/_p12_openssl.err 2>/dev/null || true
    exit 1
  fi
fi

if [ -z "${CM_CERTIFICATE_PASSWORD:-}" ]; then
  keychain add-certificates --certificate /tmp/cm_distribution.p12
else
  keychain add-certificates --certificate /tmp/cm_distribution.p12 --certificate-password "$CM_CERTIFICATE_PASSWORD"
fi

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
echo "OK: certificado + perfil + ExportOptions.plist"

# Alinhar perfil ao P12: fetch-signing-files + opcional criação de perfil via API ASC (mesmo repositório).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.gestaoyahwehios.app}"
bash "${SCRIPT_DIR}/codemagic_ios_fetch_profile_matching_p12.sh" || true
