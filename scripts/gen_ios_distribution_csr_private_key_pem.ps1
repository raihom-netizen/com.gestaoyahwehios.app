# Gera uma chave RSA 2048 (PEM) para usar no Codemagic como CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM
# (fetch-signing-files --certificate-key). Guarde o MESMO secret em todos os builds.
# Saida por defeito: D:\temporarios\CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM.txt
param([string]$OutDir = "D:\temporarios")
$ErrorActionPreference = "Stop"
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$out = Join-Path $OutDir "CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM.txt"
$openssl = "openssl"
if (-not (Get-Command $openssl -ErrorAction SilentlyContinue)) {
    Write-Host "ERRO: openssl nao encontrado no PATH." -ForegroundColor Red
    exit 1
}
& $openssl genrsa -out $out 2048
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "OK: $out" -ForegroundColor Green
Write-Host "Codemagic: novo secret CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM = conteudo completo deste ficheiro (PEM)." -ForegroundColor Cyan
