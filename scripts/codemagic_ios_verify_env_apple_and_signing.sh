#!/usr/bin/env bash
# Codemagic: valida App Store Connect API + modo de assinatura.
# Modo A — «Controle Total» (só 3 secrets): APP_STORE_CONNECT_PRIVATE_KEY + KEY_IDENTIFIER + ISSUER_ID
#   (sem CM_CERTIFICATE / CERTIFICATE_PRIVATE_KEY / CM_PROVISIONING_PROFILE). O CI obtém certificado
#   e perfil com app-store-connect fetch-signing-files.
# Modo B — manual: CM_CERTIFICATE ou CERTIFICATE_PRIVATE_KEY (P12 Base64) + CM_PROVISIONING_PROFILE + senha se aplicável.
# Modo C — team_signing: CM_USE_CODEMAGIC_TEAM_SIGNING=1 + codemagic.yaml «ios_signing» (certificados na equipa Codemagic).
set -eu
ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
# shellcheck source=./codemagic_ios_p12_password_helpers.sh
source "$ROOT/scripts/codemagic_ios_p12_password_helpers.sh"

echo "=== Verificar credenciais Apple (Codemagic) ==="

if [ -z "${CM_CERTIFICATE:-}" ] && [ -n "${CERTIFICATE_PRIVATE_KEY:-}" ]; then
  export CM_CERTIFICATE="$CERTIFICATE_PRIVATE_KEY"
  echo "AVISO: CM_CERTIFICATE vazio — a usar CERTIFICATE_PRIVATE_KEY (mesmo nome que Controle Total / UI Codemagic)."
fi
if [ -z "${CM_PROVISIONING_PROFILE:-}" ] && [ -n "${PROVISIONING_PROFILE:-}" ]; then
  export CM_PROVISIONING_PROFILE="$PROVISIONING_PROFILE"
  echo "AVISO: CM_PROVISIONING_PROFILE vazio — a usar PROVISIONING_PROFILE (alias UI Codemagic)."
fi

: "${APP_STORE_CONNECT_PRIVATE_KEY:?Grupo appstore_credentials: APP_STORE_CONNECT_PRIVATE_KEY (.p8)}"
: "${APP_STORE_CONNECT_KEY_IDENTIFIER:?APP_STORE_CONNECT_KEY_IDENTIFIER (Key ID)}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID (Issuer UUID)}"

_CM_CERT_COMPACT="$(printf '%s' "${CM_CERTIFICATE:-}" | tr -d '\n\r\t ')"
if [ -z "$_CM_CERT_COMPACT" ]; then
  _ts="${CM_USE_CODEMAGIC_TEAM_SIGNING:-0}"
  if [ "$_ts" = "1" ] || [ "$_ts" = "true" ]; then
    echo "team_signing" > /tmp/cm_yw_signing_mode
    echo "OK: modo team_signing — certificados/perfis via codemagic.yaml «ios_signing» (equipa Codemagic)."
    echo "    (Nao usa CERTIFICATE_PRIVATE_KEY nos secrets; evita POST /certificates 403.)"
    exit 0
  fi
  echo "api_only" > /tmp/cm_yw_signing_mode
  echo "OK: modo API-only — fetch-signing-files (com --certificate-key RSA)."
  echo "AVISO: Com chave API sem permissao para criar certificados, o passo 11 pode dar 403."
  echo "       Ou defina CM_USE_CODEMAGIC_TEAM_SIGNING=1 + ios_signing no YAML, ou P12+perfil nos secrets."
  exit 0
fi

echo "manual" > /tmp/cm_yw_signing_mode
echo "OK: modo manual — P12 + perfil nos secrets (ou P12 + sincronização ASC nos passos seguintes)."

: "${CM_CERTIFICATE:?Defina CM_CERTIFICATE ou CERTIFICATE_PRIVATE_KEY (P12 Apple Distribution Base64), ou remova ambos para modo API-only (3 variáveis).}"
: "${CM_PROVISIONING_PROFILE:?Modo manual: CM_PROVISIONING_PROFILE ou PROVISIONING_PROFILE (perfil App Store .mobileprovision Base64).}"

_CM_PROV_COMPACT="$(printf '%s' "${CM_PROVISIONING_PROFILE}" | tr -d '\n\r\t ')"
if [ -z "${_CM_PROV_COMPACT}" ]; then
  echo "ERRO: CM_PROVISIONING_PROFILE / PROVISIONING_PROFILE vazio apos normalizar."
  echo "  Codemagic > appstore_credentials — CM_PROVISIONING_PROFILE ou PROVISIONING_PROFILE (perfil do bundle com.gestaoyahwehios.app)"
  exit 1
fi
if ! printf '%s' "${_CM_PROV_COMPACT}" | base64 -D > /tmp/_cm_verify_prov.bin 2>/tmp/_cm_verify_prov.err; then
  echo "ERRO: CM_PROVISIONING_PROFILE nao decodifica em Base64 valido."
  cat /tmp/_cm_verify_prov.err 2>/dev/null || true
  exit 1
fi
if [ ! -s /tmp/_cm_verify_prov.bin ]; then
  echo "ERRO: CM_PROVISIONING_PROFILE decodifica para ficheiro vazio."
  exit 1
fi

_CM_P12_COMPACT="$(printf '%s' "${CM_CERTIFICATE}" | tr -d '\n\r\t ')"
if [ -z "${_CM_P12_COMPACT}" ]; then
  echo "ERRO: CM_CERTIFICATE vazio apos normalizar."
  exit 1
fi
if ! printf '%s' "${_CM_P12_COMPACT}" | base64 -D > /tmp/_cm_verify_p12.bin 2>/tmp/_cm_verify_p12.err; then
  echo "ERRO: CM_CERTIFICATE (P12) nao decodifica em Base64 valido."
  cat /tmp/_cm_verify_p12.err 2>/dev/null || true
  exit 1
fi
if [ ! -s /tmp/_cm_verify_p12.bin ]; then
  echo "ERRO: CM_CERTIFICATE decodifica para ficheiro vazio."
  exit 1
fi

codemagic_normalize_p12_password_from_env
echo "A verificar senha do P12 (fail-fast)..."
if ! codemagic_verify_p12_opens_with_password /tmp/_cm_verify_p12.bin /tmp/_early_p12.err; then
  echo ""
  echo "ERRO: CM_CERTIFICATE_PASSWORD nao abre o CM_CERTIFICATE (.p12)."
  echo "  Codemagic > Secrets — CM_CERTIFICATE_PASSWORD ou CERTIFICATE_PASSWORD = senha do export .p12 (Mac)."
  cat /tmp/_early_p12.err 2>/dev/null || true
  exit 1
fi

echo "OK: P12 + provisioning decodificam (prov=$(wc -c < /tmp/_cm_verify_prov.bin) p12=$(wc -c < /tmp/_cm_verify_p12.bin) bytes); senha P12 validada."
