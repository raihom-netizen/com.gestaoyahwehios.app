# Gera ficheiros para colar na Codemagic (grupo appstore_credentials) — poucos ficheiros, estilo Controle Total.
# Saida: D:\Temporarios\gestao_yahweh_codemagic\ (NAO commite)
#
# Uso (raiz do repo):  .\scripts\encode_ios_codemagic_secrets.ps1
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$IOS = Join-Path $RepoRoot "IOS"
$OutDir = "D:\Temporarios\gestao_yahweh_codemagic"

if (-not (Test-Path $IOS)) {
    Write-Host "Pasta IOS nao encontrada: $IOS" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# Limpar saida antiga (nomes longos / duplicados de versoes anteriores)
Get-ChildItem -Path $OutDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like "COLAR___*" -or $_.Name -eq "CODEMAGIC___COLAR_NESTA_ORDEM.txt"
} | Remove-Item -Force -ErrorAction SilentlyContinue

function Write-Base64OneLine {
    param([string]$Path, [string]$DestTxt)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $b64 = [Convert]::ToBase64String($bytes)
    $b64One = ($b64 -replace "\r|\n", "")
    [IO.File]::WriteAllText($DestTxt, $b64One, [Text.UTF8Encoding]::new($false))
}

# --- P12 (Apple Distribution + chave privada) ---
$p12 = Get-ChildItem -Path $IOS -Filter "*.p12" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p12) {
    foreach ($name in @("com_gestaoyahwehiosapi", "gestaoyahwehiosapp", "distribution.p12")) {
        $fallback = Join-Path $IOS $name
        if (-not (Test-Path -LiteralPath $fallback)) { continue }
        if ($fallback -match '\.cer$') { continue }
        try {
            $head = [IO.File]::ReadAllBytes($fallback)
            if ($head.Length -ge 4 -and $head[0] -eq 0x30) {
                $p12 = Get-Item -LiteralPath $fallback
                break
            }
        } catch {}
    }
}

$prov = Get-ChildItem -Path $IOS -Filter "*.mobileprovision" -File -ErrorAction SilentlyContinue | Select-Object -First 1

$p8 = $null
$p8All = @(Get-ChildItem -Path $IOS -Filter "AuthKey_*.p8" -File -ErrorAction SilentlyContinue)
foreach ($c in $p8All) {
    if ($c.Name -match '85X9UNAT43') { $p8 = $c; break }
}
if (-not $p8 -and $p8All.Count -gt 0) {
    $p8 = $p8All | Sort-Object Name | Select-Object -First 1
    Write-Host "AVISO: Varias chaves .p8 em IOS - a usar $($p8.Name)." -ForegroundColor DarkYellow
}

$p12Out = Join-Path $OutDir "CM_CERTIFICATE_base64.txt"
$provOut = Join-Path $OutDir "CM_PROVISIONING_PROFILE_base64.txt"
$p8Out = Join-Path $OutDir "APP_STORE_CONNECT_PRIVATE_KEY.txt"
$readmeOut = Join-Path $OutDir "LEIA_CODEMAGIC.txt"

if (-not $prov) {
    Write-Host "ERRO: Nenhum .mobileprovision em $IOS" -ForegroundColor Red
    exit 1
}

Write-Base64OneLine -Path $prov.FullName -DestTxt $provOut

if ($p12) {
    $p12Bytes = [IO.File]::ReadAllBytes($p12.FullName)
    if ($p12Bytes.Length -lt 4 -or $p12Bytes[0] -ne 0x30) {
        Write-Host "AVISO: $($p12.Name) nao parece PKCS#12. Use export .p12 do Keychain." -ForegroundColor Yellow
    }
    Write-Base64OneLine -Path $p12.FullName -DestTxt $p12Out
    $p12Ok = $true
} else {
    $cer = Get-ChildItem -Path $IOS -Filter "distribution*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cer) { $cer = Get-ChildItem -Path $IOS -Filter "*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    $msg = @"
Falta .p12 (Apple Distribution + chave privada) em $IOS
O .cer nao substitui o P12. CM_PROVISIONING_PROFILE_base64.txt ja foi gerado.
Exporte .p12 (Mac) e volte a correr: .\scripts\encode_ios_codemagic_secrets.ps1
"@
    [IO.File]::WriteAllText((Join-Path $OutDir "FALTA_P12.txt"), $msg, [Text.UTF8Encoding]::new($false))
    Remove-Item -LiteralPath $p12Out -Force -ErrorAction SilentlyContinue
    Write-Host "AVISO: Sem .p12 — ver FALTA_P12.txt" -ForegroundColor Yellow
    $p12Ok = $false
}

if ($p8) {
    $pemText = [IO.File]::ReadAllText($p8.FullName, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($p8Out, $pemText.TrimEnd() + "`n", [Text.UTF8Encoding]::new($false))
} else {
    Write-Host "AVISO: Nenhum AuthKey_*.p8 em $IOS" -ForegroundColor Yellow
}

$issuerLine = "77a1debb-f68b-418d-9fe3-af0f37b40585"
$issuerSrc = Join-Path $IOS "app_store_connect_issuer_id.txt"
if (Test-Path -LiteralPath $issuerSrc) {
    $issuerLine = ([IO.File]::ReadAllText($issuerSrc, [Text.UTF8Encoding]::new($false))).Trim() -replace "\s+", ""
}

$keyIdLine = "85X9UNAT43"

$readme = @"
Codemagic → grupo appstore_credentials (copiar o CONTEUDO de cada .txt para o secret com o mesmo nome):

  APP_STORE_CONNECT_PRIVATE_KEY.txt     → APP_STORE_CONNECT_PRIVATE_KEY (multilinha)
  CM_PROVISIONING_PROFILE_base64.txt    → CM_PROVISIONING_PROFILE ou PROVISIONING_PROFILE (uma linha)
  CM_CERTIFICATE_base64.txt            → CERTIFICATE_PRIVATE_KEY ou CM_CERTIFICATE (uma linha; so se existir .p12)

  APP_STORE_CONNECT_KEY_IDENTIFIER ou KEY_ID na UI:  $keyIdLine
  APP_STORE_CONNECT_ISSUER_ID:  $issuerLine

  CM_CERTIFICATE_PASSWORD / CERTIFICATE_PASSWORD = senha do .p12 ou vazio

Pasta: $OutDir
Nao commite estes ficheiros.
"@
[IO.File]::WriteAllText($readmeOut, $readme.TrimStart(), [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "OK: $OutDir" -ForegroundColor Green
Write-Host "  LEIA_CODEMAGIC.txt"
Write-Host "  CM_PROVISIONING_PROFILE_base64.txt"
if ($p8) { Write-Host "  APP_STORE_CONNECT_PRIVATE_KEY.txt" }
if ($p12Ok) { Write-Host "  CM_CERTIFICATE_base64.txt" } else { Write-Host "  FALTA_P12.txt" }
