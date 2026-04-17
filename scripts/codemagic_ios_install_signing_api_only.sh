#!/usr/bin/env bash
# Assinatura iOS só com App Store Connect API (padrão «Controle Total»: 3 variáveis).
# Pré-requisitos: keychain initialize + /tmp/_asc_ok.pem
#
# Sem CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM: primeiro descarrega perfis/certificados
# já existentes na Apple (sem --create), para não gerar chave RSA aleatória nem bater no 409.
# Com CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM (mesmo PEM em todos os builds): pode usar --create.
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f /tmp/_asc_ok.pem ]; then
  echo "ERRO: /tmp/_asc_ok.pem ausente — execute antes: Preparar PEM App Store Connect."
  exit 1
fi

BUNDLE="${IOS_BUNDLE_ID:-com.gestaoyahwehios.app}"

_persist_asc_pem_to_cm_env() {
  [ -n "${CM_ENV:-}" ] && [ -f /tmp/_asc_ok.pem ] || return 0
  _ASC_DELIM="CMGYYWHASCPEM594E2F1END"
  {
    echo "APP_STORE_CONNECT_PRIVATE_KEY<<${_ASC_DELIM}"
    cat /tmp/_asc_ok.pem
    printf '\n%s\n' "${_ASC_DELIM}"
  } >> "$CM_ENV"
}

if ! command -v app-store-connect >/dev/null 2>&1; then
  echo "A instalar codemagic-cli-tools (app-store-connect)..."
  python3 -m pip install --user -q "codemagic-cli-tools>=0.52.0"
  export PATH="$(python3 -m site --user-base)/bin:$PATH"
fi

PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"

_has_fixed_distribution_key() {
  if [ -n "${CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM:-}" ]; then
    return 0
  fi
  if [ -n "${CERTIFICATE_PRIVATE_KEY:-}" ] && printf '%s' "${CERTIFICATE_PRIVATE_KEY}" | grep -qE "BEGIN (EC |RSA )?PRIVATE KEY"; then
    return 0
  fi
  return 1
}

_prepare_cert_key_file() {
  CERT_KEY_FILE="/tmp/cm_distribution_rsa_for_fetch.pem"
  rm -f "$CERT_KEY_FILE"
  if [ -n "${CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM:-}" ]; then
    if printf '%s' "${CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM}" | grep -qE "BEGIN (EC |RSA )?PRIVATE KEY"; then
      printf '%s' "${CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM}" > "$CERT_KEY_FILE"
    else
      _b64="$(printf '%s' "${CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM}" | tr -d '\n\r\t ')"
      if ! printf '%s' "$_b64" | base64 -D > "$CERT_KEY_FILE" 2>/dev/null; then
        printf '%s' "${CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM}" > "$CERT_KEY_FILE"
      fi
    fi
  elif [ -n "${CERTIFICATE_PRIVATE_KEY:-}" ] && printf '%s' "${CERTIFICATE_PRIVATE_KEY}" | grep -qE "BEGIN (EC |RSA )?PRIVATE KEY"; then
    printf '%s' "${CERTIFICATE_PRIVATE_KEY}" > "$CERT_KEY_FILE"
  else
    openssl genrsa -out "$CERT_KEY_FILE" 2048 2>/dev/null || openssl genrsa -traditional -out "$CERT_KEY_FILE" 2048
    echo "AVISO: gerada chave RSA nova (só para tentativa --create). Guarde PEM fixo em CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM para builds estáveis."
  fi
  if [ ! -s "$CERT_KEY_FILE" ] || ! grep -qE "BEGIN (EC |RSA )?PRIVATE KEY" "$CERT_KEY_FILE" 2>/dev/null; then
    echo "ERRO: chave RSA PEM invalida (ficheiro $CERT_KEY_FILE). Defina CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM com PEM completo."
    exit 1
  fi
  chmod 600 "$CERT_KEY_FILE"
  echo "$CERT_KEY_FILE"
}

_run_select_profile_python() {
  export IOS_BUNDLE_ID="$BUNDLE"
  python3 << 'PY'
import glob
import os
import plistlib
import shutil
import subprocess
import sys

bundle = os.environ.get("IOS_BUNDLE_ID", "com.gestaoyahwehios.app").strip()
prov_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
want_suffix = "." + bundle


def load_plist(path: str):
    r = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True)
    if r.returncode != 0 or not r.stdout:
        return None
    try:
        return plistlib.loads(r.stdout)
    except Exception:
        return None


def profile_matches(pl: dict) -> bool:
    ent = pl.get("Entitlements") or {}
    if isinstance(ent, (bytes, bytearray)):
        try:
            ent = plistlib.loads(bytes(ent))
        except Exception:
            ent = {}
    if not isinstance(ent, dict):
        return False
    aid = ent.get("application-identifier")
    if not isinstance(aid, str):
        return False
    return aid.endswith(want_suffix) or aid == bundle


def is_distribution_app_store(pl: dict) -> bool:
    ent = pl.get("Entitlements") or {}
    if isinstance(ent, (bytes, bytearray)):
        try:
            ent = plistlib.loads(bytes(ent))
        except Exception:
            ent = {}
    if not isinstance(ent, dict):
        return False
    if ent.get("get-task-allow") is True:
        return False
    devs = pl.get("ProvisionedDevices")
    if isinstance(devs, list) and len(devs) > 0:
        return False
    return True


best_path = None
best_pl = None
best_mtime = 0.0
for path in glob.glob(os.path.join(prov_dir, "*.mobileprovision")):
    try:
        mtime = os.stat(path).st_mtime
    except OSError:
        continue
    pl = load_plist(path)
    if not pl or not profile_matches(pl):
        continue
    if not is_distribution_app_store(pl):
        continue
    if mtime >= best_mtime:
        best_mtime = mtime
        best_path = path
        best_pl = pl

if not best_path or not best_pl:
    print("ERRO: nenhum perfil App Store adequado em", prov_dir, "para", bundle, file=sys.stderr)
    print("  Crie/edite um perfil IOS_APP_STORE para este bundle na Apple Developer ou defina CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM.", file=sys.stderr)
    sys.exit(1)

shutil.copyfile(best_path, "/tmp/cm_raw.mobileprovision")
out_pl = subprocess.run(
    ["security", "cms", "-D", "-i", "/tmp/cm_raw.mobileprovision"],
    capture_output=True,
)
if out_pl.returncode != 0:
    print("ERRO: security cms no perfil.", file=sys.stderr)
    sys.exit(1)
with open("/tmp/cm_prov.plist", "wb") as f:
    f.write(out_pl.stdout)

name = str(best_pl.get("Name") or "").strip()
team_ids = best_pl.get("TeamIdentifier")
if isinstance(team_ids, list) and team_ids:
    team = str(team_ids[0]).strip()
else:
    team = ""
if not name or not team:
    print("ERRO: Name/TeamIdentifier no perfil.", file=sys.stderr)
    sys.exit(1)

data = {
    "method": "app-store",
    "signingStyle": "manual",
    "teamID": team,
    "uploadSymbols": True,
    "provisioningProfiles": {bundle: name},
}
with open("/tmp/ExportOptions.plist", "wb") as f:
    plistlib.dump(data, f, fmt=plistlib.FMT_XML)

uuid_val = str(best_pl.get("UUID") or "")
print("OK API-only: perfil=", name, "uuid=", uuid_val, "team=", team)
PY
}

_log_suggests_409() {
  [ -f /tmp/cm_api_only_fetch.log ] && grep -E "returned 409|current Distribution certificate|pending certificate request" /tmp/cm_api_only_fetch.log >/dev/null 2>&1
}

_fetch_with_create() {
  local cert_key_file="$1"
  set +e
  app-store-connect fetch-signing-files "$BUNDLE" \
    --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
    --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
    --private-key "@file:/tmp/_asc_ok.pem" \
    --certificate-key "@file:${cert_key_file}" \
    --type IOS_APP_STORE \
    --create \
    --delete-stale-profiles \
    --profiles-dir "$PROFILE_DIR" 2>&1 | tee /tmp/cm_api_only_fetch.log
  local ex=$?
  set -eu
  if [[ "$ex" -ne 0 ]] && _log_suggests_409; then
    echo ""
    echo "AVISO: Apple recusou criar novo certificado Distribution (409)."
    echo "       Fallback: reutilizar recursos existentes sem --create."
    set +e
    app-store-connect fetch-signing-files "$BUNDLE" \
      --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
      --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
      --private-key "@file:/tmp/_asc_ok.pem" \
      --type IOS_APP_STORE \
      --profiles-dir "$PROFILE_DIR" 2>&1 | tee /tmp/cm_api_only_fetch_fallback.log
    ex=$?
    set -eu
  fi
  return "$ex"
}

# --- Fluxo principal ---
FETCH_EXIT=0
REST_EXIT=0
if _has_fixed_distribution_key; then
  echo "=== Modo API-only: chave Distribution fixa + fetch-signing-files ($BUNDLE, IOS_APP_STORE) ==="
  CERT_KEY_FILE="$(_prepare_cert_key_file)"
  set +e
  _fetch_with_create "$CERT_KEY_FILE"
  FETCH_EXIT=$?
  set -eu
  if [[ "$FETCH_EXIT" -ne 0 ]]; then
    echo ""
    echo "AVISO: fetch-signing-files (--create) terminou com codigo $FETCH_EXIT (ver log)."
    tail -40 /tmp/cm_api_only_fetch.log 2>/dev/null || true
    tail -40 /tmp/cm_api_only_fetch_fallback.log 2>/dev/null || true
  fi
else
  echo "=== Modo API-only (só API .p8): fetch SEM --create e SEM --delete-stale-profiles (evita 409 e limpezas agressivas) ==="
  set +e
  app-store-connect fetch-signing-files "$BUNDLE" \
    --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
    --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
    --private-key "@file:/tmp/_asc_ok.pem" \
    --type IOS_APP_STORE \
    --profiles-dir "$PROFILE_DIR" 2>&1 | tee /tmp/cm_api_only_fetch.log
  FETCH_EXIT=$?
  set -eu
  if [[ "$FETCH_EXIT" -ne 0 ]]; then
    echo ""
    echo "AVISO: fetch sem --create terminou com codigo $FETCH_EXIT (ver log)."
    tail -40 /tmp/cm_api_only_fetch.log 2>/dev/null || true
  fi
fi

if _run_select_profile_python; then
  _persist_asc_pem_to_cm_env
  echo "OK: ExportOptions.plist + /tmp/cm_raw.mobileprovision (API-only, CLI)."
  exit 0
fi

echo ""
echo "=== Fallback: perfil IOS_APP_STORE via REST (App Store Connect API) ==="
set +e
python3 "$SCRIPT_DIR/codemagic_ios_asc_api_ensure_appstore_profile.py" --download-app-store-profile-api-only
REST_EXIT=$?
set -eu
if [[ "$REST_EXIT" -ne 0 ]]; then
  echo "AVISO: fallback REST terminou com codigo $REST_EXIT."
fi

if _run_select_profile_python; then
  _persist_asc_pem_to_cm_env
  echo "OK: ExportOptions.plist + /tmp/cm_raw.mobileprovision (API-only, REST ASC)."
  exit 0
fi

echo ""
echo "ERRO: nenhum perfil App Store adequado após CLI (codigo ${FETCH_EXIT}) + REST (codigo ${REST_EXIT})."
echo "  Confirme chave API (Admin) e APP_STORE_CONNECT_*."
echo "  Recomendado: CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM (mesmo PEM em todos os builds) — scripts/gen_ios_distribution_csr_private_key_pem.ps1"
echo "  Ou modo manual: CM_CERTIFICATE + CM_PROVISIONING_PROFILE (Base64)."
tail -80 /tmp/cm_api_only_fetch.log 2>/dev/null || true
tail -80 /tmp/cm_api_only_fetch_fallback.log 2>/dev/null || true
exit 1
