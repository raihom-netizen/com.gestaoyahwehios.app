# Publica regras Firestore em 2 etapas: SIMPLES -> COMPLETA.
# Motivo: firebaserules.googleapis.com aceita melhor ruleset pequeno primeiro (evita 503/hang).
# Memoria: .cursor/rules/firestore-rules-publicar-duas-etapas.mdc
#
# Uso (raiz, com pedido explicito do utilizador):
#   .\scripts\deploy_firebase_rules_duas_etapas.ps1
#   .\scripts\deploy_firebase_rules_duas_etapas.ps1 -ForcePublish -IncludeStorage

param(
    [switch] $ForcePublish,
    [switch] $IncludeStorage,
    [switch] $SkipIndexes,
    [string] $Project = 'gestaoyahweh-21e23'
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$fullRules = Join-Path $RepoRoot 'firestore.rules'
$simpleRules = Join-Path $RepoRoot 'firestore.rules.simple'
$backupDir = 'D:\TEMPORARIOS\yh_rules_bridge'
$backupFile = Join-Path $backupDir ("firestore.rules.full_{0:yyyyMMdd_HHmmss}.bak" -f (Get-Date))
$nodePublish = Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs'
$keyPath = Join-Path $RepoRoot 'gestaoyahweh-gcp-deploy-key.json'

if (-not (Test-Path $fullRules)) { throw "Falta firestore.rules" }
if (-not (Test-Path $simpleRules)) { throw "Falta firestore.rules.simple (bridge)" }
if (-not (Test-Path $nodePublish)) { throw "Falta firebase_rules_gcp_publish.cjs" }

New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
Copy-Item -LiteralPath $fullRules -Destination $backupFile -Force
Write-Host "Backup regras completas: $backupFile" -ForegroundColor DarkGray

if (Test-Path $keyPath) {
    $env:GOOGLE_APPLICATION_CREDENTIALS = $keyPath
}

function Invoke-GcpFirestorePublish {
    param([string] $Label)
    Write-Host "`n=== Etapa: $Label ===" -ForegroundColor Cyan
    $forceFlags = @('--force', '--force-republish', '--only=firestore', '--max-attempts=40')
    # Node escreve progresso em stderr — nao tratar como erro terminante do PowerShell.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & node $nodePublish $Project @forceFlags 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            Write-Host $_.ToString()
        } else {
            Write-Host $_
        }
    }
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    if ($code -ne 0) {
        throw "Falha ao publicar Firestore ($Label). exit=$code"
    }
}

$restored = $false
try {
    Write-Host "=== 2 etapas Firestore rules (simples -> completa) | projeto $Project ===" -ForegroundColor Yellow
    Write-Host "ATENCAO: entre as etapas o release pode ficar no bridge (allow false). Completar logo a seguir." -ForegroundColor DarkYellow

    # [1] Bridge simples
    Copy-Item -LiteralPath $simpleRules -Destination $fullRules -Force
    Invoke-GcpFirestorePublish -Label 'SIMPLES (bridge)'

    # Quota GCP ~1 req/min — pausa antes do ruleset completo
    $gapSec = [int]($env:YAHWEH_RULES_MIN_GAP_SEC)
    if ($gapSec -lt 70) { $gapSec = 75 }
    Write-Host "Aguardar ${gapSec}s (quota firebaserules) antes da completa..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $gapSec

    # [2] Completa (restaurar ficheiro oficial)
    Copy-Item -LiteralPath $backupFile -Destination $fullRules -Force
    $restored = $true
    Invoke-GcpFirestorePublish -Label 'COMPLETA (oficial)'

    Write-Host "`nFirestore rules: 2 etapas OK." -ForegroundColor Green
}
catch {
    Write-Host "`nERRO nas 2 etapas: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
finally {
    if (-not $restored -and (Test-Path $backupFile)) {
        Copy-Item -LiteralPath $backupFile -Destination $fullRules -Force
        Write-Host "Ficheiro local restaurado para firestore.rules COMPLETO (backup)." -ForegroundColor Yellow
        Write-Host "Se a etapa SIMPLES ja tinha ido para o release remoto, REPUBLIQUE a completa ja:" -ForegroundColor Yellow
        Write-Host "  .\scripts\deploy_firebase_rules.ps1 -ForcePublish" -ForegroundColor Yellow
    }
}

# Storage + indexes via script existente (opcional)
$deployRules = Join-Path $RepoRoot 'scripts\deploy_firebase_rules.ps1'
if ($IncludeStorage -or -not $SkipIndexes) {
    $extra = @()
    if ($ForcePublish) { $extra += '-ForcePublish' }
    if ($IncludeStorage -and $SkipIndexes) {
        Write-Host "`n=== Storage via deploy_firebase_rules (-OnlyStorage se existir) ===" -ForegroundColor Cyan
    }
    Write-Host "`n=== Seguir storage/indexes (deploy_firebase_rules) ===" -ForegroundColor Cyan
    & $deployRules @extra
    if ($LASTEXITCODE -ne 0) {
        Write-Host "AVISO: storage/indexes nao concluido (exit $LASTEXITCODE). Firestore completa ja publicada." -ForegroundColor DarkYellow
        exit $LASTEXITCODE
    }
}

Write-Host "`nConcluido: simples -> completa (+ extras)." -ForegroundColor Green
