#!/usr/bin/env bash
# Codemagic (macOS): falha ANTES de flutter build ipa se o .mobileprovision não incluir
# o certificado Apple Distribution do P12 (evita 8+ min de archive + exportArchive falho).
#
# Pré-requisitos (passo "JWT App Store Connect + keychain..." deste repositório):
#   /tmp/cm_distribution.p12
#   /tmp/cm_prov.plist   (security cms -D -i /tmp/cm_raw.mobileprovision)
#
# Uso: bash scripts/codemagic_ios_verify_profile_matches_p12.sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./codemagic_ios_p12_password_helpers.sh
source "${SCRIPT_DIR}/codemagic_ios_p12_password_helpers.sh"
codemagic_normalize_p12_password_from_env
if [[ -f /tmp/cm_yw_signing_mode ]] && [[ "$(tr -d '\r\n' < /tmp/cm_yw_signing_mode)" == "api_only" ]]; then
  echo "OK: modo api_only (Controle Total) — saltar verificação P12 vs perfil."
  exit 0
fi
if [[ -f /tmp/cm_yw_signing_mode ]] && [[ "$(tr -d '\r\n' < /tmp/cm_yw_signing_mode)" == "team_signing" ]]; then
  echo "OK: modo team_signing — certificados Codemagic; saltar verificação P12 vs perfil."
  exit 0
fi
# Última tentativa antes do fail-fast: API ASC (lista ampla de certificados + perfil / criação).
if [[ -f "${SCRIPT_DIR}/codemagic_ios_asc_api_ensure_appstore_profile.py" ]]; then
  echo "=== API App Store Connect: alinhar perfil .mobileprovision ao P12 ==="
  python3 "${SCRIPT_DIR}/codemagic_ios_asc_api_ensure_appstore_profile.py" || true
fi
set -euo pipefail

P12=/tmp/cm_distribution.p12
PLIST=/tmp/cm_prov.plist

if [[ ! -f "$P12" ]]; then
  echo "ERRO: $P12 ausente (passo JWT/keychain deve criar o P12)."
  exit 1
fi
if [[ ! -f "$PLIST" ]]; then
  echo "ERRO: $PLIST ausente. O passo JWT deve executar: security cms -D -i /tmp/cm_raw.mobileprovision > /tmp/cm_prov.plist"
  exit 1
fi

rm -f /tmp/p12_leaf.der /tmp/p12_leaf.pem

if [[ -n "${CM_CERTIFICATE_PASSWORD:-}" ]]; then
  _pwf="$(mktemp)"
  umask 077
  printf '%s' "$CM_CERTIFICATE_PASSWORD" > "$_pwf"
  if ! openssl pkcs12 -in "$P12" -passin "file:${_pwf}" -clcerts -nokeys 2>/dev/null \
      | openssl x509 -outform DER -out /tmp/p12_leaf.der; then
    rm -f "$_pwf"
    echo "ERRO: não foi possível extrair o certificado do P12 (senha CM_CERTIFICATE_PASSWORD incorreta?)."
    exit 1
  fi
  rm -f "$_pwf"
else
  if ! openssl pkcs12 -in "$P12" -nodes -passin pass: -clcerts -nokeys 2>/dev/null \
      | openssl x509 -outform DER -out /tmp/p12_leaf.der; then
    echo "ERRO: não foi possível extrair o certificado do P12 (sem senha). Tente definir CM_CERTIFICATE_PASSWORD no Codemagic."
    exit 1
  fi
fi

if [[ ! -s /tmp/p12_leaf.der ]]; then
  echo "ERRO: certificado extraído do P12 está vazio."
  exit 1
fi

python3 << 'PY'
import os
import plistlib
import subprocess
import sys

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

with open("/tmp/cm_prov.plist", "rb") as f:
    prov = plistlib.load(f)

# Sign In with Apple: só exigir no perfil se o projeto iOS tiver o entitlement no Runner.
# (Runner.entitlements sem applesignin → perfis App Store simples passam no Codemagic.)
_raw_pb = open("/tmp/cm_prov.plist", "rb").read()
_ent_check_root = os.environ.get("CM_BUILD_DIR") or os.environ.get("FCI_BUILD_DIR") or os.getcwd()
_cwd = os.getcwd()
_ent_candidates = [
    os.path.join(_ent_check_root, "flutter_app", "ios", "Runner", "Runner.entitlements"),
    os.path.join(_ent_check_root, "ios", "Runner", "Runner.entitlements"),
    os.path.join(_cwd, "flutter_app", "ios", "Runner", "Runner.entitlements"),
    os.path.join(_cwd, "ios", "Runner", "Runner.entitlements"),
]
_project_wants_apple_sign_in = False
for _p in _ent_candidates:
    try:
        if os.path.isfile(_p):
            _raw = open(_p, "rb").read()
            if b"com.apple.developer.applesignin" in _raw:
                _project_wants_apple_sign_in = True
            break
    except OSError:
        pass
if _project_wants_apple_sign_in and b"com.apple.developer.applesignin" not in _raw_pb:
    print("")
    print("ERRO: Runner.entitlements pede Sign In with Apple, mas o .mobileprovision nao inclui com.apple.developer.applesignin.")
    print("       Atualize CM_PROVISIONING_PROFILE apos ativar a capability no App ID.")
    print("       Ver: IOS/CODEMAGIC_SIGN_IN_APPLE.txt")
    sys.exit(1)
dev_certs = prov.get("DeveloperCertificates", [])
if not dev_certs:
    print("ERRO: DeveloperCertificates vazio no perfil — .mobileprovision inválido ou corrompido.")
    sys.exit(1)

fp_provs = []
for item in dev_certs:
    if not isinstance(item, (bytes, bytearray)):
        continue
    fp = fp_sha256_der(bytes(item))
    if fp:
        fp_provs.append(fp)

if not fp_provs:
    print("ERRO: não foi possível calcular fingerprints dos certificados embutidos no perfil.")
    sys.exit(1)

with open("/tmp/p12_leaf.der", "rb") as f:
    der_p12 = f.read()
fp_p12 = fp_sha256_der(der_p12)
if not fp_p12:
    print("ERRO: fingerprint do certificado do P12 falhou.")
    sys.exit(1)

def subject_cn(der: bytes) -> str:
    p = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-subject", "-nameopt", "RFC2253"],
        input=der,
        capture_output=True,
    )
    if p.returncode != 0:
        return ""
    line = p.stdout.decode().strip()
    if line.startswith("subject="):
        return line[9:].strip()
    return line


def fail_profile_mismatch(fp_p12: str, fp_provs: list, dev_certs: list) -> None:
    print("")
    print("ERRO: Provisioning profile NÃO inclui o certificado do P12 (CM_CERTIFICATE).")
    print("       Xcode exporta: exportArchive ... doesn't include signing certificate ...")
    print("")
    print("  Fingerprint SHA256 do P12:  " + fp_p12)
    print("  Fingerprints no perfil (" + str(len(fp_provs)) + " cert(s)):")
    for fp in fp_provs[:8]:
        print("    " + fp)
    if len(fp_provs) > 8:
        print("    ...")
    print("  Subjects no perfil (DeveloperCertificates):")
    for item in dev_certs[:8]:
        if isinstance(item, (bytes, bytearray)):
            sj = subject_cn(bytes(item))
            if sj:
                print("    " + sj)
    print("")
    print("Correção permanente:")
    print("  1) developer.apple.com → Certificates, Identifiers & Profiles → Profiles")
    print("  2) Abra o perfil App Store de com.gestaoyahwehios.app (ex.: gestaoyahwehiosapp) → Edit")
    print("  3) Em Certificates, marque o Apple Distribution: Raihom Barbosa (82RC6YL7KL) que corresponde ao .p12 exportado.")
    print("  4) Save → Download do NOVO .mobileprovision")
    print("  5) Codemagic → Team applications → Secrets (grupo appstore_credentials)")
    print("     → CM_PROVISIONING_PROFILE = Base64 do novo ficheiro (uma linha, sem quebras)")
    print("  Se renovou o certificado Distribution: exporte novo .p12 e atualize CM_CERTIFICATE também.")
    print("")
    print("  CI: o passo «Sync ASC profile with P12» corre fetch-signing-files na Apple;")
    print("       se este erro persistiu, a API não devolveu nenhum perfil App Store com o SHA256 do P12")
    print("       (corrija o perfil em developer.apple.com ou defina CM_SKIP_ASC_PROFILE_SYNC=1 para forçar só o secret).")
    print("")
    sys.exit(1)


subj_p12 = subject_cn(der_p12)
print("")
print("Certificados no perfil (.mobileprovision):")
for i, item in enumerate(dev_certs):
    if isinstance(item, (bytes, bytearray)):
        sj = subject_cn(bytes(item))
        print("  [" + str(i) + "] " + (sj or "(?)"))
print("P12 (leaf): " + (subj_p12 or "(subject indisponível)"))

if fp_p12 not in fp_provs:
    fail_profile_mismatch(fp_p12, fp_provs, dev_certs)

# Sign in with Apple: o IPA falha no archive se o App ID / perfil não incluírem o entitlement.
# Alguns .mobileprovision anexam Entitlements no topo; outros aninham — procurar recursivamente.
def plist_has_apple_signin(obj) -> bool:
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == "com.apple.developer.applesignin":
                return True
            if plist_has_apple_signin(v):
                return True
    elif isinstance(obj, list):
        for x in obj:
            if plist_has_apple_signin(x):
                return True
    return False

ent = prov.get("Entitlements")
if isinstance(ent, (bytes, bytearray)):
    try:
        ent = plistlib.loads(bytes(ent))
    except Exception:
        ent = {}
if not isinstance(ent, dict):
    ent = {}
# Mesmo critério do Xcode: só exigir SIWA no perfil se Runner.entitlements pedir applesignin.
has_siwa = "com.apple.developer.applesignin" in ent
if not has_siwa:
    # Alguns perfis anexam a capability noutro nível — procurar só em dicts (evita falso + no binário).
    has_siwa = plist_has_apple_signin(ent)

if _project_wants_apple_sign_in:
    if not has_siwa:
        print("")
        print("ERRO: Provisioning profile sem Sign In with Apple (com.apple.developer.applesignin).")
        print("       Xcode: Provisioning profile ... doesn't include the Sign In with Apple capability.")
        try:
            keys = sorted(ent.keys())
            print("  Chaves em Entitlements deste perfil (" + str(len(keys)) + "): " + ", ".join(keys[:24]) + (" ..." if len(keys) > 24 else ""))
        except Exception:
            pass
        print("")
        print("  1) developer.apple.com → Identifiers → com.gestaoyahwehios.app → Capabilities")
        print("     → ative «Sign In with Apple» → Save.")
        print("  2) Profiles → perfil App Store deste App ID (ex.: gestaoyahwehiosapp) → Edit → Save")
        print("  3) Download do NOVO .mobileprovision")
        print("  4) Codemagic → Secrets (appstore_credentials) → CM_PROVISIONING_PROFILE = Base64 (uma linha)")
        print("")
        print("  Ver: IOS/CODEMAGIC_SIGN_IN_APPLE.txt neste repositório.")
        sys.exit(1)
    print("OK: perfil inclui Sign In with Apple (com.apple.developer.applesignin).")
else:
    if has_siwa:
        print("AVISO: perfil inclui SIWA, mas Runner.entitlements nao declara applesignin (ok).")
    else:
        print("OK: Runner sem entitlement applesignin — nao exigimos SIWA no perfil (alinhado ao Xcode archive).")

print("OK: o perfil App Store inclui o certificado Apple Distribution do P12 (SHA256 coincide).")
sys.exit(0)
PY
