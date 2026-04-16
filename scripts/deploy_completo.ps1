# Entrada única: deploy produção completo (Firebase + AAB + iOS ZIP + Git push Codemagic).
# Na raiz: .\scripts\deploy_completo.ps1
# Ver implementação: deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1

param(
    [string] $CopyTo = 'D:\Temporarios',
    [switch] $SkipGitPush
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$release = Join-Path $RepoRoot "scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1"
if (-not (Test-Path $release)) {
    Write-Host "Erro: nao encontrado $release" -ForegroundColor Red
    exit 1
}
if ($SkipGitPush) {
    & $release -CopyTo $CopyTo -SkipGitPush
} else {
    & $release -CopyTo $CopyTo
}
exit $LASTEXITCODE
