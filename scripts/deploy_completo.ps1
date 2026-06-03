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

param(
    [string] $CopyTo = 'D:\Temporarios',
    [switch] $SkipGitPush,
    [switch] $ForceFunctions,
    [switch] $ForceClean,
    [switch] $ForceFirestoreRules,
    [switch] $SkipProductionGate
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

& $release @invokeArgs
exit $LASTEXITCODE
