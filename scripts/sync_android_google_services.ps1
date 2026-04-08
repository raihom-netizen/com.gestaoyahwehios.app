# Copia apenas google-services.json de ANDROID\ para flutter_app\android\app\
# (não copia Admin SDK nem client_secret — são perigosos no build do app).
# Uso (raiz do repo): .\scripts\sync_android_google_services.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Src = Join-Path $RepoRoot "ANDROID\google-services.json"
$Dst = Join-Path $RepoRoot "flutter_app\android\app\google-services.json"

if (-not (Test-Path $Src)) {
    Write-Error "Nao encontrado: $Src"
}
Copy-Item -Path $Src -Destination $Dst -Force
Write-Host "OK: $Dst" -ForegroundColor Green
Write-Host "Lembrete: Admin SDK e client_secret ficam so na pasta ANDROID (ou servidor), nao no app." -ForegroundColor DarkGray
