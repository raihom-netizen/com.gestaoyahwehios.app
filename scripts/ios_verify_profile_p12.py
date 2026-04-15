#!/usr/bin/env python3
"""
Compara o certificado Apple Distribution do .p12 com os certificados embutidos no
.mobileprovision (DeveloperCertificates). É o mesmo critério do Xcode exportArchive.

Uso (na raiz do repo):
  python scripts/ios_verify_profile_p12.py
  python scripts/ios_verify_profile_p12.py --ios-dir IOS --p12-password "sua_senha"

Saída: exit 0 se o SHA256 do leaf do P12 estiver no perfil; exit 1 com instruções Apple/Codemagic.
"""
from __future__ import annotations

import argparse
import plistlib
import subprocess
import sys
from pathlib import Path


def _fp_sha256_der(der: bytes) -> str:
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


def _subject_cn_der(der: bytes) -> str:
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


def _load_mobileprovision_plist(path: Path) -> dict:
    raw = path.read_bytes()
    start = raw.find(b"<?xml")
    if start < 0:
        print("ERRO: .mobileprovision sem plist XML embutido (ficheiro corrompido?).", file=sys.stderr)
        sys.exit(1)
    end = raw.find(b"</plist>", start)
    if end < 0:
        print("ERRO: plist XML truncado no .mobileprovision.", file=sys.stderr)
        sys.exit(1)
    end += len(b"</plist>")
    try:
        return plistlib.loads(raw[start:end])
    except Exception as e:
        print(f"ERRO: plist inválido: {e}", file=sys.stderr)
        sys.exit(1)


def _p12_leaf_der(p12: Path, password: str) -> bytes:
    cmd = [
        "openssl",
        "pkcs12",
        "-in",
        str(p12),
        "-nodes",
        "-passin",
        f"pass:{password}",
        "-clcerts",
        "-nokeys",
    ]
    p = subprocess.run(cmd, capture_output=True)
    if p.returncode != 0:
        err = p.stderr.decode(errors="replace").strip()
        print(
            "ERRO: não foi possível ler o .p12 (senha errada ou ficheiro inválido).\n"
            f"  openssl: {err}",
            file=sys.stderr,
        )
        sys.exit(1)
    q = subprocess.run(
        ["openssl", "x509", "-outform", "DER"],
        input=p.stdout,
        capture_output=True,
    )
    if q.returncode != 0 or not q.stdout:
        print("ERRO: não foi possível extrair o certificado leaf do .p12.", file=sys.stderr)
        sys.exit(1)
    return q.stdout


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--ios-dir",
        type=Path,
        default=None,
        help="Pasta com gestaoyahwehiosapp.mobileprovision e gestaoyahwehiosapp.p12 (default: IOS na raiz do repo)",
    )
    ap.add_argument(
        "--p12-password",
        default="",
        help="Password do .p12 (evite deixar no histórico; prefira prompt interativo no wrapper PowerShell).",
    )
    args = ap.parse_args()

    root = Path(__file__).resolve().parent.parent
    ios_dir = args.ios_dir if args.ios_dir is not None else root / "IOS"
    prov_path = ios_dir / "gestaoyahwehiosapp.mobileprovision"
    p12_path = ios_dir / "gestaoyahwehiosapp.p12"

    if not prov_path.is_file():
        print(f"ERRO: não encontrado {prov_path}", file=sys.stderr)
        return 1
    if not p12_path.is_file():
        print(f"ERRO: não encontrado {p12_path}", file=sys.stderr)
        return 1

    prov = _load_mobileprovision_plist(prov_path)
    name = prov.get("Name", "(sem nome)")
    app_id = prov.get("AppIDName", prov.get("Entitlements", {}))
    print(f"Perfil: {name}")
    if isinstance(prov.get("Entitlements"), dict):
        tid = prov["Entitlements"].get("com.apple.developer.team-identifier", "")
        bid = prov["Entitlements"].get("application-identifier", "")
        if tid or bid:
            print(f"  team-identifier / app-id: {tid}  {bid}")

    dev_certs = prov.get("DeveloperCertificates") or []
    if not dev_certs:
        print("ERRO: DeveloperCertificates vazio no .mobileprovision.", file=sys.stderr)
        return 1

    fp_provs: list[str] = []
    print("Certificados listados no .mobileprovision:")
    for i, item in enumerate(dev_certs):
        if not isinstance(item, (bytes, bytearray)):
            continue
        der = bytes(item)
        sub = _subject_cn_der(der)
        fp = _fp_sha256_der(der)
        fp_provs.append(fp)
        print(f"  [{i}] {sub}")
        print(f"       SHA256: {fp}")

    pwd = args.p12_password
    der_p12 = _p12_leaf_der(p12_path, pwd)
    fp_p12 = _fp_sha256_der(der_p12)
    sub_p12 = _subject_cn_der(der_p12)
    print("")
    print(f"P12 (leaf): {sub_p12}")
    print(f"       SHA256: {fp_p12}")

    if not fp_p12:
        print("ERRO: fingerprint do P12 falhou.", file=sys.stderr)
        return 1

    if fp_p12 not in fp_provs:
        print("", file=sys.stderr)
        print("ERRO: o .mobileprovision NÃO inclui o certificado Apple Distribution deste .p12.", file=sys.stderr)
        print("       Xcode/Codemagic: exportArchive ... doesn't include signing certificate ...", file=sys.stderr)
        print("", file=sys.stderr)
        print("Correção (Apple Developer → Profiles):", file=sys.stderr)
        print("  1) Abra o perfil App Store gestaoyahwehiosapp → Edit.", file=sys.stderr)
        print("  2) Em Certificates, marque exactamente:", file=sys.stderr)
        print(f"     {sub_p12 or 'Apple Distribution: Raihom Barbosa (82RC6YL7KL)'}", file=sys.stderr)
        print("  3) Save → Download → substitua IOS/gestaoyahwehiosapp.mobileprovision", file=sys.stderr)
        print("  4) Codemagic → CM_PROVISIONING_PROFILE = Base64 do NOVO .mobileprovision (uma linha).", file=sys.stderr)
        print("", file=sys.stderr)
        print("Se o certificado correcto NÃO aparece na lista do perfil:", file=sys.stderr)
        print("  - Instale distribution.cer no Mac, exporte NOVO .p12 e actualize CM_CERTIFICATE + password.", file=sys.stderr)
        print("  Ver: IOS/ATUALIZAR_APOS_NOVO_CERTIFICADO.txt", file=sys.stderr)
        return 1

    print("")
    print("OK: o .mobileprovision inclui o mesmo certificado Apple Distribution que o .p12.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
