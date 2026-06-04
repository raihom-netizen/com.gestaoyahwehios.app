# Deploy Firestore (rules + indexes) + Storage rules - Gestão YAHWEH
# Execute na raiz do repo:  .\scripts\deploy_firebase_rules.ps1
#
# Erros frequentes (API Google, não bug local):
#   • 503/504/429 em firebaserules.googleapis.com (/test, /rulesets, /releases)
#   • 409 em releases - deploy parcial anterior (tratado como OK se rules compilaram)
#
# Estratégia v2 (Controle Total / produção):
#   • Não repetir storage/rules/indexes já OK (menos carga na API -> menos 503)
#   • Micro-retries por alvo (firestore:rules / firestore:indexes) antes da próxima rodada
#   • -ForcePublish: mais tentativas + backoff longo (publicação forçada)
#
# Parâmetros:
#   -MaxAttempts 15 (padrão) | -ForcePublish -> 25 tentativas, backoff até 600s
#   -OnlyStorage | -OnlyFirestoreRules | -OnlyFirestoreIndexes (debug)

param(
    [int] $MaxAttempts = 15,
    [switch] $ForcePublish,
    [switch] $OnlyStorage,
    [switch] $OnlyFirestoreRules,
    [switch] $OnlyFirestoreIndexes
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
. (Join-Path $RepoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")
. (Join-Path $RepoRoot "scripts\firebase_rules_preflight.ps1")

$ProjectId = Get-FirebaseDeployProjectId -RepoRoot $RepoRoot

if (-not (Test-Path (Join-Path $RepoRoot "firebase.json"))) {
    Write-Host "Erro: firebase.json nao encontrado na raiz: $RepoRoot" -ForegroundColor Red
    exit 1
}

if ($ForcePublish) {
    if ($MaxAttempts -gt 8) {
        $MaxAttempts = [Math]::Max($MaxAttempts, 25)
        Write-Host "ForcePublish: ate $MaxAttempts tentativas com backoff longo (503 firebaserules)." -ForegroundColor Yellow
    } else {
        Write-Host "ForcePublish: max $MaxAttempts tentativas (deploy completo — web/AAB nao bloqueia)." -ForegroundColor Yellow
    }
}

$BackoffSec = @(15, 30, 60, 90, 120, 150, 180, 240, 300, 300, 360, 420, 480, 540, 600)
while ($BackoffSec.Count -lt $MaxAttempts) {
    $BackoffSec += 600
}

$script:SessionStorageOk = $false
$script:SessionFirestoreRulesOk = $false
$script:SessionFirestoreIndexesOk = $false

function Get-FirebaseDeployFailureKind {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return "unknown" }
    $t = $OutputText.ToLowerInvariant()
    if ($t -match 'firebaserules\.googleapis\.com.*/test' -and $t -match '503|504|429|unavailable') {
        return "rules_test_503"
    }
    if ($t -match 'firebaserules\.googleapis\.com.*/releases' -and $t -match '409|already exists') {
        return "rules_release_409"
    }
    if ($t -match 'firebaserules\.googleapis\.com' -and $t -match '503|504|429|unavailable') {
        return "rules_api_unavailable"
    }
    if ($t -match 'firestore\.googleapis\.com.*/indexes' -and $t -match '409|already exists') {
        return "firestore_index_409"
    }
    if ($t -match '503|504|429|service is currently unavailable|unavailable|timeout|timed out|econnreset') {
        return "transient"
    }
    if ($t -match '409|already exists') { return "conflict_409" }
    return "other"
}

function Test-FirebaseRulesDeployNonRetryable {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return $false }
    $t = $OutputText.ToLowerInvariant()
    if ($t -match 'requires login|please login|not logged in|authentication error|invalid credentials|invalid grant') {
        return $true
    }
    if ($t -match 'could not find rules|rules file.*not found|project not found|invalid project') {
        return $true
    }
    if ($t -match 'error compiling rules|rules compilation failed|failed to compile') {
        return $true
    }
    return $false
}

function Test-FirebaseStorageRulesOk {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return $false }
    $t = $OutputText
    return (
        ($t -match 'released rules storage\.rules') -or
        ($t -match 'latest version of storage\.rules already up to date')
    )
}

function Test-FirebaseFirestoreRulesOk {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return $false }
    $t = $OutputText
    $releaseConflictOk = (
        ($t -match 'compiled successfully') -and
        ($t -match 'firebaserules\.googleapis\.com.*/releases') -and
        ($t -match '409|already exists')
    )
    return (
        ($t -match 'released rules firestore\.rules') -or
        ($t -match 'latest version of firestore\.rules already up to date') -or
        $releaseConflictOk
    )
}

function Test-FirebaseFirestoreIndexesOk {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return $false }
    $t = $OutputText
    if ($t -match 'deployed indexes in firestore\.indexes\.json successfully') { return $true }
    if ($t -match 'index already exists') { return $true }
    if ($t -match 'there are \d+ indexes defined in your project that are not present') {
        return $true
    }
    return $false
}

function Test-FirebaseRulesDeployEffectiveSuccess {
    return (
        $script:SessionStorageOk -and
        $script:SessionFirestoreRulesOk -and
        $script:SessionFirestoreIndexesOk
    )
}

function Update-SessionFlagsFromText {
    param([string] $OutputText)
    if (Test-FirebaseStorageRulesOk -OutputText $OutputText) {
        $script:SessionStorageOk = $true
    }
    if (Test-FirebaseFirestoreRulesOk -OutputText $OutputText) {
        $script:SessionFirestoreRulesOk = $true
    }
    if (Test-FirebaseFirestoreIndexesOk -OutputText $OutputText) {
        $script:SessionFirestoreIndexesOk = $true
    }
}

function Invoke-FirebaseDeployCapture {
    param([string] $OnlyTarget)
    $lines = & firebase deploy --only $OnlyTarget 2>&1
    foreach ($line in $lines) { Write-Host $line }
    return @{ Exit = $LASTEXITCODE; Text = ($lines | Out-String) }
}

function Get-MicroRetryWaitSec {
    param(
        [int] $InnerAttempt,
        [string] $Kind,
        [switch] $ForcePublish
    )
    $base = if ($ForcePublish) { 75 } else { 45 }
    $wait = $base + (($InnerAttempt - 1) * 35) + (Get-Random -Maximum 25)
    if ($Kind -eq 'rules_test_503' -or $Kind -eq 'rules_api_unavailable') {
        $min = if ($ForcePublish) { 55 } else { 35 }
        $wait = [Math]::Max($wait, $min)
    }
    if ($Kind -eq 'rules_release_409' -or $Kind -eq 'conflict_409') {
        $wait = [Math]::Max($wait, 120)
    }
    return $wait
}

function Invoke-FirebaseTargetResilient {
    param(
        [string] $OnlyTarget,
        [string] $Label,
        [int] $InnerAttempts = 6,
        [switch] $ForcePublish
    )
    $accum = ""
    $lastKind = "unknown"
    $lastExit = 1

    for ($inner = 1; $inner -le $InnerAttempts; $inner++) {
        if ($inner -gt 1) {
            $wait = Get-MicroRetryWaitSec -InnerAttempt $inner -Kind $lastKind -ForcePublish:$ForcePublish
            Write-Host "   ... micro-retry $inner/$InnerAttempts ($Label), aguardar ${wait}s ($lastKind) ..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds $wait
        }

        Write-Host (
            "   [{0}] firebase deploy --only {1} (micro {2}/{3}) ..." -f $Label, $OnlyTarget, $inner, $InnerAttempts
        ) -ForegroundColor DarkGray
        $r = Invoke-FirebaseDeployCapture -OnlyTarget $OnlyTarget
        $accum += $r.Text
        $lastExit = $r.Exit
        $lastKind = Get-FirebaseDeployFailureKind -OutputText $r.Text
        Update-SessionFlagsFromText -OutputText $accum

        $ok = switch ($OnlyTarget) {
            'storage' { $script:SessionStorageOk }
            'firestore:rules' { $script:SessionFirestoreRulesOk }
            'firestore:indexes' { $script:SessionFirestoreIndexesOk }
            default { $false }
        }
        if ($ok) {
            return @{ Exit = 0; Text = $accum; Kind = $lastKind }
        }

        if (Test-FirebaseRulesDeployNonRetryable -OutputText $accum) {
            return @{ Exit = $lastExit; Text = $accum; Kind = 'fatal' }
        }

        # Erro não-transiente: não insistir em micro-retries
        if ($lastKind -eq 'other' -and $lastExit -ne 0) {
            break
        }
    }

    return @{ Exit = $lastExit; Text = $accum; Kind = $lastKind }
}

function Invoke-FirebaseDeployGranular {
    param([switch] $ForcePublish)

    $allText = ""
    $innerMax = if ($ForcePublish) {
        if ($MaxAttempts -le 6) { 2 } else { 5 }
    } else { 4 }

    if (-not $OnlyFirestoreRules -and -not $OnlyFirestoreIndexes) {
        if (-not $script:SessionStorageOk) {
            $s = Invoke-FirebaseTargetResilient -OnlyTarget 'storage' -Label 'storage' -InnerAttempts 3 -ForcePublish:$ForcePublish
            $allText += $s.Text
            if ($s.Kind -eq 'fatal') { return @{ Exit = $s.Exit; Text = $allText } }
        }
        else {
            Write-Host "   [storage] ja OK nesta sessao - skip" -ForegroundColor DarkGray
        }
    }

    # Regras antes de indices: publicar rules libera compilacao remota; indices evita /test repetido.
    if (-not $OnlyStorage -and -not $OnlyFirestoreIndexes) {
        if (-not $script:SessionFirestoreRulesOk) {
            Start-Sleep -Seconds 1
            $r = Invoke-FirebaseTargetResilient -OnlyTarget 'firestore:rules' -Label 'firestore:rules' -InnerAttempts $innerMax -ForcePublish:$ForcePublish
            $allText += $r.Text
            if ($r.Kind -eq 'fatal') { return @{ Exit = $r.Exit; Text = $allText } }
            if (-not $script:SessionFirestoreRulesOk -and ($r.Kind -eq 'rules_test_503' -or $r.Kind -eq 'rules_api_unavailable')) {
                Write-Host '   [fallback] REST publish firestore.rules (contorna CLI /test 503)...' -ForegroundColor DarkYellow
                $rest = Publish-FirestoreRulesViaRest -RepoRoot $RepoRoot -ProjectId $ProjectId
                $allText += $rest.Text
                if ($rest.Ok) {
                    $script:SessionFirestoreRulesOk = $true
                    if ($pf.FirestoreIndexesOk) {
                        $script:SessionFirestoreIndexesOk = $true
                    }
                    Write-Host '   [fallback] firestore.rules publicadas via REST.' -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "   [firestore:rules] ja OK nesta sessao - skip" -ForegroundColor DarkGray
        }
    }

    if (-not $OnlyStorage -and -not $OnlyFirestoreRules) {
        if (-not $script:SessionFirestoreIndexesOk) {
            if (-not $script:SessionFirestoreRulesOk -and $MaxAttempts -le 6) {
                Write-Host "   [firestore:indexes] skip (rules pendentes + deploy completo; evita /test 503)" -ForegroundColor DarkYellow
            } else {
            Start-Sleep -Seconds 1
            $i = Invoke-FirebaseTargetResilient -OnlyTarget 'firestore:indexes' -Label 'firestore:indexes' -InnerAttempts $innerMax -ForcePublish:$ForcePublish
            $allText += $i.Text
            if ($i.Kind -eq 'fatal') { return @{ Exit = $i.Exit; Text = $allText } }
            }
        }
        else {
            Write-Host "   [firestore:indexes] ja OK nesta sessao - skip" -ForegroundColor DarkGray
        }
    }

    $effectiveOk = Test-FirebaseRulesDeployEffectiveSuccess
    $exit = if ($effectiveOk) { 0 } else { 1 }
    return @{ Exit = $exit; Text = $allText }
}

function Invoke-FirebaseDeployCombined {
    $lines = & firebase deploy --only "firestore,storage" 2>&1
    foreach ($line in $lines) { Write-Host $line }
    $text = ($lines | Out-String)
    Update-SessionFlagsFromText -OutputText $text
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and (Test-FirebaseRulesDeployEffectiveSuccess)) {
        Write-Host ('   (aviso) CLI exit {0} mas tudo ja em producao - OK.' -f $exit) -ForegroundColor DarkYellow
        $exit = 0
    }
    return @{ Exit = $exit; Text = $text }
}

function Write-FailureKindHint {
    param([string] $Kind)
    switch ($Kind) {
        'rules_test_503' {
            Write-Host '   Causa: API Rules /test (503) - compilacao remota; micro-retry + backoff longo.' -ForegroundColor DarkYellow
        }
        'rules_api_unavailable' {
            Write-Host '   Causa: firebaserules.googleapis.com indisponivel - retry (nao e falha das regras locais).' -ForegroundColor DarkYellow
        }
        'rules_release_409' {
            Write-Host '   Causa: release 409 apos deploy parcial - aguardar e repetir so firestore:rules.' -ForegroundColor DarkYellow
        }
        'firestore_index_409' {
            Write-Host '   Causa: indice ja existe (409) - inofensivo se indexes.json nao mudou.' -ForegroundColor DarkYellow
        }
        'conflict_409' {
            Write-Host '   Causa: recurso 409 - aguardar sincronizacao Google.' -ForegroundColor DarkYellow
        }
    }
}

function Write-SessionStatus {
    Write-Host ("   Estado: storage={0} rules={1} indexes={2}" -f `
            $(if ($script:SessionStorageOk) { 'OK' } else { '...' }), `
            $(if ($script:SessionFirestoreRulesOk) { 'OK' } else { '...' }), `
            $(if ($script:SessionFirestoreIndexesOk) { 'OK' } else { '...' })) -ForegroundColor DarkGray
}

function Save-DeployStateIfSuccess {
    if (-not (Test-FirebaseRulesDeployEffectiveSuccess)) { return }
    Write-DeployState -RepoRoot $RepoRoot `
        -FirestoreRulesSha (Get-LocalFileSha256 (Join-Path $RepoRoot 'firestore.rules')) `
        -StorageRulesSha (Get-LocalFileSha256 (Join-Path $RepoRoot 'storage.rules')) `
        -IndexesSha (Get-LocalFileSha256 (Join-Path $RepoRoot 'firestore.indexes.json'))
}

Write-Host "=== Google Cloud auth (gcloud / conta de servico) ===" -ForegroundColor Cyan
Ensure-GoogleCloudAuth -RepoRoot $RepoRoot

Write-Host "=== Preflight (skip /test se ja sincronizado) ===" -ForegroundColor Cyan
$pf = Invoke-FirebaseRulesPreflight -RepoRoot $RepoRoot -VerbosePreflight
if ($pf.AllOk) {
    $script:SessionStorageOk = $true
    $script:SessionFirestoreRulesOk = $true
    $script:SessionFirestoreIndexesOk = $true
    Write-Host "`n=== Concluido (preflight) | sem chamar firebaserules.googleapis.com/test ===" -ForegroundColor Green
    Write-SessionStatus
    Write-Host "Console: https://console.firebase.google.com/project/$ProjectId/overview" -ForegroundColor DarkGray
    exit 0
}
Write-Host "   $($pf.Message)" -ForegroundColor DarkGray

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "=== firebase deploy rules (tentativa $attempt de $MaxAttempts) ===" -ForegroundColor Cyan
    Write-SessionStatus

    $r = Invoke-FirebaseDeployGranular -ForcePublish:$ForcePublish
    $text = $r.Text
    $exit = $r.Exit
    Update-SessionFlagsFromText -OutputText $text

    if ($exit -eq 0 -or (Test-FirebaseRulesDeployEffectiveSuccess)) {
        Save-DeployStateIfSuccess
        Write-Host "`n=== Concluido | Firestore (rules + indexes) + Storage rules ===" -ForegroundColor Green
        Write-SessionStatus
        Write-Host "Console: https://console.firebase.google.com/project/$ProjectId/overview" -ForegroundColor DarkGray
        exit 0
    }

    if (Test-FirebaseRulesDeployNonRetryable -OutputText $text) {
        Write-Host "`nErro nao recuperavel (login/projeto/compilacao); sem mais retries." -ForegroundColor Red
        exit $exit
    }

    if ($attempt -ge ($MaxAttempts - 2)) {
        Write-Host "   (estrategia final) deploy combinado firestore+storage ..." -ForegroundColor DarkYellow
        $r2 = Invoke-FirebaseDeployCombined
        $text += $r2.Text
        if ($r2.Exit -eq 0 -or (Test-FirebaseRulesDeployEffectiveSuccess)) {
            Save-DeployStateIfSuccess
            Write-Host "`n=== Concluido (combinado) ===" -ForegroundColor Green
            exit 0
        }
        $exit = $r2.Exit
    }

    if ($attempt -ge $MaxAttempts) {
        Write-Host "`nEsgotadas as $MaxAttempts tentativas." -ForegroundColor Red
        Write-SessionStatus
        Write-Host "503 na API Google: https://status.firebase.google.com/" -ForegroundColor DarkGray
        Write-Host "Repita: .\scripts\deploy_firebase_rules.ps1 -ForcePublish" -ForegroundColor DarkGray
        Start-FirebaseRulesBackgroundRetry -RepoRoot $RepoRoot
        exit $exit
    }

    $kind = Get-FirebaseDeployFailureKind -OutputText $text
    Write-FailureKindHint -Kind $kind

    $idx = [Math]::Min($attempt - 1, $BackoffSec.Length - 1)
    $wait = $BackoffSec[$idx]
    if ($kind -eq 'rules_test_503' -or $kind -eq 'rules_api_unavailable') {
        $minRulesApiWait = if ($ForcePublish) { 90 } else { 60 }
        $wait = [Math]::Max($wait, $minRulesApiWait)
    }
    if ($kind -eq 'rules_release_409' -or $kind -eq 'conflict_409') {
        $wait = [Math]::Max($wait, 90)
    }
    $wait += Get-Random -Maximum 30

    Write-Host "`nAguardar ${wait}s antes da proxima rodada..." -ForegroundColor Yellow
    Start-Sleep -Seconds $wait
}

exit 1
