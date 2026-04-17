#!/usr/bin/env bash
# Gera PEM + CSR para Apple Distribution (macOS/Linux). Mesmo fluxo que o .ps1 no Windows.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/.local/ios-signing}"
mkdir -p "$OUT"
KEY="$OUT/distribution_private_key.pem"
CSR="$OUT/distribution_ios.csr"
if [[ -f "$KEY" ]]; then
  echo "AVISO: já existe $KEY — não sobrescrever (apague se quiser um novo par)."
  exit 2
fi
openssl genrsa -out "$KEY" 2048
openssl req -new -key "$KEY" -out "$CSR" -subj "/C=PT/O=GestaoYAHWEH/CN=Apple Distribution CSR"
chmod 600 "$KEY" "$CSR"
echo ""
echo "OK:"
echo "  $KEY"
echo "  $CSR"
echo ""
echo "1) developer.apple.com → Certificates → + → Apple Distribution → carregar o .csr"
echo "2) Codemagic → CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM = conteúdo completo de distribution_private_key.pem (Secret)"
echo "3) Profiles → perfil App Store → marcar este certificado Distribution"
echo ""
echo ".local/ está no .gitignore — não faça commit do .pem/.csr."
