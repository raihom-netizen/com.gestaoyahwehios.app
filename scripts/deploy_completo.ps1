# Entrada única: deploy produção completo (Firebase + AAB + iOS ZIP + Git push Codemagic).
# Na raiz: .\scripts\deploy_completo.ps1
# Ver implementação: deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1
#
# Flags (todos opcionais):
#   -CopyTo "D:\Temporarios"    pasta de saida (AAB + ZIP iOS)
#   -SkipGitPush                pula commit/push final (Codemagic nao recebe)
#   -ForceFunctions             roda deploy de Cloud Functions mesmo
#                               sem alteracao em /functions
#   -ForceClean                 forca `flutter clean` (cache corrompido)

param(
    [string] $CopyTo = 'D:\Temporarios',
    [switch] $SkipGitPush,
    [switch] $ForceFunctions,
    [switch] $ForceClean
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$release = Join-Path $RepoRoot "scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1"
if (-not (Test-Path $release)) {
    Write-Host "Erro: nao encontrado $release" -ForegroundColor Red
    exit 1
}

$args = @('-CopyTo', $CopyTo)
if ($SkipGitPush)    { $args += '-SkipGitPush' }
if ($ForceFunctions) { $args += '-ForceFunctions' }
if ($ForceClean)     { $args += '-ForceClean' }

& $release @args
exit $LASTEXITCODE
