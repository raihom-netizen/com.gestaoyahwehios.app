# Deploy Firestore (rules + indexes) + Storage rules — Gestão YAHWEH
# Execute na raiz do repo:  .\scripts\deploy_firebase_rules.ps1
#
# Erros frequentes (NÃO são bug do firestore.rules / storage.rules locais):
#   • 503/504/429 em firebaserules.googleapis.com — API Google de Rules (test/rulesets/releases)
#   • 409 em .../releases — conflito ao republicar o mesmo release após deploy parcial (retry rápido)
#   • 409 em firestore.googleapis.com/.../indexes — índice já existe (tratado como OK se já implantado)
#
# Estratégia: deploy granular (storage → firestore:rules → firestore:indexes) + deteção de sucesso
# efectivo mesmo com exit != 0 quando as regras já foram libertadas.
# Parâmetro: -MaxAttempts 10 (padrão)

param(
    [int] $MaxAttempts = 10
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
. (Join-Path $RepoRoot "scripts\ensure_gestao_yahweh_toolchain_path.ps1")

if (-not (Test-Path (Join-Path $RepoRoot "firebase.json"))) {
    Write-Host "Erro: firebase.json nao encontrado na raiz: $RepoRoot" -ForegroundColor Red
    exit 1
}

$BackoffSec = @(10, 20, 45, 60, 90, 120, 120, 180, 180, 240)

function Get-FirebaseDeployFailureKind {
    param([string] $OutputText)
    if ([string]::IsNullOrWhiteSpace($OutputText)) { return "unknown" }
    $t = $OutputText.ToLowerInvariant()
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
    # 409 em .../releases apos "compiled successfully" = release ja existe (deploy parcial anterior)
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
        # Apenas aviso de índice extra no projeto — não bloqueia se rules OK
        return $true
    }
    return $false
}

function Test-FirebaseRulesDeployEffectiveSuccess {
    param([string] $OutputText)
    return (
        (Test-FirebaseStorageRulesOk -OutputText $OutputText) -and
        (Test-FirebaseFirestoreRulesOk -OutputText $OutputText) -and
        (Test-FirebaseFirestoreIndexesOk -OutputText $OutputText)
    )
}

function Invoke-FirebaseDeployCapture {
    param([string] $OnlyTarget)
    $lines = & firebase deploy --only $OnlyTarget 2>&1
    foreach ($line in $lines) { Write-Host $line }
    return @{ Exit = $LASTEXITCODE; Text = ($lines | Out-String) }
}

function Invoke-FirebaseDeployGranular {
    $allText = ""
    $worstExit = 0

    Write-Host "   [granular] storage (storage.rules) ..." -ForegroundColor DarkGray
    $s = Invoke-FirebaseDeployCapture -OnlyTarget "storage"
    $allText += $s.Text
    if ($s.Exit -ne 0 -and -not (Test-FirebaseStorageRulesOk -OutputText $s.Text)) {
        $worstExit = $s.Exit
        return @{ Exit = $worstExit; Text = $allText }
    }

    Start-Sleep -Seconds 3

    Write-Host "   [granular] firestore:rules (firebaserules API) ..." -ForegroundColor DarkGray
    $r = Invoke-FirebaseDeployCapture -OnlyTarget "firestore:rules"
    $allText += $r.Text
    if ($r.Exit -ne 0 -and -not (Test-FirebaseFirestoreRulesOk -OutputText $r.Text)) {
        if ($worstExit -eq 0) { $worstExit = $r.Exit }
    }
    if (-not (Test-FirebaseFirestoreRulesOk -OutputText $allText)) {
        return @{ Exit = $worstExit; Text = $allText }
    }

    Start-Sleep -Seconds 3

    Write-Host "   [granular] firestore:indexes (firestore.googleapis.com) ..." -ForegroundColor DarkGray
    $i = Invoke-FirebaseDeployCapture -OnlyTarget "firestore:indexes"
    $allText += $i.Text
    if ($i.Exit -ne 0 -and -not (Test-FirebaseFirestoreIndexesOk -OutputText $i.Text)) {
        if ($worstExit -eq 0) { $worstExit = $i.Exit }
    }

    $effectiveOk = Test-FirebaseRulesDeployEffectiveSuccess -OutputText $allText
    $exit = if ($effectiveOk) { 0 } else { if ($worstExit -ne 0) { $worstExit } else { $i.Exit } }
    return @{ Exit = $exit; Text = $allText }
}

function Invoke-FirebaseDeployCombined {
    $lines = & firebase deploy --only "firestore,storage" 2>&1
    foreach ($line in $lines) { Write-Host $line }
    $text = ($lines | Out-String)
    $exit = $LASTEXITCODE
    if ($exit -ne 0 -and (Test-FirebaseRulesDeployEffectiveSuccess -OutputText $text)) {
        Write-Host ('   (aviso) CLI exit {0} mas regras/indexes ja estao em producao - OK.' -f $exit) -ForegroundColor DarkYellow
        $exit = 0
    }
    return @{ Exit = $exit; Text = $text }
}

function Write-FailureKindHint {
    param([string] $Kind)
    if ($Kind -eq 'rules_api_unavailable') {
        Write-Host '   Causa: API Google Firebase Rules (firebaserules.googleapis.com) indisponivel - retry automatico.' -ForegroundColor DarkYellow
    }
    elseif ($Kind -eq 'rules_release_409') {
        Write-Host '   Causa: conflito 409 no release cloud.firestore (deploy parcial + retry rapido). Aguardar mais.' -ForegroundColor DarkYellow
    }
    elseif ($Kind -eq 'firestore_index_409') {
        Write-Host '   Causa: indice Firestore ja existe (409) - inofensivo se indexes.json nao mudou.' -ForegroundColor DarkYellow
    }
    elseif ($Kind -eq 'conflict_409') {
        Write-Host '   Causa: recurso ja existe (409) - aguardar sincronizacao Google.' -ForegroundColor DarkYellow
    }
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    Write-Host "=== firebase deploy rules (tentativa $attempt de $MaxAttempts) ===" -ForegroundColor Cyan
    Write-Host "APIs: firebaserules.googleapis.com (rules) + firestore.googleapis.com (indexes) + storage rules" -ForegroundColor DarkGray

    # Granular primeiro (menos 503/409 que firestore+storage num unico comando)
    $r = Invoke-FirebaseDeployGranular
    $text = $r.Text
    $exit = $r.Exit

    if ($exit -eq 0) {
        Write-Host "`n=== Concluido | Firestore (rules + indexes) + Storage rules ===" -ForegroundColor Green
        Write-Host "Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview" -ForegroundColor DarkGray
        exit 0
    }

    if (Test-FirebaseRulesDeployNonRetryable -OutputText $text) {
        Write-Host "`nErro nao recuperavel (login/projeto/compilacao regras); nao ha mais retries." -ForegroundColor Red
        exit $exit
    }

    if (Test-FirebaseRulesDeployEffectiveSuccess -OutputText $text) {
        Write-Host "`n=== Concluido (sucesso efectivo apesar de exit $exit) ===" -ForegroundColor Green
        Write-Host "Console: https://console.firebase.google.com/project/gestaoyahweh-21e23/overview" -ForegroundColor DarkGray
        exit 0
    }

    # Ultima tentativa: combinado (as vezes passa quando granular falhou so no ultimo passo)
    if ($attempt -ge ($MaxAttempts - 1)) {
        Write-Host "   (ultima estrategia) deploy combinado firestore+storage ..." -ForegroundColor DarkYellow
        $r2 = Invoke-FirebaseDeployCombined
        $text = $text + $r2.Text
        $exit = $r2.Exit
        if ($exit -eq 0 -or (Test-FirebaseRulesDeployEffectiveSuccess -OutputText $text)) {
            Write-Host "`n=== Concluido (combinado) | Firestore + Storage ===" -ForegroundColor Green
            exit 0
        }
    }

    if ($attempt -ge $MaxAttempts) {
        Write-Host "`nEsgotadas as $MaxAttempts tentativas (exit $exit)." -ForegroundColor Red
        Write-Host "Se persistir: https://status.firebase.google.com/ ou Console > Firestore > Rules (deploy manual)." -ForegroundColor DarkGray
        exit $exit
    }

    $kind = Get-FirebaseDeployFailureKind -OutputText $text
    Write-FailureKindHint -Kind $kind

    $idx = [Math]::Min($attempt - 1, $BackoffSec.Length - 1)
    $wait = $BackoffSec[$idx]
    if ($kind -eq "rules_release_409" -or $kind -eq "conflict_409") {
        $wait = [Math]::Max($wait, 90)
    }

    Write-Host "`nAguardar ${wait}s antes da proxima tentativa..." -ForegroundColor Yellow
    Start-Sleep -Seconds $wait
}

exit 1
