#!/usr/bin/env bash
# Devolve o maior CFBundleVersion já enviado à App Store Connect (TestFlight/App Store).
# Saída: número inteiro em stdout; exit 0. Em falha: imprime 0 e exit 1.
set -euo pipefail

APP_ID="${APP_STORE_APPLE_ID:-}"
if [[ -z "$APP_ID" ]]; then
  echo "AVISO: APP_STORE_APPLE_ID vazio." >&2
  echo 0
  exit 1
fi

if [[ ! -f /tmp/_asc_ok.pem ]]; then
  ROOT="${CM_BUILD_DIR:-${FCI_BUILD_DIR:-$(pwd)}}"
  if [[ -f "$ROOT/scripts/codemagic_ios_prepare_api_pem.sh" ]]; then
    bash "$ROOT/scripts/codemagic_ios_prepare_api_pem.sh" || true
  fi
fi
if [[ ! -f /tmp/_asc_ok.pem ]]; then
  echo "AVISO: /tmp/_asc_ok.pem ausente — não consultar ASC." >&2
  echo 0
  exit 1
fi

if [[ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" || -z "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ]]; then
  echo "AVISO: credenciais App Store Connect API incompletas." >&2
  echo 0
  exit 1
fi

if ! command -v app-store-connect >/dev/null 2>&1; then
  echo "A instalar codemagic-cli-tools (app-store-connect)..." >&2
  python3 -m pip install --user -q "codemagic-cli-tools>=0.52.0"
  export PATH="$(python3 -m site --user-base)/bin:$PATH"
fi

_asc_query() {
  local subcmd="$1"
  local raw=""
  set +e
  raw="$(app-store-connect "$subcmd" "$APP_ID" \
    --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
    --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
    --private-key "@file:/tmp/_asc_ok.pem" 2>/dev/null | tr -d '\r\n' | head -n 1)"
  local ec=$?
  set -e
  if [[ $ec -ne 0 || -z "$raw" || ! "$raw" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  echo "$raw"
}

LATEST=""
if LATEST="$(_asc_query get-latest-testflight-build-number)"; then
  echo "ASC (TestFlight): último build number = $LATEST" >&2
elif LATEST="$(_asc_query get-latest-app-store-build-number)"; then
  echo "ASC (App Store): último build number = $LATEST" >&2
else
  echo "AVISO: não foi possível ler último build number na ASC (rede/API)." >&2
  echo 0
  exit 1
fi

FLOOR=0
if [[ -f "${CM_BUILD_DIR:-}/flutter_app/ios/asc_build_number_floor.txt" ]]; then
  FLOOR="$(tr -d '\r\n[:space:]' < "${CM_BUILD_DIR}/flutter_app/ios/asc_build_number_floor.txt" 2>/dev/null || echo 0)"
elif [[ -f "${FCI_BUILD_DIR:-}/flutter_app/ios/asc_build_number_floor.txt" ]]; then
  FLOOR="$(tr -d '\r\n[:space:]' < "${FCI_BUILD_DIR}/flutter_app/ios/asc_build_number_floor.txt" 2>/dev/null || echo 0)"
fi
case "$FLOOR" in
  ''|*[!0-9]*) FLOOR=0 ;;
esac
if [[ "$FLOOR" -gt "$LATEST" ]]; then
  echo "ASC: usando floor do repo ($FLOOR) > API ($LATEST)" >&2
  LATEST="$FLOOR"
fi

echo "$LATEST"
