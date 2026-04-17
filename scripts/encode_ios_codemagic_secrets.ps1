# Gera ficheiros de texto com Base64 (uma linha) para colar na Codemagic:
#   CM_CERTIFICATE, CM_PROVISIONING_PROFILE
# Saida: D:\Temporarios\gestao_yahweh_codemagic\ (NAO commite estes ficheiros)
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

# Preferir *.p12; senao ficheiro sem extensao tipico do export (gestaoyahwehiosapp).
# NUNCA usar "distribution" .cer como P12 — causa "Unknown format in import" no Codemagic.
$p12 = Get-ChildItem -Path $IOS -Filter "*.p12" -File -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p12) {
    foreach ($name in @("com_gestaoyahwehiosapi", "gestaoyahwehiosapp")) {
        $fallback = Join-Path $IOS $name
        if (Test-Path -LiteralPath $fallback) {
            $p12 = Get-Item -LiteralPath $fallback
            break
        }
    }
}
$prov = Get-ChildItem -Path $IOS -Filter "*.mobileprovision" -File -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $p12) {
    $cer = Get-ChildItem -Path $IOS -Filter "distribution*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cer) { $cer = Get-ChildItem -Path $IOS -Filter "*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($cer) {
        Write-Host "AVISO: Existe $($cer.Name) — ficheiro .cer da Apple NAO serve como CERTIFICATE_PRIVATE_KEY (sem chave privada)." -ForegroundColor Yellow
        Write-Host "       No Mac: duplo clique no .cer → Keychain → exportar «Apple Distribution» + chave privada como .p12." -ForegroundColor Yellow
        Write-Host "       Ou: na Codemagic, após «Generate certificate», descarregue o pacote .p12 indicado pela equipa." -ForegroundColor Yellow
    }
    Write-Host "ERRO: Nenhum .p12 em $IOS (nome *.p12 ou com_gestaoyahwehiosapi sem extensao)." -ForegroundColor Red
    exit 1
}
if (-not $prov) {
    Write-Host "ERRO: Nenhum ficheiro .mobileprovision em $IOS" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

function Write-Base64OneLine {
    param([string]$Path, [string]$DestTxt)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $b64 = [Convert]::ToBase64String($bytes)
    $b64One = ($b64 -replace "\r|\n", "")
    [IO.File]::WriteAllText($DestTxt, $b64One, [Text.UTF8Encoding]::new($false))
}

$p12Out = Join-Path $OutDir "CM_CERTIFICATE_base64.txt"
$provOut = Join-Path $OutDir "CM_PROVISIONING_PROFILE_base64.txt"

# PKCS#12 DER costuma comecar por 0x30 (SEQUENCE); .cer sozinho falha no CI.
$p12Bytes = [IO.File]::ReadAllBytes($p12.FullName)
if ($p12Bytes.Length -lt 4 -or $p12Bytes[0] -ne 0x30) {
    Write-Host "AVISO: $($p12.Name) nao parece PKCS#12 (DER). Confirme que e export .p12 do Keychain, nao .cer." -ForegroundColor Yellow
}

Write-Base64OneLine -Path $p12.FullName -DestTxt $p12Out
Write-Base64OneLine -Path $prov.FullName -DestTxt $provOut

Write-Host ""
Write-Host "Origem:" -ForegroundColor Cyan
Write-Host "  P12:              $($p12.FullName)"
Write-Host "  Provisioning:     $($prov.FullName)"
Write-Host ""
Write-Host "Gerado (colar na Codemagic > appstore_credentials):" -ForegroundColor Green
Write-Host "  CM_CERTIFICATE            -> $p12Out"
Write-Host "  CM_PROVISIONING_PROFILE   -> $provOut"
Write-Host ""
Write-Host "Abra cada .txt no Notepad, Ctrl+A, Ctrl+C e cole no campo correspondente." -ForegroundColor Yellow
Write-Host "NAO commite estes ficheiros nem os cole em chats publicos." -ForegroundColor DarkYellow
