# Preflight obrigatorio antes de web/AAB no deploy completo.
# Bloqueia cedo se houver error no analyze (evita falhar 20+ min depois no build web).
#
# Uso (raiz): .\scripts\preflight_deploy_compile.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"

. (Join-Path $RepoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")

if (-not (Test-Path (Join-Path $FlutterApp "pubspec.yaml"))) {
    Write-Host "Erro: flutter_app nao encontrado." -ForegroundColor Red
    exit 1
}

Push-Location $FlutterApp
try {
    Write-Host "=== Preflight deploy: dart analyze lib (errors bloqueiam) ===" -ForegroundColor Cyan
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $analyzeOut = dart analyze lib --no-fatal-warnings 2>&1
    $analyzeExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap
    $analyzeOut | ForEach-Object { Write-Host $_ }

    $dartErrors = @($analyzeOut | Where-Object { $_ -match '^\s*error\s+-' })
    if ($dartErrors.Count -gt 0 -or $analyzeExit -eq 3) {
        Write-Host ""
        Write-Host "ERRO preflight: $($dartErrors.Count) error(s) no dart analyze - deploy abortado." -ForegroundColor Red
        Write-Host "Corrija os ficheiros acima antes de web/AAB/iOS." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Preflight OK - sem errors de compilacao Dart." -ForegroundColor Green
    exit 0
}
finally {
    Pop-Location
}
