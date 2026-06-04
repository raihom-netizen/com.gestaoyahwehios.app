# Retry em background das regras Firebase (503 API Google) — nao bloqueia deploy web/AAB.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')

$log = Join-Path $RepoRoot '.deploy-state\firebase-rules-background.log'
$lock = Join-Path $RepoRoot '.deploy-state\firebase-rules-background.lock'
$dir = Split-Path $log -Parent
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
if (Test-Path $lock) {
    $age = (Get-Date) - (Get-Item $lock).LastWriteTime
    if ($age.TotalMinutes -lt 120) {
        Write-Host "Background rules retry ja em curso (lock). Log: $log"
        exit 0
    }
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
Set-Content -Path $lock -Value (Get-Date).ToString('o') -Encoding UTF8

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $log -Value $line -Encoding UTF8
}

Write-Log 'Inicio retry background GCP REST (watchdog + deploy).'
& (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_watchdog.ps1') -StartBackground
& (Join-Path $RepoRoot 'scripts\deploy_firebase_rules.ps1') -ForcePublish -MaxAttempts 25 *>&1 | ForEach-Object {
    Write-Log $_
    Write-Host $_
}
$code = $LASTEXITCODE
Write-Log "Fim background exit=$code"
Remove-Item $lock -Force -ErrorAction SilentlyContinue
exit $code
