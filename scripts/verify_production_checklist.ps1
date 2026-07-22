# Gate Modo Producao - Gestao YAHWEH
# Bloqueia deploy se arquitetura critica estiver incompleta ou quebrada.
# Uso: .\scripts\verify_production_checklist.ps1
# Bypass (emergencia): deploy_completo.ps1 -SkipProductionGate

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")

$failures = @()

function Add-Failure([string]$msg) {
    $script:failures += $msg
    Write-Host "  FALHA: $msg" -ForegroundColor Red
}

function Test-FileExists([string]$relPath, [string]$label) {
    $full = Join-Path $repoRoot $relPath
    if (-not (Test-Path $full)) {
        Add-Failure "$label - ficheiro em falta: $relPath"
        return $false
    }
    return $true
}

function Test-FileContains([string]$relPath, [string]$pattern, [string]$label) {
    $full = Join-Path $repoRoot $relPath
    if (-not (Test-Path $full)) {
        Add-Failure "$label - ficheiro em falta: $relPath"
        return
    }
    $hit = Select-String -Path $full -Pattern $pattern -Quiet
    if (-not $hit) {
        Add-Failure "$label - padrao nao encontrado em $relPath : $pattern"
    }
}

Write-Host "=== Modo Producao - checklist de release ===" -ForegroundColor Cyan

Write-Host "`n[1/6] Firebase - bootstrap unico..." -ForegroundColor Yellow
Test-FileExists "flutter_app\lib\core\firebase_bootstrap_service.dart" "Firebase init"
Test-FileContains "flutter_app\lib\main.dart" "FirebaseBootstrapService\.initialize" "Firebase init main"

Write-Host "`n[2/6] Regras Firestore - chat..." -ForegroundColor Yellow
Test-FileContains "firestore.rules" "match /chats/" "Chat rules"
Test-FileContains "firestore.rules" "canReadChatThreadDoc" "Chat read helper"

Write-Host "`n[3/7] Modulos criticos (offline, publicacao, saude, QA)..." -ForegroundColor Yellow
$required = @(
    "flutter_app\lib\core\offline\offline_bootstrap.dart",
    "flutter_app\lib\services\publication_engine.dart",
    "flutter_app\lib\services\system_health_service.dart",
    "flutter_app\lib\core\system_health\system_last_error_registry.dart",
    "flutter_app\lib\core\system_health\session_performance_metrics.dart",
    "flutter_app\lib\core\qa\qa_assurance_runner.dart",
    "flutter_app\lib\ui\pages\system_firebase_health_page.dart"
)
foreach ($r in $required) {
    Test-FileExists $r "Modulo critico"
}

Write-Host "`n[4/7] Monitoramento (Crashlytics + Performance + Analytics)..." -ForegroundColor Yellow
Test-FileContains "flutter_app\lib\main.dart" "FirebaseCrashlytics" "Crashlytics"
Test-FileContains "flutter_app\lib\services\performance_service.dart" "FirebasePerformance" "Performance"
Test-FileContains "flutter_app\lib\services\analytics_service.dart" "FirebaseAnalytics" "Analytics"
Test-FileContains "flutter_app\lib\core\system_health\production_module_traces.dart" "time_dashboard" "Traces modulos"

Write-Host "`n[5/7] Backup automatico (Cloud Functions)..." -ForegroundColor Yellow
Test-FileContains "functions\src\index.ts" "backupDailyToGcs" "Backup Firestore GCS"

Write-Host "`n[6/8] Modo QA (28 testes)..." -ForegroundColor Yellow
Test-FileContains "flutter_app\lib\core\qa\qa_assurance_runner.dart" "runAll" "QA runner"
Test-FileContains "flutter_app\lib\services\system_health_service.dart" "bindPeriodicProbe" "Health check 5 min"
Test-FileExists "flutter_app\test\qa_assurance_runner_test.dart" "QA unit test"

Write-Host "`n[7/8] Padronizacao multiplataforma..." -ForegroundColor Yellow
Test-FileExists "docs\PADRONIZACAO_MULTIPLATAFORMA.md" "Doc multiplataforma"
Test-FileExists "flutter_app\lib\core\qa\multiplatform_qa_matrix.dart" "Matriz QA plataformas"
Test-FileContains "flutter_app\lib\core\qa\multiplatform_qa_matrix.dart" "releaseBlockedIfAnyPlatformFails" "Gate release tri-plataforma"

Write-Host "`n[8/8] dart analyze (ficheiros de producao)..." -ForegroundColor Yellow
$flutterApp = Join-Path $repoRoot "flutter_app"
Push-Location $flutterApp
try {
    $analyzeTargets = @(
        "lib/services/system_health_service.dart",
        "lib/core/system_health/system_last_error_registry.dart",
        "lib/core/qa/qa_assurance_runner.dart",
        "lib/core/qa/multiplatform_qa_matrix.dart",
        "lib/core/system_health/session_performance_metrics.dart",
        "lib/ui/pages/system_firebase_health_page.dart",
        "lib/services/yahweh_observability.dart",
        "lib/core/yahweh_catch_log.dart",
        "lib/services/publication_engine.dart",
        "lib/core/offline/offline_bootstrap.dart"
    )
    dart analyze --no-fatal-warnings @analyzeTargets
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "dart analyze - corrigir errors nos ficheiros de producao"
    }
}
finally {
    Pop-Location
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host ('RELEASE BLOQUEADA (' + $failures.Count + ' falhas).' ) -ForegroundColor Red
    Write-Host 'Corrija antes de deploy. Bypass: -SkipProductionGate (nao recomendado).' -ForegroundColor DarkYellow
    Write-Host 'Painel ADM: Menu Master > Saude do Sistema > aba Central.' -ForegroundColor DarkGray
    exit 10
}

Write-Host "Checklist estatico OK. Valide manualmente nas 3 plataformas:" -ForegroundColor Green
Write-Host "  Android + iPhone + Web - Modo QA (28 testes) + Central = LIBERADO" -ForegroundColor DarkGray
Write-Host "Ver docs/CHECKLIST_PRODUCAO.md e docs/PADRONIZACAO_MULTIPLATAFORMA.md" -ForegroundColor Cyan
exit 0
