# Gera ficheiros para colar na Codemagic (grupo appstore_credentials).
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
    foreach ($name in @("com_gestaoyahwehiosapi", "gestaoyahwehiosapp")) {
        $fallback = Join-Path $IOS $name
        if (Test-Path -LiteralPath $fallback) {
            $p12 = Get-Item -LiteralPath $fallback
            break
        }
    }
}

# --- Perfil App Store ---
$prov = Get-ChildItem -Path $IOS -Filter "*.mobileprovision" -File -ErrorAction SilentlyContinue | Select-Object -First 1

# --- AuthKey .p8 (App Store Connect API) ---
$p8 = Get-ChildItem -Path $IOS -Filter "AuthKey_*.p8" -File -ErrorAction SilentlyContinue | Select-Object -First 1

$p12Out = Join-Path $OutDir "CM_CERTIFICATE_base64.txt"
$provOut = Join-Path $OutDir "CM_PROVISIONING_PROFILE_base64.txt"
$p8Out = Join-Path $OutDir "APP_STORE_CONNECT_PRIVATE_KEY___COLAR_MULTILINHA.txt"
$readmeOut = Join-Path $OutDir "CODEMAGIC___COLAR_NESTA_ORDEM.txt"

if (-not $prov) {
    Write-Host "ERRO: Nenhum .mobileprovision em $IOS" -ForegroundColor Red
    exit 1
}

Write-Base64OneLine -Path $prov.FullName -DestTxt $provOut

if ($p12) {
    $p12Bytes = [IO.File]::ReadAllBytes($p12.FullName)
    if ($p12Bytes.Length -lt 4 -or $p12Bytes[0] -ne 0x30) {
        Write-Host "AVISO: $($p12.Name) nao parece PKCS#12 (DER). Confirme export .p12 do Keychain, nao .cer." -ForegroundColor Yellow
    }
    Write-Base64OneLine -Path $p12.FullName -DestTxt $p12Out
    $p12Ok = $true
} else {
    $cer = Get-ChildItem -Path $IOS -Filter "distribution*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cer) { $cer = Get-ChildItem -Path $IOS -Filter "*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    $msg = @"
FALTA FICHEIRO .p12 (Apple Distribution + chave privada).

Nao foi encontrado *.p12 em: $IOS
O ficheiro distribution.cer NAO substitui o P12 (nao tem chave privada).

O que fazer:
  1) Mac: Keychain → «Apple Distribution: Raihom Barbosa» → Exportar 2 itens → .p12
  2) Ou: Codemagic → equipa → certificado gerado → descarregar o .p12 indicado
  3) Coloque o .p12 em IOS\ e volte a correr: .\scripts\encode_ios_codemagic_secrets.ps1

O ficheiro CM_PROVISIONING_PROFILE_base64.txt JA FOI GERADO nesta pasta.
"@
    [IO.File]::WriteAllText((Join-Path $OutDir "AINDA_FALTA_P12___LER_ISTO.txt"), $msg, [Text.UTF8Encoding]::new($false))
    Remove-Item -LiteralPath $p12Out -Force -ErrorAction SilentlyContinue
    Write-Host 'AVISO: Sem .p12 - nao gerado CM_CERTIFICATE_base64.txt. Leia AINDA_FALTA_P12___LER_ISTO.txt.' -ForegroundColor Yellow
    $p12Ok = $false
}

if ($p8) {
    $pemText = [IO.File]::ReadAllText($p8.FullName, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($p8Out, $pemText.TrimEnd() + "`n", [Text.UTF8Encoding]::new($false))
} else {
    Write-Host "AVISO: Nenhum AuthKey_*.p8 em $IOS - nao gerado APP_STORE_CONNECT_PRIVATE_KEY." -ForegroundColor Yellow
}

$summary = @'
================================================================================
Colar na Codemagic - Application - Environment variables - grupo appstore_credentials
================================================================================

[1] APP_STORE_CONNECT_PRIVATE_KEY
    Abrir: APP_STORE_CONNECT_PRIVATE_KEY___COLAR_MULTILINHA.txt
    Copiar TUDO desde -----BEGIN ate -----END inclusive - colar no secret multilinha.

[2] APP_STORE_CONNECT_KEY_IDENTIFIER / KEY_ID
    Valor no codemagic.yaml: 55BABQVL48

[3] APP_STORE_CONNECT_ISSUER_ID
    77a1debb-f68b-418d-9fe3-af0f37b40585

[4] CM_PROVISIONING_PROFILE
    Abrir: CM_PROVISIONING_PROFILE_base64.txt - UMA linha Base64 - colar.

[5] CERTIFICATE_PRIVATE_KEY  (mesmo conteudo que CM_CERTIFICATE_base64)
    Abrir: CM_CERTIFICATE_base64.txt - UMA linha Base64 - colar.
    So existe se tiver ficheiro .p12 em IOS; senao leia AINDA_FALTA_P12___LER_ISTO.txt

[6] CM_CERTIFICATE_PASSWORD
    Senha definida ao exportar o .p12 ou vazio.

NAO commite estes ficheiros nem os partilhe em chats publicos.
================================================================================
'@
[IO.File]::WriteAllText($readmeOut, $summary, [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Gerado em: $OutDir" -ForegroundColor Green
Write-Host "  CM_PROVISIONING_PROFILE_base64.txt"
if ($p8) { Write-Host "  APP_STORE_CONNECT_PRIVATE_KEY___COLAR_MULTILINHA.txt" }
if ($p12Ok) {
    Write-Host "  CM_CERTIFICATE_base64.txt"
} else {
    Write-Host "  AINDA_FALTA_P12___LER_ISTO.txt  (sem P12 ainda)"
}
Write-Host "  CODEMAGIC___COLAR_NESTA_ORDEM.txt"
Write-Host ""
Write-Host 'Abra CODEMAGIC___COLAR_NESTA_ORDEM.txt para a ordem dos secrets.' -ForegroundColor Cyan
