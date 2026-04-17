# Gera ficheiros em %TEMP% para colar na Codemagic (secrets) a partir do output do bootstrap.
# Uso (na pasta IOS):  .\prepare_codemagic_paste_from_bootstrap.ps1
# Ou:  .\prepare_codemagic_paste_from_bootstrap.ps1 -BootstrapDir "C:\caminho\bootstrap_signing_output"

param(
    [string] $BootstrapDir = ""
)

$ErrorActionPreference = "Stop"
$IosRoot = $PSScriptRoot
if (-not $BootstrapDir) {
    $BootstrapDir = Join-Path $IosRoot "bootstrap_signing_output"
}

$p12Candidates = @(
    (Join-Path $BootstrapDir "bootstrap_identity.p12"),
    (Join-Path $BootstrapDir "bootstrap_identity")
)
$pemPath = Join-Path $BootstrapDir "distribution_private_key.pem"

if (-not (Test-Path $pemPath)) {
    Write-Host "ERRO: nao encontrado: $pemPath" -ForegroundColor Red
    Write-Host "  Extraia o ZIP do Codemagic para IOS\bootstrap_signing_output ou passe -BootstrapDir" -ForegroundColor Yellow
    exit 1
}

$p12Path = $null
foreach ($c in $p12Candidates) {
    if (Test-Path $c) { $p12Path = $c; break }
}
if (-not $p12Path) {
    Write-Host "AVISO: P12 nao encontrado (bootstrap_identity.p12). So sera gerado o PEM." -ForegroundColor Yellow
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outRoot = Join-Path $env:TEMP "GestaoYahweh_codemagic_paste_$stamp"
New-Item -ItemType Directory -Path $outRoot -Force | Out-Null

# 1) PEM — secret multilinha na Codemagic
$destPem = Join-Path $outRoot "01_CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM.txt"
Copy-Item -LiteralPath $pemPath -Destination $destPem -Force

# 2) P12 Base64 uma linha (opcional: modo manual CM_CERTIFICATE)
if ($p12Path) {
    $bytes = [System.IO.File]::ReadAllBytes($p12Path)
    $b64 = [Convert]::ToBase64String($bytes)
    $destB64 = Join-Path $outRoot "02_CM_CERTIFICATE_bootstrap_identity_BASE64_uma_linha.txt"
    Set-Content -Path $destB64 -Value $b64 -Encoding ASCII -NoNewline
}

# 3) Senha do P12 gerado pelo bootstrap (fixo no script Python se nao mudou CM_API_ONLY_IMPORT_P12_PASSWORD)
$bootstrapP12Password = "cm_yw_bootstrap_dist_1"
$destPw = Join-Path $outRoot "03_CM_CERTIFICATE_PASSWORD_uma_linha.txt"
Set-Content -Path $destPw -Value $bootstrapP12Password -Encoding UTF8 -NoNewline

$readme = @"
================================================================================
GESTAO YAHWEH — Colar na Codemagic (grupo: appstore_credentials)
Pasta gerada: $outRoot
================================================================================

A) OBRIGATORIO para API-only / import da chave Distribution no CI
   Variavel:  CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM  (tipo: Secret)
   Valor:     Abra o ficheiro 01_CM_DISTRIBUTION_CERT_PRIVATE_KEY_PEM.txt
              Copie TUDO (desde -----BEGIN ate -----END inclusive).
              Cole no campo do secret na Codemagic (aceita multilinhas).

B) OPCIONAL — modo manual (alternativa ao PEM + API)
   Se preferir P12 + perfil em vez de depender do PEM na API:
   CM_CERTIFICATE  = conteudo UMA linha do ficheiro 02_...BASE64...
   CM_CERTIFICATE_PASSWORD = conteudo do ficheiro 03_... (uma linha)
   CM_PROVISIONING_PROFILE = Base64 do .mobileprovision App Store (se ainda nao tiver no grupo)

C) Depois de guardar os secrets
   Codemagic → Start new build → workflow  iOS Build - Gestao YAHWEH (TestFlight)
   NAO volte a correr o workflow de Bootstrap salvo necessidade (limite Apple ~3 certs Distribution).

D) Seguranca
   Apague esta pasta em %TEMP% quando terminar ou nao partilhe estes ficheiros.
   NAO faca commit de bootstrap_signing_output no Git.
================================================================================
"@
$readmePath = Join-Path $outRoot "00_LEIA_PRIMEIRO.txt"
Set-Content -Path $readmePath -Value $readme -Encoding UTF8

try {
    Set-Clipboard -Path $destPem
    $clipMsg = "Clipboard: conteudo de 01_... (PEM) copiado para a area de transferencia."
} catch {
    $clipMsg = "Clipboard: nao foi possivel copiar automaticamente; abra 01_... manualmente."
}

Write-Host ""
Write-Host "OK. Ficheiros prontos em:" -ForegroundColor Green
Write-Host "  $outRoot" -ForegroundColor Cyan
Write-Host ""
Write-Host $clipMsg -ForegroundColor DarkGray
Write-Host "Abra o Explorador de ficheiros..." -ForegroundColor Green
Start-Process explorer.exe -ArgumentList $outRoot
