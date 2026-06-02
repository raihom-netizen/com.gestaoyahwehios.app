# Deploy produção completo (otimizado):
#   1) Firestore (regras + índices) + Storage (regras) -- com retry
#   2) Cloud Functions (npm + tsc + deploy) -- SKIP automatico se /functions
#      nao mudou no ultimo commit (use -ForceFunctions para forcar)
#   3) Web release + Firebase Hosting
#   4) AAB Play Store (obfuscate) + cópia para D:\Temporarios
#   5) ZIP das fontes iOS (sem Pods) em D:\Temporarios
#   6) Git commit + push (Codemagic usa o repositório; use -SkipGitPush para saltar)
#
# OTIMIZACOES vs versao anterior (~5 min mais rapido em deploys tipicos):
#   * `flutter clean` + `flutter pub get` rodam UMA UNICA VEZ (etapa 0),
#     em vez de 3x (web/AAB/ZIP). Sub-scripts recebem -SkipPubGet.
#   * Step ZIP iOS nao chama mais `flutter pub get` redundante
#     (so faz robocopy + Compress-Archive da pasta ios/).
#   * Cloud Functions: detecta automaticamente se houve mudanca em
#     /functions desde HEAD~1; se nao, SKIPa o deploy de functions
#     inteiro (npm ci + tsc + firebase deploy ~3 min). Use
#     -ForceFunctions para forcar mesmo sem alteracao.
#
# Uso (na raiz):
#   .\scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1
# Pasta destino opcional:
#   ... -CopyTo "D:\Temporarios"
# Sem commit/push Git (Codemagic não recebe código novo): -SkipGitPush
# Forcar deploy de functions mesmo sem mudancas: -ForceFunctions
# Forcar `flutter clean` (caso suspeite de cache corrompido): -ForceClean
#
# Atalho: .\scripts\deploy_completo.ps1 (mesmos parâmetros)

param(
    [string] $CopyTo = 'D:\Temporarios',
    [switch] $SkipGitPush,
    [switch] $ForceFunctions,
    [switch] $ForceClean,
    [switch] $ForceFirestoreRules
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
. (Join-Path $RepoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")

$Project = "gestaoyahweh-21e23"
$rc = Join-Path $RepoRoot ".firebaserc"
if (Test-Path $rc) {
    try {
        $j = Get-Content $rc -Raw | ConvertFrom-Json
        if ($j.projects.default) { $Project = [string]$j.projects.default }
    } catch {}
}

$FlutterApp = Join-Path $RepoRoot "flutter_app"
$startedAt = Get-Date

# ========================================================================
# [0/6] Pre-step: flutter clean + pub get UMA VEZ (reusado em web e AAB)
# ========================================================================
Write-Host "`n=== [0/6] Preparar Flutter (clean + pub get unico) ===" -ForegroundColor Cyan
Push-Location $FlutterApp
try {
    if ($ForceClean) {
        Write-Host "ForceClean: rodando flutter clean..." -ForegroundColor DarkGray
        flutter clean
        if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
    }
    else {
        # Limpa apenas saidas dos builds anteriores (mantem .dart_tool / pub cache).
        # `.dart_tool/` quando preservado evita re-descobrir 800+ pacotes a cada build.
        $cleanPaths = @(
            (Join-Path $FlutterApp "build\web"),
            (Join-Path $FlutterApp "build\app\outputs\bundle\release\app-release.aab")
        )
        foreach ($p in $cleanPaths) {
            if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Write-Host "Rodando flutter pub get..." -ForegroundColor DarkGray
    flutter pub get
    if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
}
finally { Pop-Location }

# ========================================================================
# [1/6] Firestore + Storage rules
# ========================================================================
Write-Host "`n=== [1/6] Firestore + Storage (regras e indices) ===" -ForegroundColor Cyan
# ForcePublish sempre no deploy completo: API firebaserules 503/409 nao pode abortar [1/6].
$rulesArgs = @{ MaxAttempts = 25; ForcePublish = $true }
if (-not $ForceFirestoreRules) {
    Write-Host "   (regras: modo resiliente ForcePublish - padrao no deploy completo)" -ForegroundColor DarkGray
}
& (Join-Path $RepoRoot "scripts\deploy_firebase_rules.ps1") @rulesArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ========================================================================
# [2/6] Cloud Functions -- SKIP se nao mudou
# ========================================================================
$functionsChanged = $true
$functionsSkipReason = ""
if (-not $ForceFunctions) {
    try {
        # Detecta se /functions mudou em relacao ao remoto (ou ultimo commit local).
        # Compara contra origin/<branch> se existir, senao HEAD~1.
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if (-not $branch) { $branch = "main" }
        $remoteRef = "origin/$branch"
        $compareTo = $null
        $hasRemote = $false
        try {
            git rev-parse --verify $remoteRef 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $hasRemote = $true }
        } catch {}
        if ($hasRemote) { $compareTo = $remoteRef } else { $compareTo = "HEAD~1" }

        $diff = git diff --name-only $compareTo -- functions 2>$null
        # Tambem detecta arquivos staged/unstaged ainda nao commitados.
        $staged = git diff --cached --name-only -- functions 2>$null
        $unstaged = git diff --name-only -- functions 2>$null
        $allChanges = @(@($diff) + @($staged) + @($unstaged) | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -Unique)
        if ($allChanges.Count -eq 0) {
            $functionsChanged = $false
            $functionsSkipReason = "sem alteracoes em /functions desde $compareTo (use -ForceFunctions para forcar)"
        }
        else {
            Write-Host "Functions: detectadas $($allChanges.Count) alteracao(es) em /functions" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "Aviso: nao foi possivel comparar /functions com Git ($($_.Exception.Message)). Vai rodar deploy normal." -ForegroundColor Yellow
        $functionsChanged = $true
    }
}

if (-not $functionsChanged) {
    Write-Host "`n=== [2/6] Cloud Functions -- SKIP ($functionsSkipReason) ===" -ForegroundColor Yellow
}
else {
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
    $env:FUNCTIONS_DISCOVERY_TIMEOUT = "120"
    firebase deploy --only functions --project $Project --force
    $funcExit = $LASTEXITCODE
    Pop-Location
    if ($funcExit -ne 0) { exit $funcExit }
}

# ========================================================================
# [3/6] Web + Hosting (sub-script com -SkipPubGet)
# ========================================================================
Write-Host "`n=== [3/6] Web + Hosting ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\deploy_web_hosting.ps1") -SkipPubGet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ========================================================================
# [4/6] AAB Play Store (sub-script com -SkipPubGet)
# ========================================================================
Write-Host "`n=== [4/6] AAB Play + copia $CopyTo ===" -ForegroundColor Cyan
& (Join-Path $RepoRoot "scripts\build_android_play_store_aab.ps1") -CopyTo $CopyTo -SkipPubGet
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# ========================================================================
# [5/6] ZIP iOS (sem pub get redundante -- robocopy direto)
# ========================================================================
Write-Host "`n=== [5/6] ZIP fontes iOS (sem Pods) para Codemagic ===" -ForegroundColor Cyan
if (-not (Test-Path $CopyTo)) {
    New-Item -ItemType Directory -Path $CopyTo -Force | Out-Null
}

$verLine = Select-String -Path (Join-Path $FlutterApp "pubspec.yaml") -Pattern "^version:\s*" | Select-Object -First 1
$ver = if ($verLine) { ($verLine.Line -replace '^version:\s*', '').Trim() } else { "unknown" }
$zipName = "GestaoYahweh_ios_sources_$($ver -replace '\+', '_build').zip"
$zipPath = Join-Path $CopyTo $zipName
$srcIos = Join-Path $FlutterApp "ios"
$stage = Join-Path $env:TEMP ("yw_ios_stage_" + [Guid]::NewGuid().ToString("N"))
$stageIos = Join-Path $stage "ios"
New-Item -ItemType Directory -Path $stageIos -Force | Out-Null
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

# ========================================================================
# [6/6] Git commit + push
# ========================================================================
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

$elapsed = (Get-Date) - $startedAt
$elapsedStr = "{0:mm\:ss}" -f $elapsed

Write-Host ""
Write-Host "=== Concluido em $elapsedStr ===" -ForegroundColor Green
Write-Host "Web: https://gestaoyahweh-21e23.web.app (Ctrl+F5)" -ForegroundColor Green
Write-Host "Console: https://console.firebase.google.com/project/$Project/overview" -ForegroundColor DarkGray
Write-Host ('AAB + ZIP iOS em: ' + $CopyTo) -ForegroundColor Green
if (-not $functionsChanged) {
    Write-Host "Cloud Functions: SKIP ($functionsSkipReason)" -ForegroundColor DarkGray
}
exit 0
