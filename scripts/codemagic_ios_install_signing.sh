#!/usr/bin/env bash
# Entrada única de assinatura iOS no CI.
# Ordem: P12+perfil (se secrets) → team_signing → API-only automático (só .p8, como antes).
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"

# shellcheck source=./codemagic_ios_p12_password_helpers.sh
source "${SCRIPT_DIR}/codemagic_ios_p12_password_helpers.sh"

if [ -z "${CM_CERTIFICATE:-}" ] && [ -n "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  export CM_CERTIFICATE="$CERTIFICATE_PRIVATE_KEY"
fi
if [ -z "${CM_PROVISIONING_PROFILE:-}" ] && [ -n "${PROVISIONING_PROFILE:-}" ]; then
  export CM_PROVISIONING_PROFILE="$PROVISIONING_PROFILE"
fi

_has_p12_b64_secret() {
  local c
  c="$(printf '%s' "${CM_CERTIFICATE:-}" | tr -d '\n\r\t ')"
  [ -n "$c" ] || return 1
  if printf '%s' "$c" | grep -qE "BEGIN (EC |RSA )?PRIVATE KEY"; then
    return 1
  fi
  printf '%s' "$c" | base64 -D > /tmp/_cm_signing_probe_p12.bin 2>/dev/null || return 1
  [ -s /tmp/_cm_signing_probe_p12.bin ] || return 1
  return 0
}

_has_profile_b64_secret() {
  local p
  p="$(printf '%s' "${CM_PROVISIONING_PROFILE:-}" | tr -d '\n\r\t ')"
  [ -n "$p" ] || return 1
  printf '%s' "$p" | base64 -D > /tmp/_cm_signing_probe_prov.bin 2>/dev/null || return 1
  [ -s /tmp/_cm_signing_probe_prov.bin ] || return 1
  return 0
}

_mode="$(tr -d '\r\n' < /tmp/cm_yw_signing_mode 2>/dev/null || echo "")"

# Modo manual: nunca usar CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM (causa 409/erro recorrente).
if _has_p12_b64_secret && _has_profile_b64_secret; then
  if [ -n "${CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM:-}" ]; then
    echo "AVISO: CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM ignorado — assinatura estável via P12+perfil."
    unset CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM || true
  fi
  echo "=== Assinatura iOS: modo manual (P12 + mobileprovision) ==="
  exec bash "${SCRIPT_DIR}/codemagic_ios_install_p12_profile_exportoptions.sh"
fi

if [ "$_mode" = "team_signing" ]; then
  exec bash "${SCRIPT_DIR}/codemagic_ios_team_signing_prepare_exportoptions.sh"
fi

if [ "$_mode" = "api_only" ]; then
  echo "=== Assinatura iOS: API-only automático (App Store Connect API) ==="
  exec bash "${SCRIPT_DIR}/codemagic_ios_install_signing_api_only.sh"
fi

_disallow="${CM_DISALLOW_API_ONLY_SIGNING:-0}"
if [ "$_disallow" = "1" ] || [ "$_disallow" = "true" ]; then
  echo "ERRO: CM_DISALLOW_API_ONLY_SIGNING=1 e faltam P12+perfil. Ver passo «Verificar variaveis»."
  exit 1
fi

echo "=== Assinatura iOS: API-only automático (fallback) ==="
exec bash "${SCRIPT_DIR}/codemagic_ios_install_signing_api_only.sh"
