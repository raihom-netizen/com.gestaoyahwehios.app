# Entrada unica: deploy producao completo (Firebase + AAB + iOS ZIP + Git push Codemagic).
# Na raiz: .\scripts\deploy_completo.ps1
# Ver implementacao: deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1
#
# Flags (todos opcionais):
#   -CopyTo "D:\Temporarios"    pasta de saida (AAB + ZIP iOS)
#   -SkipGitPush                pula commit/push final (Codemagic nao recebe)
#   -ForceFunctions             roda deploy de Cloud Functions mesmo
#                               sem alteracao em /functions
#   -ForceClean                 forca `flutter clean` (cache corrompido)
#   -SkipProductionGate         pula gate verify_production_checklist.ps1 (emergencia)
#   -ContinueOnRulesFailure     apos tentativas de regras (503 API), segue web+AAB+iOS
#   -SkipRules                  pula [1/6] (retomar deploy apos regras OK)
#   -SkipFunctionsDeploy        pula [2/6] (retomar apos functions OK)
#   -LogTo "D:\Temporarios\deploy.log"  grava saida completa (nao perde se terminal fechar)

param(
    [string] $CopyTo = 'D:\Temporarios',
    [switch] $SkipGitPush,
    [switch] $ForceFunctions,
    [switch] $ForceClean,
    [switch] $ForceFirestoreRules,
    [switch] $SkipProductionGate,
    [switch] $SkipPreflight,
    [switch] $ContinueOnRulesFailure,
    [switch] $SkipRules,
    [switch] $SkipFunctionsDeploy,
    [switch] $SkipWeb,
    [string] $LogTo = ''
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$release = Join-Path $RepoRoot "scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1"
if (-not (Test-Path $release)) {
    Write-Host "Erro: nao encontrado $release" -ForegroundColor Red
    exit 1
}

# Splatting com hashtable (mais robusto que array via $args, que e
# variavel automatica do PowerShell e gera comportamentos inesperados).
$invokeArgs = @{ CopyTo = $CopyTo }
if ($SkipGitPush)    { $invokeArgs.SkipGitPush    = $true }
if ($ForceFunctions)       { $invokeArgs.ForceFunctions       = $true }
if ($ForceClean)           { $invokeArgs.ForceClean           = $true }
if ($ForceFirestoreRules)  { $invokeArgs.ForceFirestoreRules  = $true }
if ($SkipProductionGate)   { $invokeArgs.SkipProductionGate   = $true }
if ($SkipPreflight)        { $invokeArgs.SkipPreflight        = $true }
if ($SkipRules)            { $invokeArgs.SkipRules            = $true }
if ($SkipFunctionsDeploy)  { $invokeArgs.SkipFunctionsDeploy  = $true }
if ($SkipWeb)               { $invokeArgs.SkipWeb               = $true }
if ($LogTo)                { $invokeArgs.LogTo                = $LogTo }

# Padrao otimizado: nao bloquear horas em 503 da API Rules — web/AAB/iOS seguem.
if (-not $PSBoundParameters.ContainsKey('ContinueOnRulesFailure')) {
    $invokeArgs.ContinueOnRulesFailure = $true
}

if ($LogTo -and $LogTo.Trim().Length -gt 0) {
    $logPath = $LogTo.Trim()
    $logDir = Split-Path -Parent $logPath
    if ($logDir -and -not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Write-Host "Log: $logPath" -ForegroundColor DarkGray
    if (Test-Path $logPath) {
        & $release @invokeArgs *>&1 | Tee-Object -FilePath $logPath -Append
    } else {
        & $release @invokeArgs *>&1 | Tee-Object -FilePath $logPath
    }
} else {
    & $release @invokeArgs
}
exit $LASTEXITCODE
