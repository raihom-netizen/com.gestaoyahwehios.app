# Watchdog: republica regras via GCP REST ate sucesso (503 Google).
# Uso: .\scripts\firebase_rules_gcp_watchdog.ps1 -StartBackground

param(
    [switch] $StartBackground,
    [int] $IntervalMinutes = 20
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
    $rootKey = Join-Path $RepoRoot 'gestaoyahweh-gcp-deploy-key.json'
    if (Test-Path $rootKey) {
        $env:GOOGLE_APPLICATION_CREDENTIALS = $rootKey
        $env:YAHWEH_GCP_KEY_FILE = $rootKey
    }
    $env:YAHWEH_GCP_PREFER_ADC = '0'
    $env:YAHWEH_GCP_PREFER_OWNER = '0'
    Write-Log 'Watchdog GCP iniciado (chave SA raiz, firestore only se storage OK).'
    $round = 0
    while ($round -lt 48) {
        $round++
        $pubLock = Join-Path $RepoRoot '.deploy-state\firebase-rules-publish.lock'
        if (Test-Path $pubLock) {
            $age = (Get-Date) - (Get-Item $pubLock).LastWriteTime
            if ($age.TotalMinutes -lt 90) {
                Write-Log 'Skip: publish lock activo.'
                Start-Sleep -Seconds (60 * $IntervalMinutes)
                continue
            }
            Remove-Item $pubLock -Force -ErrorAction SilentlyContinue
            Write-Log 'Lock expirado (>90min) — removido.'
        }
        $only = 'all'
        $syncPath = Join-Path $RepoRoot '.deploy-state\firebase-sync.json'
        if (Test-Path $syncPath) {
            try {
                $sync = Get-Content $syncPath -Raw | ConvertFrom-Json
                $hasStorage = @($sync.results) | Where-Object { $_.target -eq 'storage' -and $_.action -match 'published|already_synced' }
                $hasFirestore = @($sync.results) | Where-Object { $_.target -eq 'firestore' -and $_.action -match 'published|already_synced' }
                if ($hasStorage -and -not $hasFirestore) { $only = 'firestore' }
            } catch { }
        }
        Write-Log "Rodada $round (only=$only)"
        $out = & node $publish gestaoyahweh-21e23 --force --max-attempts=3 --only=$only 2>&1
        $text = $out | Out-String
        Add-Content -Path $log -Value $text -Encoding UTF8
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'Sucesso - regras publicadas via GCP REST.'
            Remove-Item $lock -Force -ErrorAction SilentlyContinue
            return
        }
        $firebaseCmd = Join-Path $env:APPDATA 'npm\firebase.cmd'
        if (Test-Path $firebaseCmd) {
            Write-Log 'REST falhou; tentar Firebase CLI com a mesma conta administrativa.'
            $cliOut = & $firebaseCmd deploy --only 'firestore:rules' --project 'gestaoyahweh-21e23' --force --non-interactive 2>&1
            Add-Content -Path $log -Value ($cliOut | Out-String) -Encoding UTF8
            if ($LASTEXITCODE -eq 0) {
                Write-Log 'Sucesso - regras publicadas via Firebase CLI.'
                Remove-Item $lock -Force -ErrorAction SilentlyContinue
                return
            }
        }
        Write-Log "REST e CLI falharam - proxima em ${IntervalMinutes}min"
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
        '-File', (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_watchdog.ps1'),
        '-IntervalMinutes', $IntervalMinutes
    ) -WindowStyle Hidden -WorkingDirectory $RepoRoot | Out-Null
    Write-Host "Watchdog GCP em background. Log: $log"
    exit 0
}

try {
    Invoke-WatchdogLoop
} finally {
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
