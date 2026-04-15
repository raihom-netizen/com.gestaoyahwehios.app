#!/usr/bin/env bash
# Gera /tmp/_asc_ok.pem a partir de APP_STORE_CONNECT_PRIVATE_KEY (PEM ou Base64 PEM).
# Não exporta PEM multilinha para o ambiente (evita CM_ENV delimiter quebrado no Codemagic).
set -euo pipefail

_secret_to_pem_file() {
  local val="$1"
  local out="$2"
  printf '%b' "$val" | tr -d '\r' | perl -0777 -pe 's/^\xEF\xBB\xBF//; s/\A"(.*)"\z/$1/s; s/\A'\''(.*)'\''\z/$1/s' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$out"
}

_looks_like_pem_api() { grep -qE 'BEGIN (EC )?PRIVATE KEY|BEGIN PRIVATE KEY' "$1"; }

_norm_api() {
  _secret_to_pem_file "${APP_STORE_CONNECT_PRIVATE_KEY}" /tmp/_asc_raw.pem
  if [ ! -s /tmp/_asc_raw.pem ]; then
    echo "ERRO: APP_STORE_CONNECT_PRIVATE_KEY vazio ou sumiu ao gravar /tmp/_asc_raw.pem."
    exit 1
  fi
  if _looks_like_pem_api /tmp/_asc_raw.pem; then
    cat /tmp/_asc_raw.pem > /tmp/_asc_ok.pem
  elif base64 -D < /tmp/_asc_raw.pem > /tmp/_asc_dec.pem 2>/tmp/_asc_b64.err && [ -s /tmp/_asc_dec.pem ] && _looks_like_pem_api /tmp/_asc_dec.pem; then
    cat /tmp/_asc_dec.pem > /tmp/_asc_ok.pem
  else
    echo "ERRO: APP_STORE_CONNECT_PRIVATE_KEY nao e PEM .p8 valido nem Base64 de PEM."
    [ -s /tmp/_asc_b64.err ] && cat /tmp/_asc_b64.err
    exit 1
  fi
  unset APP_STORE_CONNECT_PRIVATE_KEY || true
}

_norm_api
echo "OK: /tmp/_asc_ok.pem ($(wc -c < /tmp/_asc_ok.pem | tr -d ' ') bytes)"
