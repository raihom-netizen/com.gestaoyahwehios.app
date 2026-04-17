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
# NUNCA usar .cer (so certificado publico) - so *.p12 ou ficheiro sem extensao PKCS#12.
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

# --- Perfil App Store ---
$prov = Get-ChildItem -Path $IOS -Filter "*.mobileprovision" -File -ErrorAction SilentlyContinue | Select-Object -First 1

# --- AuthKey .p8: preferir a chave alinhada ao codemagic.yaml (85X9UNAT43) se existir ---
$p8 = $null
$p8All = @(Get-ChildItem -Path $IOS -Filter "AuthKey_*.p8" -File -ErrorAction SilentlyContinue)
foreach ($c in $p8All) {
    if ($c.Name -match '85X9UNAT43') { $p8 = $c; break }
}
if (-not $p8 -and $p8All.Count -gt 0) {
    $p8 = $p8All | Sort-Object Name | Select-Object -First 1
    Write-Host "AVISO: Varias chaves .p8 em IOS - a usar $($p8.Name). Alinhe o codemagic.yaml ao mesmo Key ID." -ForegroundColor DarkYellow
}

$p12Out = Join-Path $OutDir "CM_CERTIFICATE_base64.txt"
$provOut = Join-Path $OutDir "CM_PROVISIONING_PROFILE_base64.txt"
$p8Out = Join-Path $OutDir "APP_STORE_CONNECT_PRIVATE_KEY___COLAR_MULTILINHA.txt"
$readmeOut = Join-Path $OutDir "CODEMAGIC___COLAR_NESTA_ORDEM.txt"
# Nomes explícitos: abrir, Ctrl+A, Ctrl+C, colar no secret correspondente (só o conteúdo do ficheiro).
$colarP12 = Join-Path $OutDir "COLAR___CERTIFICATE_PRIVATE_KEY_ou_CM_CERTIFICATE__uma_linha.txt"
$colarProv = Join-Path $OutDir "COLAR___CM_PROVISIONING_PROFILE__uma_linha.txt"
$colarP8 = Join-Path $OutDir "COLAR___APP_STORE_CONNECT_PRIVATE_KEY__multilinha.txt"
$colarGuia = Join-Path $OutDir "COLAR___GUIA_CODEMAGIC.txt"

if (-not $prov) {
    Write-Host "ERRO: Nenhum .mobileprovision em $IOS" -ForegroundColor Red
    exit 1
}

Write-Base64OneLine -Path $prov.FullName -DestTxt $provOut
Copy-Item -LiteralPath $provOut -Destination $colarProv -Force

if ($p12) {
    $p12Bytes = [IO.File]::ReadAllBytes($p12.FullName)
    if ($p12Bytes.Length -lt 4 -or $p12Bytes[0] -ne 0x30) {
        Write-Host "AVISO: $($p12.Name) nao parece PKCS#12 (DER). Confirme export .p12 do Keychain, nao .cer." -ForegroundColor Yellow
    }
    Write-Base64OneLine -Path $p12.FullName -DestTxt $p12Out
    Copy-Item -LiteralPath $p12Out -Destination $colarP12 -Force
    $p12Ok = $true
} else {
    Remove-Item -LiteralPath $colarP12 -Force -ErrorAction SilentlyContinue
    $cer = Get-ChildItem -Path $IOS -Filter "distribution*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cer) { $cer = Get-ChildItem -Path $IOS -Filter "*.cer" -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
    $msg = @"
FALTA FICHEIRO .p12 (Apple Distribution + chave privada).

Pasta: $IOS
O ficheiro distribution.cer NAO substitui o P12 (nao tem chave privada).

O que fazer:
  - Mac Keychain: exportar Apple Distribution como .p12 (certificado + chave privada)
  - Ou Codemagic equipa: descarregar o .p12 do certificado gerado
  - Depois correr de novo: .\scripts\encode_ios_codemagic_secrets.ps1

CM_PROVISIONING_PROFILE_base64.txt nesta pasta JA foi gerado.
"@
    [IO.File]::WriteAllText((Join-Path $OutDir "AINDA_FALTA_P12___LER_ISTO.txt"), $msg, [Text.UTF8Encoding]::new($false))
    Remove-Item -LiteralPath $p12Out -Force -ErrorAction SilentlyContinue
    Write-Host 'AVISO: Sem .p12 - nao gerado CM_CERTIFICATE_base64.txt. Leia AINDA_FALTA_P12___LER_ISTO.txt.' -ForegroundColor Yellow
    $p12Ok = $false
}

if ($p8) {
    $pemText = [IO.File]::ReadAllText($p8.FullName, [Text.UTF8Encoding]::new($false))
    $pemTrim = $pemText.TrimEnd() + "`n"
    [IO.File]::WriteAllText($p8Out, $pemTrim, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($colarP8, $pemTrim, [Text.UTF8Encoding]::new($false))
} else {
    Remove-Item -LiteralPath $colarP8 -Force -ErrorAction SilentlyContinue
    Write-Host "AVISO: Nenhum AuthKey_*.p8 em $IOS - nao gerado APP_STORE_CONNECT_PRIVATE_KEY." -ForegroundColor Yellow
}

$issuerLine = "77a1debb-f68b-418d-9fe3-af0f37b40585"
$issuerSrc = Join-Path $IOS "app_store_connect_issuer_id.txt"
if (Test-Path -LiteralPath $issuerSrc) {
    $issuerLine = ([IO.File]::ReadAllText($issuerSrc, [Text.UTF8Encoding]::new($false))).Trim() -replace "\s+", ""
}
$issuerRefOut = Join-Path $OutDir "COLAR___APP_STORE_CONNECT_ISSUER_ID__uma_linha.txt"
[IO.File]::WriteAllText($issuerRefOut, $issuerLine + "`n", [Text.UTF8Encoding]::new($false))

$summary = @"
================================================================================
Codemagic - Application - Environment variables - grupo appstore_credentials
================================================================================

Ficheiros prontos a copiar/colar (conteudo = so o que esta dentro do .txt):

  COLAR___APP_STORE_CONNECT_PRIVATE_KEY__multilinha.txt
    -> Secret: APP_STORE_CONNECT_PRIVATE_KEY (multilinha, Secret)

  COLAR___APP_STORE_CONNECT_ISSUER_ID__uma_linha.txt  (uma linha; lido de IOS\\app_store_connect_issuer_id.txt se existir)
    -> Secret: APP_STORE_CONNECT_ISSUER_ID

  COLAR___CERTIFICATE_PRIVATE_KEY_ou_CM_CERTIFICATE__uma_linha.txt  (se existir .p12 em IOS)
    -> Secret: CERTIFICATE_PRIVATE_KEY  OU  CM_CERTIFICATE  (o mesmo valor Base64, uma linha)

  COLAR___CM_PROVISIONING_PROFILE__uma_linha.txt
    -> Secret: CM_PROVISIONING_PROFILE  OU  PROVISIONING_PROFILE

  APP_STORE_CONNECT_KEY_IDENTIFIER = 85X9UNAT43  (digitar manualmente ou ja no codemagic.yaml)

  APP_STORE_CONNECT_ISSUER_ID = $issuerLine  (ou copiar de COLAR___APP_STORE_CONNECT_ISSUER_ID__uma_linha.txt se existir)

  CM_CERTIFICATE_PASSWORD / CERTIFICATE_PASSWORD = senha do .p12 ou vazio

Copias legadas (mesmo conteudo):
  CM_CERTIFICATE_base64.txt | CM_PROVISIONING_PROFILE_base64.txt | APP_STORE_CONNECT_PRIVATE_KEY___COLAR_MULTILINHA.txt

NAO commite D:\\Temporarios\\gestao_yahweh_codemagic nem partilhe estes ficheiros.
================================================================================
"@
[IO.File]::WriteAllText($readmeOut, $summary, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($colarGuia, $summary, [Text.UTF8Encoding]::new($false))

Write-Host ""
Write-Host "Gerado em: $OutDir" -ForegroundColor Green
Write-Host "  (copiar SO o conteudo de cada ficheiro, uma variavel por secret)"
Write-Host "  COLAR___CM_PROVISIONING_PROFILE__uma_linha.txt"
if ($p8) {
    Write-Host "  COLAR___APP_STORE_CONNECT_PRIVATE_KEY__multilinha.txt"
}
Write-Host "  COLAR___APP_STORE_CONNECT_ISSUER_ID__uma_linha.txt"
if ($p12Ok) {
    Write-Host "  COLAR___CERTIFICATE_PRIVATE_KEY_ou_CM_CERTIFICATE__uma_linha.txt"
} else {
    Write-Host "  AINDA_FALTA_P12___LER_ISTO.txt  (sem P12 em IOS - falta export .p12)"
}
Write-Host "  COLAR___GUIA_CODEMAGIC.txt  (instrucoes)"
Write-Host ""
Write-Host 'Abra COLAR___GUIA_CODEMAGIC.txt (a pasta abre no Explorador).' -ForegroundColor Cyan
try { Start-Process "explorer.exe" -ArgumentList $OutDir } catch {}
