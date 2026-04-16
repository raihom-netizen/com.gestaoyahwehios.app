#!/usr/bin/env bash
# Assinatura iOS só com App Store Connect API (padrão «Controle Total»: 3 variáveis).
# Pré-requisitos: keychain initialize + /tmp/_asc_ok.pem
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

# fetch-signing-files --create exige --certificate-key (chave RSA do certificado Distribution),
# NAO e a chave .p8 da API. Ver: codemagic-cli-tools docs fetch-signing-files.
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
  echo "AVISO: sem CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM (PEM) — gerada chave RSA nova para criar/associar certificado Distribution."
  echo "        Recomendado: openssl genrsa 2048 > dist.pem ; colar PEM no secret CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM (evita multiplos certs na Apple)."
fi
if [ ! -s "$CERT_KEY_FILE" ] || ! grep -qE "BEGIN (EC |RSA )?PRIVATE KEY" "$CERT_KEY_FILE" 2>/dev/null; then
  echo "ERRO: chave RSA PEM invalida (ficheiro $CERT_KEY_FILE). Defina CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM com PEM completo."
  exit 1
fi
chmod 600 "$CERT_KEY_FILE"

echo "=== Modo API-only: app-store-connect fetch-signing-files ($BUNDLE, IOS_APP_STORE) ==="
set +e
app-store-connect fetch-signing-files "$BUNDLE" \
  --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
  --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
  --private-key "@file:/tmp/_asc_ok.pem" \
  --certificate-key "@file:${CERT_KEY_FILE}" \
  --type IOS_APP_STORE \
  --create \
  --delete-stale-profiles \
  --profiles-dir "$PROFILE_DIR" 2>&1 | tee /tmp/cm_api_only_fetch.log
FETCH_EXIT=$?
set -eu
if [[ "$FETCH_EXIT" -ne 0 ]]; then
  echo ""
  echo "ERRO: fetch-signing-files falhou (codigo $FETCH_EXIT)."
  echo "  A chave API precisa de permissoes para ler/criar certificados e perfis (papel Admin na App Store Connect)."
  echo "  Confirme APP_STORE_CONNECT_PRIVATE_KEY (.p8), KEY_IDENTIFIER e ISSUER_ID."
  tail -80 /tmp/cm_api_only_fetch.log 2>/dev/null || true
  exit 1
fi

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
    print("  Verifique fetch-signing-files e o bundle ID na Apple Developer.", file=sys.stderr)
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

_persist_asc_pem_to_cm_env
echo "OK: ExportOptions.plist + /tmp/cm_raw.mobileprovision (modo API-only)."
