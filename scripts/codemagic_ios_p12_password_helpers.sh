#!/usr/bin/env bash
# Normalização da senha do P12 (Apple Distribution) no Codemagic + verificação OpenSSL.
# Problemas comuns: espaço ao colar no portal, quebra de linha no secret, uso de CERTIFICATE_PASSWORD
# em vez de CM_CERTIFICATE_PASSWORD, caracteres especiais com passin env:.
#
# Uso: source "$(dirname "$0")/codemagic_ios_p12_password_helpers.sh"
#      codemagic_normalize_p12_password_from_env

codemagic_normalize_p12_password_from_env() {
  # Alguns workflows Codemagic usam só CERTIFICATE_PASSWORD (mesmo valor = senha do .p12 exportado).
  if [ -z "${CM_CERTIFICATE_PASSWORD:-}" ] && [ -n "${CERTIFICATE_PASSWORD:-}" ]; then
    export CM_CERTIFICATE_PASSWORD="$CERTIFICATE_PASSWORD"
    echo "AVISO: CM_CERTIFICATE_PASSWORD vazio — a usar CERTIFICATE_PASSWORD. Renomeie o secret para CM_CERTIFICATE_PASSWORD (consistencia)."
  fi
  # Trim e uma única linha (evita falha "invalid password" por \n final).
  if [ -n "${CM_CERTIFICATE_PASSWORD:-}" ]; then
    CM_CERTIFICATE_PASSWORD="$(
      printf '%s' "$CM_CERTIFICATE_PASSWORD" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -d '\n\r'
    )"
    export CM_CERTIFICATE_PASSWORD
  fi
}

# Verifica se o OpenSSL abre o PKCS#12 (sem listar conteúdo).
# Senha via ficheiro temporário (compatível com caracteres especiais).
codemagic_verify_p12_opens_with_password() {
  local p12="${1:?caminho P12}"
  local err="${2:-/tmp/_cm_p12_openssl.err}"
  codemagic_normalize_p12_password_from_env
  if [ ! -f "$p12" ] || [ ! -s "$p12" ]; then
    echo "ERRO: P12 ausente ou vazio: $p12" >&2
    return 1
  fi
  if [ -n "${CM_CERTIFICATE_PASSWORD:-}" ]; then
    local pwf
    pwf="$(mktemp)"
    umask 077
    printf '%s' "$CM_CERTIFICATE_PASSWORD" > "$pwf"
    if ! openssl pkcs12 -in "$p12" -passin "file:${pwf}" -noout 2>"$err"; then
      rm -f "$pwf"
      return 1
    fi
    rm -f "$pwf"
    return 0
  fi
  if ! openssl pkcs12 -in "$p12" -nodes -passin pass: -noout 2>"$err"; then
    return 1
  fi
  return 0
}
