# Deploy produção completo:
#   1) Firestore (regras + índices) + Storage (regras) — com retry
#   2) Todas as Cloud Functions (npm run build + firebase deploy --only functions)
#   3) Web release + Firebase Hosting
#   4) AAB Play Store (obfuscate) + cópia para D:\Temporarios
#   5) ZIP das fontes iOS (sem Pods) em D:\Temporarios
#   6) Git commit + push (Codemagic usa o repositório; use -SkipGitPush para saltar)
#
# Uso (na raiz): .\scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1
# Pasta destino opcional: .\scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1 -CopyTo "D:\Temporarios"
# Sem commit/push Git (Codemagic não recebe código novo): -SkipGitPush
#
# Atalho: .\scripts\deploy_completo.ps1 (mesmos parâmetros -CopyTo / -SkipGitPush)

param(
    [string] $CopyTo = 'D:\Temporarios',
    [switch] $SkipGitPush
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

$Project = "gestaoyahweh-21e23"
$rc = Join-Path $RepoRoot ".firebaserc"
if (Test-Path $rc) {
    try {
        $j = Get-Content $rc -Raw | ConvertFrom-Json
        if ($j.projects.default) { $Project = [string]$j.projects.default }
    } catch {}
}

$FlutterApp = Join-Path $RepoRoot "flutter_app"

Write-Host "`n=== [1/6] Firestore + Storage (regras e indices) ===" -ForegroundColor Cyan
# Mais tentativas que o padrao (10): API firebaserules.googleapis.com costuma devolver 503/409 transitórios.
& (Join-Path $RepoRoot "scripts\deploy_firebase_rules.ps1") -MaxAttempts 20
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== [2/6] Cloud Functions (build + deploy todas) - projeto $Project ===" -ForegroundColor Cyan
$FunctionsDir = Join-Path $RepoRoot "functions"
Push-Location $FunctionsDir
if (Test-Path (Join-Path $FunctionsDir "package-lock.json")) {
    npm ci
} else {
    npm install
}
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
npm run build
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
# index.ts grande: sem isto o CLI pode falhar com "Timeout after 10000" na descoberta.
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "120"
# --force: remove da nuvem funções que já não existem no código (evita abort em modo não interativo).
firebase deploy --only functions --project $Project --force
$funcExit = $LASTEXITCODE
Pop-Location
if ($funcExit -ne 0) { exit $funcExit }

Write-Host "`n=== [3/6] Web + Hosting ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\deploy_web_hosting.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== [4/6] AAB Play + copia $CopyTo ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\build_android_play_store_aab.ps1") -CopyTo $CopyTo
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== [5/6] ZIP fontes iOS (sem Pods) para Codemagic ===" -ForegroundColor Cyan
if (-not (Test-Path $CopyTo)) {
    New-Item -ItemType Directory -Path $CopyTo -Force | Out-Null
}
Set-Location $FlutterApp
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$verLine = Select-String -Path (Join-Path $FlutterApp "pubspec.yaml") -Pattern "^version:\s*" | Select-Object -First 1
$ver = if ($verLine) { ($verLine.Line -replace '^version:\s*', '').Trim() } else { "unknown" }
$zipName = "GestaoYahweh_ios_sources_$($ver -replace '\+', '_build').zip"
$zipPath = Join-Path $CopyTo $zipName
$srcIos = Join-Path $FlutterApp "ios"
$stage = Join-Path $env:TEMP ("yw_ios_stage_" + [Guid]::NewGuid().ToString("N"))
$stageIos = Join-Path $stage "ios"
New-Item -ItemType Directory -Path $stageIos -Force | Out-Null
# Copia iOS excluindo Pods, build e caches (Codemagic corre pod install)
$null = & robocopy $srcIos $stageIos /E /XD Pods .symlinks build /NFL /NDL /NJH /NJS /nc /ns /np
$rcRobo = $LASTEXITCODE
if ($rcRobo -ge 8) {
    Write-Host "robocopy falhou (codigo $rcRobo)." -ForegroundColor Red
    exit $rcRobo
}
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $stageIos -DestinationPath $zipPath -Force
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "ZIP iOS: $zipPath" -ForegroundColor Green

Set-Location $RepoRoot

if (-not $SkipGitPush) {
    Write-Host "`n=== [6/6] Git - commit e push (Codemagic usa o repositorio) ===" -ForegroundColor Cyan
    if (-not (Test-Path (Join-Path $RepoRoot ".git"))) {
        Write-Host "Aviso: pasta .git ausente - push ignorado." -ForegroundColor Yellow
    }
    else {
        Push-Location $RepoRoot
        try {
            $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
            if (-not $branch) { $branch = "main" }
            git add -A
            $staged = @(git diff --cached --name-only 2>$null)
            if ($staged.Count -gt 0) {
                $msg = "chore: deploy completo producao $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                git commit -m $msg
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "ERRO: git commit falhou (hooks ou user.name?). Corrija e faca push manualmente." -ForegroundColor Red
                    Pop-Location
                    exit $LASTEXITCODE
                }
                Write-Host "Commit criado ($($staged.Count) ficheiros)." -ForegroundColor Green
            }
            else {
                Write-Host "Sem alteracoes por commitar - apenas push." -ForegroundColor DarkGray
            }
            git push -u origin $branch
            if ($LASTEXITCODE -ne 0) {
                Write-Host "ERRO: git push falhou. Configure credenciais ou remoto origin." -ForegroundColor Red
                Pop-Location
                exit $LASTEXITCODE
            }
            Write-Host "Push concluido: origin/$branch" -ForegroundColor Green
        }
        finally {
            Pop-Location
        }
    }
}
else {
    Write-Host "`n=== [6/6] Git - ignorado (-SkipGitPush) ===" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Concluido ===" -ForegroundColor Green
Write-Host "Web: https://gestaoyahweh-21e23.web.app (Ctrl+F5)" -ForegroundColor Green
Write-Host "Console: https://console.firebase.google.com/project/$Project/overview" -ForegroundColor DarkGray
Write-Host ('AAB + ZIP iOS em: ' + $CopyTo) -ForegroundColor Green
# Robocopy usa exit 1..7 para sucesso; sem isto o PowerShell pode sair com codigo 1.
exit 0
