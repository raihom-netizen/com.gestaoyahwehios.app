# Deploy Firebase YAHWEH: hosting + firestore + storage (+ functions opcional).
# Padrao Controle Total — token CI automatico (.firebase-ci-token / FIREBASE_TOKEN).
param(
    [string]$Root = (Split-Path $PSScriptRoot -Parent),
    [switch]$HostingOnly,
    [switch]$FunctionsOnly,
    [switch]$SkipFunctions
)

$ErrorActionPreference = "Stop"
Set-Location $Root

$firebaseCmd = $null
$cmdPath = Join-Path $env:APPDATA 'npm\firebase.cmd'
if (Test-Path $cmdPath) { $firebaseCmd = $cmdPath }
elseif (Get-Command firebase -ErrorAction SilentlyContinue) { $firebaseCmd = 'firebase' }
else { throw "Firebase CLI nao encontrado. Instale: npm i -g firebase-tools" }

$tokenFile = Join-Path $Root ".firebase-ci-token"
if (-not $env:FIREBASE_TOKEN -and (Test-Path $tokenFile)) {
    $env:FIREBASE_TOKEN = (Get-Content $tokenFile -Raw).Trim()
}

$eap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$projectArgs = @('--project', 'gestaoyahweh-21e23', '--non-interactive')

if ($FunctionsOnly) {
    & $firebaseCmd deploy --only functions @projectArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($code -ne 0) { throw "firebase deploy functions falhou ($code)" }
    return
}

if ($HostingOnly) {
    & $firebaseCmd deploy --only hosting @projectArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($code -ne 0) { throw "firebase deploy hosting falhou ($code)" }
    return
}

& $firebaseCmd deploy --only "hosting,firestore,storage" @projectArgs
if ($LASTEXITCODE -ne 0) {
    $ErrorActionPreference = $eap
    throw "firebase deploy hosting/firestore/storage falhou ($LASTEXITCODE)"
}

if (-not $SkipFunctions) {
    if (-not $env:FUNCTIONS_DISCOVERY_TIMEOUT) { $env:FUNCTIONS_DISCOVERY_TIMEOUT = "90" }
    & $firebaseCmd deploy --only functions @projectArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = $eap
    if ($code -ne 0) { throw "firebase deploy functions falhou ($code)" }
} else {
    $ErrorActionPreference = $eap
    Write-Host "  Functions puladas (-SkipFunctions)." -ForegroundColor Yellow
}
