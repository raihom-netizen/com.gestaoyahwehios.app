# Release: deploy completo (Firestore + Storage + seed + hosting) + AAB Play Store
# com cópia automática para D:\Temporarios (definida em build_android_play_store_aab.ps1).
#
# Raiz do repo: .\scripts\release_completo_web_aab.ps1
# Requisitos: Flutter, Firebase CLI (firebase login), Node (seed opcional).
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

Write-Host "=== [1/2] Deploy completo (regras + seed + web hosting) ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\deploy_full_gestao_yahweh.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== [2/2] AAB release + copia D:\Temporarios ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\build_android_play_store_aab.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== Release concluido ===" -ForegroundColor Green
Write-Host "Web: https://gestaoyahweh-21e23.web.app" -ForegroundColor Green
Write-Host "AAB: copia em D:\Temporarios (nome GestaoYahweh_*_play.aab)" -ForegroundColor Green
Write-Host "iOS: requer macOS/Xcode para IPA." -ForegroundColor DarkGray
