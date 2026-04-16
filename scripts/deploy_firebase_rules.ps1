# Deploy Firestore (rules + indexes) + Storage rules — Gestão YAHWEH
# Execute na raiz do repo:  .\scripts\deploy_firebase_rules.ps1
# Re-tenta falhas transitórias (503/409/429 na Rules API, timeouts).
# Fallback: se o deploy combinado falhar, tenta Firestore e depois Storage em separado (menos pressão na API).
# Parâmetro: -MaxAttempts 10 (padrão)

param(
    [int] $MaxAttempts = 10
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Test-Path (Join-Path $RepoRoot "firebase.json"))) {
    Write-Host "Erro: firebase.json nao encontrado na raiz: $RepoRoot" -ForegroundColor Red
    exit 1
}

# Backoff entre rodadas completas (segundos) — alarga até ~15 min no total
$BackoffSec = @(8, 15, 30, 45, 60, 90, 120, 120, 180, 180)

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

function Test-FirebaseRulesDeployTransient {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return $false }
    $t = $OutputText.ToLowerInvariant()
    if ($t -match '503|504|429|409|service is currently unavailable|unavailable|timeout|timed out|econnreset|try again') {
        return $true
    }
    return $false
}

function Invoke-FirebaseDeployCombined {
    $lines = & firebase deploy --only "firestore,storage" 2>&1
    foreach ($line in $lines) { Write-Host $line }
    $text = ($lines | Out-String)
    return @{ Exit = $LASTEXITCODE; Text = $text }
}

function Invoke-FirebaseDeploySequential {
    Write-Host "   (fallback) firebase deploy --only firestore ..." -ForegroundColor DarkYellow
    $a = & firebase deploy --only firestore 2>&1
    foreach ($line in $a) { Write-Host $line }
    $textA = ($a | Out-String)
    if ($LASTEXITCODE -ne 0) {
        return @{ Exit = $LASTEXITCODE; Text = $textA }
    }
    Write-Host "   (fallback) firebase deploy --only storage ..." -ForegroundColor DarkYellow
    $b = & firebase deploy --only storage 2>&1
    foreach ($line in $b) { Write-Host $line }
    $textB = $textA + ($b | Out-String)
    return @{ Exit = $LASTEXITCODE; Text = $textB }
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "=== firebase deploy rules (tentativa $attempt de $MaxAttempts) ===" -ForegroundColor Cyan
    Write-Host "Projeto: .firebaserc na raiz | 1) firestore+storage  2) fallback firestore -> storage" -ForegroundColor DarkGray

    $r = Invoke-FirebaseDeployCombined
    $text = $r.Text
    $exit = $r.Exit

    if ($exit -eq 0) {
        Write-Host "`n=== Concluido | Firestore (rules + indexes) + Storage rules ===" -ForegroundColor Green
        Write-Host "Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview" -ForegroundColor DarkGray
        exit 0
    }

    if (Test-FirebaseRulesDeployNonRetryable -OutputText $text) {
        Write-Host "`nErro nao recuperavel (login/projeto/regras); nao ha mais retries." -ForegroundColor Red
        exit $exit
    }

    # Combinado falhou: tentar sequencial (ajuda em 503/409 parciais na API de rules)
    if ($exit -ne 0) {
        $r2 = Invoke-FirebaseDeploySequential
        $text = $text + $r2.Text
        $exit = $r2.Exit
        if ($exit -eq 0) {
            Write-Host "`n=== Concluido (fallback sequencial) | Firestore + Storage ===" -ForegroundColor Green
            Write-Host "Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview" -ForegroundColor DarkGray
            exit 0
        }
    }

    if (Test-FirebaseRulesDeployNonRetryable -OutputText $text) {
        Write-Host "`nErro nao recuperavel apos fallback; nao ha mais retries." -ForegroundColor Red
        exit $exit
    }

    if ($attempt -ge $MaxAttempts) {
        Write-Host "`nEsgotadas as $MaxAttempts tentativas (exit $exit)." -ForegroundColor Red
        exit $exit
    }

    $idx = [Math]::Min($attempt - 1, $BackoffSec.Length - 1)
    $wait = $BackoffSec[$idx]
    $transient = Test-FirebaseRulesDeployTransient -OutputText $text
    $reason = if ($transient) { "API indisponivel / limite / conflito temporario" } else { "deploy falhou" }
    Write-Host "`n$reason - aguardar ${wait}s antes da proxima tentativa..." -ForegroundColor Yellow
    Start-Sleep -Seconds $wait
}

exit 1
