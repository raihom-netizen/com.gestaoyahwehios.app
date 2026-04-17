# Gera chave RSA 2048 (PEM) + CSR para certificado Apple Distribution (App Store / TestFlight).
# O PEM é o valor do secret Codemagic CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM (o MESMO em todos os builds).
#
# Uso:
#   .\scripts\gen_ios_distribution_csr_private_key_pem.ps1
#   .\scripts\gen_ios_distribution_csr_private_key_pem.ps1 -OutDir "D:\temporarios"
#
# Depois: developer.apple.com Certificates + Apple Distribution (upload do .csr)
#         Codemagic: CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM = conteudo do .pem
param(
    [string]$OutDir = ""
)
$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path (Join-Path $repoRoot ".local") "ios-signing"
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$keyPem = Join-Path $OutDir "distribution_private_key.pem"
$csrOut = Join-Path $OutDir "distribution_ios.csr"

$openssl = $null
if (Get-Command openssl -ErrorAction SilentlyContinue) { $openssl = "openssl" }
if (-not $openssl) {
    foreach ($p in @(
        "${env:ProgramFiles}\Git\usr\bin\openssl.exe",
        "${env:ProgramFiles(x86)}\Git\usr\bin\openssl.exe"
    )) {
        if (Test-Path $p) { $openssl = $p; break }
    }
}
if (-not $openssl) {
    Write-Host "ERRO: openssl nao encontrado (instale Git for Windows ou OpenSSL)." -ForegroundColor Red
    exit 1
}

if (Test-Path $keyPem) {
    Write-Host "AVISO: ja existe $keyPem - nao sobrescrever (apague manualmente se quiser gerar outro par)." -ForegroundColor Yellow
    exit 2
}

& $openssl genrsa -out $keyPem 2048
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Subject mínimo aceite pela Apple para CSR de Distribution
$subj = "/C=PT/O=GestaoYAHWEH/CN=GestaoYAHWEH-Distribution-CSR"
& $openssl req -new -key $keyPem -out $csrOut -subj $subj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ""
Write-Host "OK: ficheiros gerados em:" -ForegroundColor Green
Write-Host "  $keyPem"
Write-Host "  $csrOut"
Write-Host ""
Write-Host "1) Apple Developer: Certificates, +, Apple Distribution, carregar o .csr acima." -ForegroundColor Cyan
Write-Host "2) Codemagic: app, Environment variables (grupo appstore_credentials):" -ForegroundColor Cyan
Write-Host "   CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM = conteudo COMPLETO de distribution_private_key.pem (multilinha, Secret)." -ForegroundColor Cyan
Write-Host "3) Profiles: perfil App Store do bundle, editar, marcar este certificado Distribution." -ForegroundColor Cyan
Write-Host ""
Write-Host "Esta pasta .local/ esta no .gitignore - nao commite o .pem nem o .csr." -ForegroundColor Yellow
