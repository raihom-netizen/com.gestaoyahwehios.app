# Gera 3 ficheiros para colar na Codemagic (grupo appstore_credentials):
#   APP_STORE_CONNECT_PRIVATE_KEY - conteudo PEM do .p8
#   APP_STORE_CONNECT_KEY_IDENTIFIER - Key ID (do nome AuthKey_XXXXX.p8)
#   APP_STORE_CONNECT_ISSUER_ID - Issuer UUID (IOS\app_store_connect_issuer_id.txt ou defeito)
#
# Por defeito: IOS na raiz do repo + saida D:\temporarios
# Uso (na raiz): .\scripts\export_app_store_connect_secrets_to_d_temporarios.ps1

param(
    [string] $IosDir = "",
    [string] $OutDir = "D:\temporarios"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($IosDir)) {
    $IosDir = Join-Path $RepoRoot "IOS"
}
if (-not (Test-Path $IosDir)) {
    Write-Host "ERRO: pasta IOS nao encontrada: $IosDir" -ForegroundColor Red
    exit 1
}

$p8 = Get-ChildItem -Path $IosDir -Filter "AuthKey_*.p8" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p8) {
    Write-Host "ERRO: nenhum AuthKey_*.p8 em $IosDir. Confirme que o .p8 existe em IOS (gitignore)." -ForegroundColor Red
    exit 1
}

if ($p8.BaseName -notmatch '^AuthKey_(.+)$') {
    Write-Host "ERRO: nome esperado AuthKey_KEYID.p8. Obtido: $($p8.Name)" -ForegroundColor Red
    exit 1
}
$keyId = $Matches[1].Trim()

$issuerFile = Join-Path $IosDir "app_store_connect_issuer_id.txt"
if (Test-Path $issuerFile) {
    $issuer = (Get-Content -LiteralPath $issuerFile -Raw -Encoding UTF8).Trim()
} else {
    $issuer = "77a1debb-f68b-418d-9fe3-af0f37b40585"
    Write-Host "AVISO: usando Issuer por defeito. Crie IOS\app_store_connect_issuer_id.txt para personalizar." -ForegroundColor Yellow
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$pemRaw = Get-Content -LiteralPath $p8.FullName -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($pemRaw)) {
    Write-Host "ERRO: $($p8.Name) esta vazio." -ForegroundColor Red
    exit 1
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$outPem = Join-Path $OutDir "APP_STORE_CONNECT_PRIVATE_KEY.txt"
$outKey = Join-Path $OutDir "APP_STORE_CONNECT_KEY_IDENTIFIER.txt"
$outIss = Join-Path $OutDir "APP_STORE_CONNECT_ISSUER_ID.txt"

[System.IO.File]::WriteAllText($outPem, $pemRaw.TrimEnd() + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText($outKey, $keyId + "`n", $utf8NoBom)
[System.IO.File]::WriteAllText($outIss, $issuer + "`n", $utf8NoBom)

Write-Host ""
Write-Host "OK: ficheiros gerados em $OutDir" -ForegroundColor Green
Write-Host "  $outPem"
Write-Host "  $outKey"
Write-Host "  $outIss"
Write-Host ""
Write-Host "Codemagic: cole o conteudo de cada ficheiro no secret com o mesmo nome (grupo appstore_credentials)." -ForegroundColor Cyan
Write-Host "  APP_STORE_CONNECT_PRIVATE_KEY = PEM completo (BEGIN/END)." -ForegroundColor DarkGray
