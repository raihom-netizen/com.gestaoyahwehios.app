# Watchdog: republica regras via GCP REST ate sucesso (503 Google).
# Uso: .\scripts\firebase_rules_gcp_watchdog.ps1 -StartBackground

param(
    [switch] $StartBackground,
    [int] $IntervalMinutes = 15
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$publish = Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs'
$log = Join-Path $RepoRoot '.deploy-state\firebase-gcp-watchdog.log'
$lock = Join-Path $RepoRoot '.deploy-state\firebase-gcp-watchdog.lock'

function Write-Log([string]$msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    $dir = Split-Path $log -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Add-Content -Path $log -Value $line -Encoding UTF8
}

function Invoke-WatchdogLoop {
    . (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')
    Write-Log 'Watchdog GCP iniciado.'
    $round = 0
    while ($round -lt 96) {
        $round++
        Write-Log "Rodada $round"
        $out = & node $publish gestaoyahweh-21e23 --force --max-attempts=8 2>&1
        $text = $out | Out-String
        Add-Content -Path $log -Value $text -Encoding UTF8
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'Sucesso - regras publicadas via GCP REST.'
            Remove-Item $lock -Force -ErrorAction SilentlyContinue
            return
        }
        Write-Log "Falha exit=$LASTEXITCODE - proxima em ${IntervalMinutes}min"
        Start-Sleep -Seconds (60 * $IntervalMinutes)
    }
    Write-Log 'Watchdog terminou apos 96 rodadas (~24h).'
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}

if ($StartBackground) {
    if (Test-Path $lock) {
        $age = (Get-Date) - (Get-Item $lock).LastWriteTime
        if ($age.TotalHours -lt 24) {
            Write-Host "Watchdog ja activo (lock). Log: $log"
            exit 0
        }
        Remove-Item $lock -Force -ErrorAction SilentlyContinue
    }
    Set-Content -Path $lock -Value (Get-Date).ToString('o') -Encoding UTF8
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_watchdog.ps1')
    ) -WindowStyle Hidden -WorkingDirectory $RepoRoot | Out-Null
    Write-Host "Watchdog GCP em background. Log: $log"
    exit 0
}

try {
    Invoke-WatchdogLoop
} finally {
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
