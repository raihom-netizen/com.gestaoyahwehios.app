# Análise Flutter/Dart com avisos não-fatais — útil antes de build quando há warnings herdados.
# Uso (na raiz do repo): .\scripts\flutter_analyze_relax.ps1
# Com paths extra: .\scripts\flutter_analyze_relax.ps1 lib/foo.dart
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot "flutter_app"
if (-not (Test-Path $FlutterApp)) {
    Write-Host "Pasta flutter_app nao encontrada em $FlutterApp" -ForegroundColor Red
    exit 1
}
Push-Location $FlutterApp
try {
    if ($args.Count -gt 0) {
        dart analyze --no-fatal-warnings @args
    } else {
        dart analyze --no-fatal-warnings
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
