#!/usr/bin/env bash
# Codemagic (macOS): após instalar o P12 (CM_CERTIFICATE), tenta obter da App Store Connect
# um perfil App Store que INCLUA o certificado Distribution do P12 (SHA256), e substitui
# /tmp/cm_raw.mobileprovision + /tmp/cm_prov.plist + ExportOptions + cópia em Provisioning Profiles.
#
# Isto corrige automaticamente o caso comum: CM_PROVISIONING_PROFILE (secret) antigo com outro
# certificado Distribution do mesmo nome de equipa — o fetch traz o perfil actual da Apple.
#
# Desativar: export CM_SKIP_ASC_PROFILE_SYNC=1
# Pré-requisitos: /tmp/cm_distribution.p12, /tmp/_asc_ok.pem, APP_STORE_CONNECT_* (mesmo grupo).
# Sem pipefail: pipelines openssl não devem derrubar o script (sempre exit 0 = não bloqueia o YAML).
set -eu

ROOT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${CM_SKIP_ASC_PROFILE_SYNC:-}" == "1" ]]; then
  echo "CM_SKIP_ASC_PROFILE_SYNC=1 — a saltar sincronização ASC do perfil."
  exit 0
fi

P12=/tmp/cm_distribution.p12
BUNDLE="${IOS_BUNDLE_ID:-com.gestaoyahwehios.app}"
export IOS_BUNDLE_ID="$BUNDLE"

if [[ ! -f "$P12" ]]; then
  echo "AVISO: $P12 ausente — não é possível sincronizar perfil ASC."
  exit 0
fi
if [[ ! -f /tmp/_asc_ok.pem ]]; then
  echo "AVISO: /tmp/_asc_ok.pem ausente — não é possível sincronizar perfil ASC."
  exit 0
fi
if [[ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" || -z "${APP_STORE_CONNECT_KEY_IDENTIFIER:-}" ]]; then
  echo "AVISO: APP_STORE_CONNECT_ISSUER_ID / KEY_IDENTIFIER ausentes — saltar."
  exit 0
fi

if ! command -v app-store-connect >/dev/null 2>&1; then
  echo "A instalar codemagic-cli-tools (app-store-connect fetch-signing-files)..."
  python3 -m pip install --user -q "codemagic-cli-tools>=0.52.0"
  export PATH="$(python3 -m site --user-base)/bin:$PATH"
fi

PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"

# 1) API ASC primeiro: escolhe certificado pelo SHA256 do P12 e reutiliza/cria perfil IOS_APP_STORE.
#    Evita depender só do fetch-signing-files (perfil errado / permissões).
echo "=== App Store Connect API (prioridade): alinhar perfil ao P12 ==="
python3 "${ROOT_SCRIPT}/codemagic_ios_asc_api_ensure_appstore_profile.py" || true
if python3 "${ROOT_SCRIPT}/codemagic_ios_asc_api_ensure_appstore_profile.py" --matches-only; then
  echo "OK: /tmp/cm_raw.mobileprovision já inclui o certificado do P12 — saltar fetch-signing-files (CLI)."
  exit 0
fi

echo "=== app-store-connect fetch-signing-files ($BUNDLE, IOS_APP_STORE) ==="
set +e
app-store-connect fetch-signing-files "$BUNDLE" \
  --issuer-id "$APP_STORE_CONNECT_ISSUER_ID" \
  --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
  --private-key "@file:/tmp/_asc_ok.pem" \
  --type IOS_APP_STORE \
  --create \
  --delete-stale-profiles \
  --strict-match-identifier \
  --profiles-dir "$PROFILE_DIR" 2>&1 | tee /tmp/cm_fetch_signing.log
FETCH_EXIT=$?
set -eu
if [[ "$FETCH_EXIT" -ne 0 ]]; then
  echo ""
  echo "AVISO: fetch-signing-files terminou com código $FETCH_EXIT (permissões API / rede?)."
  echo "        Mantém-se o perfil instalado a partir de CM_PROVISIONING_PROFILE."
  exit 0
fi

export CM_CERTIFICATE_PASSWORD="${CM_CERTIFICATE_PASSWORD:-}"
set +e
python3 << 'PY'
import glob
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

bundle = os.environ.get("IOS_BUNDLE_ID", "com.gestaoyahwehios.app")
p12_path = "/tmp/cm_distribution.p12"
prov_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
_pw_raw = os.environ.get("CM_CERTIFICATE_PASSWORD") or os.environ.get("CERTIFICATE_PASSWORD") or ""
pw = (_pw_raw or "").strip().replace("\n", "").replace("\r", "")

def fp_sha256_der(der: bytes) -> str:
    p = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-fingerprint", "-sha256"],
        input=der,
        capture_output=True,
    )
    if p.returncode != 0:
        return ""
    line = p.stdout.decode().strip()
    if "=" not in line:
        return ""
    return line.split("=", 1)[-1].replace(":", "").upper()

def p12_leaf_der() -> bytes:
    pw_path = None
    try:
        if pw:
            fd, pw_path = tempfile.mkstemp(prefix="cm_p12_pw_")
            with os.fdopen(fd, "wb") as f:
                f.write(pw.encode("utf-8"))
            cmd = [
                "openssl", "pkcs12", "-in", p12_path,
                "-passin", "file:" + pw_path,
                "-clcerts", "-nokeys",
            ]
        else:
            cmd = [
                "openssl", "pkcs12", "-in", p12_path,
                "-nodes", "-passin", "pass:",
                "-clcerts", "-nokeys",
            ]
        p1 = subprocess.run(cmd, capture_output=True)
    finally:
        if pw_path:
            try:
                os.unlink(pw_path)
            except OSError:
                pass
    if p1.returncode != 0:
        print("ERRO: extrair certificado do P12 falhou (senha CM_CERTIFICATE_PASSWORD?).", file=sys.stderr)
        sys.exit(0)
    p2 = subprocess.run(
        ["openssl", "x509", "-outform", "DER"],
        input=p1.stdout,
        capture_output=True,
    )
    if p2.returncode != 0 or not p2.stdout:
        print("ERRO: conversão PEM→DER do leaf do P12 falhou.", file=sys.stderr)
        sys.exit(0)
    return p2.stdout

def plist_from_mobileprovision(path: str) -> dict:
    p = subprocess.run(
        ["security", "cms", "-D", "-i", path],
        capture_output=True,
    )
    if p.returncode != 0:
        return {}
    try:
        return plistlib.loads(p.stdout)
    except Exception:
        return {}

def app_id_matches(pl: dict, want: str) -> bool:
    ent = pl.get("Entitlements")
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
    return aid.endswith("." + want) or aid == want

try:
    der_p12 = p12_leaf_der()
except SystemExit:
    raise
except Exception as e:
    print("AVISO: leitura P12:", e, file=sys.stderr)
    sys.exit(0)

fp_p12 = fp_sha256_der(der_p12)
if not fp_p12:
    print("AVISO: fingerprint SHA256 do P12 indisponível.", file=sys.stderr)
    sys.exit(0)

best_path = None
best_name = ""
for mp in sorted(glob.glob(os.path.join(prov_dir, "*.mobileprovision"))):
    pl = plist_from_mobileprovision(mp)
    if not pl or not app_id_matches(pl, bundle):
        continue
    devs = pl.get("DeveloperCertificates") or []
    fps = []
    for item in devs:
        if isinstance(item, (bytes, bytearray)):
            f = fp_sha256_der(bytes(item))
            if f:
                fps.append(f)
    if fp_p12 in fps:
        best_path = mp
        best_name = str(pl.get("Name") or "")
        break

if not best_path:
    print("")
    print("AVISO: fetch-signing-files não deixou nenhum .mobileprovision em", prov_dir)
    print("        com bundle", bundle, "e certificado SHA256 do P12.")
    print("        P12 SHA256:", fp_p12)
    print("        Mantém-se o perfil do secret CM_PROVISIONING_PROFILE.")
    sys.exit(0)

uuid = str(plist_from_mobileprovision(best_path).get("UUID") or "")
team = ""
pl_full = plist_from_mobileprovision(best_path)
try:
    tid = pl_full.get("TeamIdentifier")
    if isinstance(tid, list) and tid:
        team = str(tid[0])
    elif isinstance(tid, str):
        team = tid
except Exception:
    pass

# Atualizar ficheiros usados pelo verify + xcode export
shutil.copyfile(best_path, "/tmp/cm_raw.mobileprovision")
subprocess.run(
    ["security", "cms", "-D", "-i", "/tmp/cm_raw.mobileprovision"],
    stdout=open("/tmp/cm_prov.plist", "wb"),
    check=True,
)
if uuid:
    shutil.copyfile(best_path, os.path.join(prov_dir, uuid + ".mobileprovision"))

exp = {
    "method": "app-store",
    "signingStyle": "manual",
    "teamID": team,
    "uploadSymbols": True,
    "provisioningProfiles": {bundle: best_name},
}
with open("/tmp/ExportOptions.plist", "wb") as f:
    plistlib.dump(exp, f, fmt=plistlib.FMT_XML)

print("")
print("OK: Perfil App Store da Apple inclui o certificado do P12 (SHA256 coincide).")
print("    A usar:", best_path)
print("    Nome perfil:", best_name, "| UUID:", uuid, "| teamID:", team)
print("    Substituídos: /tmp/cm_raw.mobileprovision, /tmp/cm_prov.plist, /tmp/ExportOptions.plist")
PY
_PY_EXIT=$?
set -eu
if [[ "$_PY_EXIT" -ne 0 ]]; then
  echo ""
  echo "AVISO: análise Python do perfil terminou com código $_PY_EXIT — mantém-se CM_PROVISIONING_PROFILE."
fi

# 3) Segunda passagem API (após fetch-signing-files / scan local): cobre o caso em que o CLI
#    actualizou perfis em ~/Library/... mas ainda não havíamos batido o SHA256 no passo 1.
echo "=== App Store Connect API (após fetch-signing-files): garantir perfil com o certificado do P12 ==="
python3 "${ROOT_SCRIPT}/codemagic_ios_asc_api_ensure_appstore_profile.py" || true

exit 0
