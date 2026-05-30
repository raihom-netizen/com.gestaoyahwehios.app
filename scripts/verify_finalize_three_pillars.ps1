# Gate local - Pilares de finalizacao (Gestao YAHWEH)
# Uso: .\scripts\verify_finalize_three_pillars.ps1

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")

Write-Host "=== Pilares de finalizacao - verificacao ===" -ForegroundColor Cyan

$flutterApp = Join-Path $repoRoot "flutter_app"
Push-Location $flutterApp
try {
    Write-Host ""
    Write-Host "[1/3] dart analyze (sem fatal warnings)..." -ForegroundColor Yellow
    dart analyze --no-fatal-warnings lib/core/app_finalize_bootstrap.dart lib/services/feed_media_publish_service.dart lib/services/feed_media_publish_strict.dart lib/services/pending_uploads_firestore_service.dart lib/ui/pages/system_firebase_health_page.dart
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FALHA: corrigir errors acima antes do deploy." -ForegroundColor Red
        exit 3
    }

    Write-Host ""
    Write-Host "[2/3] Padroes proibidos no mural..." -ForegroundColor Yellow
    $bad = @()
    $files = @(
        "lib\ui\widgets\instagram_mural.dart",
        "lib\ui\pages\events_manager_page.dart"
    )
    foreach ($f in $files) {
        if (-not (Test-Path $f)) { continue }
        $patternCreate = "FeedMediaPublishService.createPost("
        $hits = Select-String -Path $f -Pattern $patternCreate -SimpleMatch
        if ($hits) {
            $msg = "{0} usa createPost (usar publish ou publishWithPhotosFirst)" -f $f
            $bad += $msg
        }
        $patternInstant = "MuralFastPublishService.publishInstant"
        $hits2 = Select-String -Path $f -Pattern $patternInstant -SimpleMatch
        if ($hits2) {
            $msg2 = "{0} usa publishInstant legado" -f $f
            $bad += $msg2
        }
    }
    if ($bad.Count -gt 0) {
        $bad | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 2
    }
    Write-Host "  OK - avisos/eventos sem createPost no fluxo principal." -ForegroundColor Green

    Write-Host ""
    Write-Host "[3/3] Ficheiros obrigatorios..." -ForegroundColor Yellow
    $required = @(
        "..\CHECKLIST_FINAL_CHAT_MURAL_LOGIN.md",
        "lib\core\app_finalize_bootstrap.dart",
        "lib\services\pending_uploads_firestore_service.dart"
    )
    foreach ($r in $required) {
        if (-not (Test-Path $r)) {
            Write-Host "  FALTA: $r" -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "  OK." -ForegroundColor Green
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Verificacao concluida. Execute CHECKLIST_FINAL_CHAT_MURAL_LOGIN.md em dispositivos reais." -ForegroundColor Cyan
exit 0
