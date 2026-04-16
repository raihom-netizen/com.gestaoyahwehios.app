# Deploy «completo» legado (regras + 1 function + web) — sem AAB nem iOS nem Git push.
# Para **deploy completo produção** (functions todas + AAB D:\Temporarios + ZIP iOS + push Codemagic):
#   .\scripts\deploy_completo.ps1
#
# Este script faz:
# 1) Firestore (regras + índices) + Storage (regras)
# 2) Seed automático: app_public/institutional_gallery + pastas public/gestao_yahweh/*
# 3) Cloud Function resolveEmailToChurchPublic (site público / busca igreja por e-mail)
# 4) Build web release + Firebase Hosting
#
# Na raiz: .\scripts\deploy_full_gestao_yahweh.ps1
# Requisitos: Flutter, Firebase CLI (firebase login), Node.js; para o seed Admin SDK use
# gcloud auth application-default login OU GOOGLE_APPLICATION_CREDENTIALS apontando para JSON de serviço.
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

if (-not (Test-Path (Join-Path $RepoRoot "firebase.json"))) {
    Write-Host "Erro: firebase.json nao encontrado na raiz: $RepoRoot" -ForegroundColor Red
    exit 1
}

Write-Host "=== [1/4] Firestore + Storage (regras) com retry em 503 ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\deploy_firebase_rules.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== [2/4] Seed galeria institucional (Firestore + Storage) ===" -ForegroundColor Cyan
$FunctionsDir = Join-Path $RepoRoot "functions"
if (Test-Path (Join-Path $FunctionsDir "scripts\ensure-institutional-gallery.js")) {
    Push-Location $FunctionsDir
    node scripts/ensure-institutional-gallery.js
    $seedExit = $LASTEXITCODE
    Pop-Location
    if ($seedExit -ne 0) {
        Write-Host "Aviso: seed falhou (credenciais Admin SDK?). Crie manualmente app_public/institutional_gallery e pastas no Storage." -ForegroundColor Yellow
    }
} else {
    Write-Host "Aviso: ensure-institutional-gallery.js nao encontrado." -ForegroundColor Yellow
}

Write-Host "`n=== [3/4] Cloud Function resolveEmailToChurchPublic ===" -ForegroundColor Cyan
if (-not (Test-Path (Join-Path $FunctionsDir "package.json"))) {
    Write-Host "Erro: pasta functions nao encontrada em $FunctionsDir" -ForegroundColor Red
    exit 1
}
Push-Location $FunctionsDir
firebase deploy --only functions:resolveEmailToChurchPublic
$funcExit = $LASTEXITCODE
Pop-Location
if ($funcExit -ne 0) { exit $funcExit }

Write-Host "`n=== [4/4] Build web + hosting ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\deploy_web_hosting.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Deploy completo ===" -ForegroundColor Green
Write-Host "Web: https://gestaoyahweh-21e23.web.app (Ctrl+F5 para cache)" -ForegroundColor Green
Write-Host "Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview" -ForegroundColor DarkGray
