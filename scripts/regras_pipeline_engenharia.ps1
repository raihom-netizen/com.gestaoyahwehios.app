# Pipeline engenharia — Security Rules Firebase (Gestao YAHWEH)
# Limpeza estado local -> testes emulador (JDK 21) -> publicacao forcada sequencial GCP.
#
# Uso (raiz, autorizado):
#   .\scripts\regras_pipeline_engenharia.ps1
#   .\scripts\regras_pipeline_engenharia.ps1 -SkipTests
#   .\scripts\regras_pipeline_engenharia.ps1 -OnlyValidate

param(
    [switch] $SkipTests,
    [switch] $SkipCors,
    [switch] $OnlyValidate,
    [int] $MaxAttempts = 25
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
$ProjectId = 'gestaoyahweh-21e23'
$startedAt = (Get-Date).ToUniversalTime().ToString('o')
$report = @{
    startedAt  = $startedAt
    projectId  = $ProjectId
    phases     = @()
    ok         = $false
}

function Add-Phase {
    param([string] $Name, [bool] $Ok, [string] $Detail = '')
    $script:report.phases += @{ name = $Name; ok = $Ok; detail = $Detail; at = (Get-Date).ToUniversalTime().ToString('o') }
}

function Write-Phase {
    param([string] $Msg, [string] $Color = 'Cyan')
    Write-Host "`n=== $Msg ===" -ForegroundColor $Color
}

Write-Host '=== Pipeline Regras Firebase (engenharia) ===' -ForegroundColor Cyan
Write-Host 'Fluxo: JDK21 -> limpar estado -> testes emulador -> publicar REST sequencial -> verificar' -ForegroundColor DarkGray

# ── 0. Toolchain ──
Write-Phase '0. Toolchain (JDK 21, Node, Firebase, GCP auth)'
. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')
. (Join-Path $RepoRoot 'scripts\ensure_jdk21_toolchain.ps1')
try {
    Ensure-Jdk21Toolchain | Out-Null
    $jv = & java -version 2>&1 | Select-Object -First 1
    Add-Phase -Name 'jdk21' -Ok $true -Detail "$jv"
} catch {
    Add-Phase -Name 'jdk21' -Ok $false -Detail $_.Exception.Message
    Write-Host "ERRO JDK 21: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

& (Join-Path $RepoRoot 'scripts\ensure_functions_node_for_gcp.ps1') | Out-Null
$key = Join-Path $RepoRoot 'gestaoyahweh-gcp-deploy-key.json'
if (-not (Test-Path $key)) {
    $src = Get-ChildItem (Join-Path $RepoRoot 'ANDROID'), (Join-Path $RepoRoot 'secrets') `
        -Filter 'gestaoyahweh*-firebase-adminsdk*.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($src) { Copy-Item $src.FullName $key -Force }
}
if (-not (Test-Path $key)) {
    Add-Phase -Name 'auth_key' -Ok $false -Detail 'Chave SA em falta (ANDROID/ ou secrets/)'
    exit 1
}
$env:GOOGLE_APPLICATION_CREDENTIALS = $key
$env:YAHWEH_GCP_KEY_FILE = $key
$env:YAHWEH_GCP_PREFER_ADC = '0'
$env:YAHWEH_FORCE_REPUBLISH = '1'
Add-Phase -Name 'auth_key' -Ok $true -Detail (Split-Path $key -Leaf)

# ── 1. Limpar estado / locks (regras "antigas" locais — nao apaga historico GCP) ──
Write-Phase '1. Limpeza estado local e locks'
$stateDir = Join-Path $RepoRoot '.deploy-state'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir | Out-Null }
$toRemove = @(
    'firebase-rules-publish.lock',
    'firebase-gcp-watchdog.lock',
    'firebase-rules-background.lock',
    'firebase-rules-pending.json',
    'firebase-sync.json',
    'regras-pipeline-report.json'
)
$removed = @()
foreach ($f in $toRemove) {
    $p = Join-Path $stateDir $f
    if (Test-Path $p) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        $removed += $f
    }
}
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'firebase_rules_gcp_publish|firebase_rules_gcp_watchdog' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Add-Phase -Name 'clean_state' -Ok $true -Detail ("removidos: " + ($removed -join ', '))
Write-Host "   Locks/estado limpos: $($removed.Count) ficheiro(s)" -ForegroundColor Green

$fr = Join-Path $RepoRoot 'firestore.rules'
$sr = Join-Path $RepoRoot 'storage.rules'
$ix = Join-Path $RepoRoot 'firestore.indexes.json'
foreach ($p in @($fr, $sr, $ix)) {
    if (-not (Test-Path $p)) {
        Add-Phase -Name 'local_files' -Ok $false -Detail "Em falta: $p"
        exit 1
    }
}
Add-Phase -Name 'local_files' -Ok $true -Detail 'firestore.rules, storage.rules, firestore.indexes.json'

# ── 2. Testes emulador ──
if (-not $SkipTests) {
    Write-Phase '2. Testes Security Rules (Firebase Emulator + Node test)'
    $testDir = Join-Path $RepoRoot 'security_rules_test_firestore'
    if (-not (Test-Path (Join-Path $testDir 'node_modules'))) {
        Push-Location $testDir
        & npm install --silent 2>&1 | Out-Null
        Pop-Location
    }
    $testCmd = 'cd security_rules_test_firestore && npm test'
    $testOut = & firebase emulators:exec --only firestore --project $ProjectId $testCmd 2>&1
    $testOut | ForEach-Object { Write-Host $_ }
    $testsOk = ($LASTEXITCODE -eq 0) -and ($testOut -match '# pass|tests passed|ok \d+')
    if (-not $testsOk) { $testsOk = $LASTEXITCODE -eq 0 }
    Add-Phase -Name 'emulator_tests' -Ok $testsOk -Detail "exit=$LASTEXITCODE"
    if (-not $testsOk) {
        Write-Host '   Testes falharam — corrija firestore.rules ou use -SkipTests para publicar mesmo assim.' -ForegroundColor Red
        $report.ok = $false
        $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stateDir 'regras-pipeline-report.json') -Encoding UTF8
        if ($OnlyValidate) { exit 1 }
        exit 1
    }
} else {
    Add-Phase -Name 'emulator_tests' -Ok $true -Detail 'skipped'
}

if ($OnlyValidate) {
    Write-Host "`n=== OnlyValidate: testes OK, deploy omitido ===" -ForegroundColor Green
    $report.ok = $true
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stateDir 'regras-pipeline-report.json') -Encoding UTF8
    exit 0
}

# ── 3. Publicacao forcada sequencial (quota 1 req/min) ──
Write-Phase '3. Publicacao forcada (Storage -> Firestore -> Indices)'
$publishScript = Join-Path $RepoRoot 'scripts\firebase_rules_gcp_publish.cjs'
$targets = @(
    @{ name = 'storage'; only = 'storage'; wait = 0 },
    @{ name = 'firestore'; only = 'firestore'; wait = 75 },
    @{ name = 'indexes'; only = $null; wait = 75 }
)
$allOk = $true

foreach ($t in $targets) {
    if ($t.wait -gt 0) {
        Write-Host "   Pausa $($t.wait)s (quota firebaserules.googleapis.com)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $t.wait
    }
    if ($t.name -eq 'indexes') {
        Write-Host "   [indexes] REST..." -ForegroundColor Yellow
        $idxOut = & node (Join-Path $RepoRoot 'scripts\firebase_indexes_gcp_publish.cjs') --force --max-attempts=$MaxAttempts 2>&1
        $idxOut | ForEach-Object { Write-Host $_ }
        $ok = ($LASTEXITCODE -eq 0) -or ($idxOut -match 'YAHWEH_INDEXES_OK=.*"ok":true')
        Add-Phase -Name 'publish_indexes' -Ok $ok -Detail "exit=$LASTEXITCODE"
        if (-not $ok) { $allOk = $false }
        continue
    }
    Write-Host "   [$($t.name)] REST --force-republish..." -ForegroundColor Yellow
    $nodeArgs = @($publishScript, $ProjectId, '--force', "--max-attempts=$MaxAttempts", "--only=$($t.only)")
    $out = & node @nodeArgs 2>&1
    $out | ForEach-Object { Write-Host $_ }
    $ok = ($LASTEXITCODE -eq 0) -or ($out -match 'YAHWEH_GCP_OK=.*"ok":true')
    Add-Phase -Name "publish_$($t.name)" -Ok $ok -Detail "exit=$LASTEXITCODE"
    if (-not $ok) { $allOk = $false }
}

# ── 4. Fallback CLI se Firestore REST falhou ──
$fsPhase = $report.phases | Where-Object { $_.name -eq 'publish_firestore' } | Select-Object -Last 1
if ($fsPhase -and -not $fsPhase.ok) {
    Write-Phase '4. Fallback Firebase CLI (firestore:rules)' 'Yellow'
    $env:FUNCTIONS_DISCOVERY_TIMEOUT = '120'
    $cliOut = & firebase deploy --only firestore:rules --project $ProjectId --non-interactive 2>&1
    $cliOut | ForEach-Object { Write-Host $_ }
    $cliOk = ($LASTEXITCODE -eq 0) -or ($cliOut -match 'released rules firestore\.rules|already up to date')
    Add-Phase -Name 'fallback_cli_firestore' -Ok $cliOk -Detail "exit=$LASTEXITCODE"
    if ($cliOk) { $allOk = $true }
}

# ── 5. Verificacao remota ──
Write-Phase '5. Verificacao remota (preflight REST)'
. (Join-Path $RepoRoot 'scripts\firebase_rules_preflight.ps1')
$pf = Invoke-FirebaseRulesPreflight -RepoRoot $RepoRoot -VerbosePreflight
Add-Phase -Name 'verify_remote' -Ok $pf.AllOk -Detail $pf.Message
if ($pf.AllOk) { $allOk = $true }

# ── 6. CORS opcional ──
if (-not $SkipCors -and $allOk) {
    Write-Phase '6. CORS Storage' 'DarkGray'
    & (Join-Path $RepoRoot 'scripts\apply_firebase_storage_cors.ps1') 2>&1 | Out-Null
}

$report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
$report.ok = $allOk
$report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $stateDir 'regras-pipeline-report.json') -Encoding UTF8

Write-Host ''
if ($allOk) {
    Write-Host '=== PIPELINE REGRAS: APROVADO ===' -ForegroundColor Green
    Write-Host "Relatorio: $stateDir\regras-pipeline-report.json" -ForegroundColor DarkGray
    Write-Host "Console: https://console.firebase.google.com/project/$ProjectId/overview" -ForegroundColor DarkGray
    exit 0
}

Write-Host '=== PIPELINE REGRAS: PENDENTE (503 API ou verificacao) ===' -ForegroundColor Yellow
Write-Host 'Watchdog:' -ForegroundColor DarkYellow
& (Join-Path $RepoRoot 'scripts\firebase_rules_gcp_watchdog.ps1') -StartBackground
exit 1
