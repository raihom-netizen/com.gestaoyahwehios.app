#!/usr/bin/env bash
# Entrada única de assinatura iOS no CI — evita alternar API-only/PEM errado a cada push.
# Ordem: P12+perfil (manual, estável) → team_signing → API-only só se CM_FORCE_API_ONLY_SIGNING=1.
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

_force_api="${CM_FORCE_API_ONLY_SIGNING:-0}"
if [ "$_force_api" = "1" ] || [ "$_force_api" = "true" ]; then
  echo "=== Assinatura iOS: API-only (CM_FORCE_API_ONLY_SIGNING=1) ==="
  exec bash "${SCRIPT_DIR}/codemagic_ios_install_signing_api_only.sh"
fi

echo ""
echo "ERRO DEFINITIVO — faltam secrets de assinatura estável (P12 + perfil App Store)."
echo ""
echo "Codemagic → Environment variables → grupo appstore_credentials:"
echo "  1) APAGUE ou deixe VAZIO: CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM"
echo "     (este secret causa falha em todo build se não for o par exacto do certificado Apple)"
echo "  2) OBRIGATÓRIO: CM_CERTIFICATE ou CERTIFICATE_PRIVATE_KEY = Base64 do .p12 Apple Distribution (uma linha)"
echo "  3) OBRIGATÓRIO: CM_PROVISIONING_PROFILE = Base64 do .mobileprovision App Store (com.gestaoyahwehios.app)"
echo "  4) CM_CERTIFICATE_PASSWORD = senha do .p12 (ou vazio)"
echo ""
echo "PC (após colocar .p12 e .mobileprovision em pasta IOS/):"
echo "  .\\scripts\\encode_ios_codemagic_secrets.ps1"
echo "  Saída: D:\\Temporarios\\gestao_yahweh_codemagic\\"
echo ""
echo "Documentação: IOS\\CODEMAGIC_SIGNING_FIX.md | IOS\\ATUALIZAR_APOS_NOVO_CERTIFICADO.txt"
echo ""
exit 1
