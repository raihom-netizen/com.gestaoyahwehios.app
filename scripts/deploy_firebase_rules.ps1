# Deploy Firestore (rules + indexes) + Storage rules — Gestão YAHWEH
# Execute na raiz do repo:  .\scripts\deploy_firebase_rules.ps1
# Re-tenta automaticamente em falhas transitórias (ex.: HTTP 503 nas Rules API).
# Parâmetro opcional: -MaxAttempts 6
param(
    [int] $MaxAttempts = 6
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Test-Path (Join-Path $RepoRoot "firebase.json"))) {
    Write-Host "Erro: firebase.json nao encontrado na raiz: $RepoRoot" -ForegroundColor Red
    exit 1
}

# Backoff entre tentativas (segundos)
$BackoffSec = @(8, 15, 30, 45, 60, 90)

function Test-FirebaseRulesDeployNonRetryable {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return $false }
    $t = $OutputText.ToLowerInvariant()
    if ($t -match 'requires login|please login|not logged in|authentication error|invalid credentials|invalid grant') {
        return $true
    }
    if ($t -match 'could not find rules|rules file.*not found|project not found|invalid project') {
        return $true
    }
    return $false
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "=== firebase deploy --only firestore,storage (tentativa $attempt de $MaxAttempts) ===" -ForegroundColor Cyan
    Write-Host "Projeto: .firebaserc na raiz" -ForegroundColor DarkGray

    $lines = & firebase deploy --only "firestore,storage" 2>&1
    foreach ($line in $lines) {
        Write-Host $line
    }
    $text = ($lines | Out-String)
    $exit = $LASTEXITCODE

    if ($exit -eq 0) {
        Write-Host "`n=== Concluido | Firestore (rules + indexes) + Storage rules ===" -ForegroundColor Green
        Write-Host "Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview" -ForegroundColor DarkGray
        exit 0
    }

    if (Test-FirebaseRulesDeployNonRetryable -OutputText $text) {
        Write-Host "`nErro nao recuperavel (login/projeto/regras); nao ha mais retries." -ForegroundColor Red
        exit $exit
    }

    if ($attempt -ge $MaxAttempts) {
        Write-Host "`nEsgotadas as $MaxAttempts tentativas (exit $exit)." -ForegroundColor Red
        exit $exit
    }

    $idx = [Math]::Min($attempt - 1, $BackoffSec.Length - 1)
    $wait = $BackoffSec[$idx]
    Write-Host "`nFalha transitória provavel (ex. 503). Aguardar ${wait}s antes da proxima tentativa..." -ForegroundColor Yellow
    Start-Sleep -Seconds $wait
}

exit 1
