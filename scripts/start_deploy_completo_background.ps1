# Inicia deploy completo em processo separado (nao fecha se o terminal do IDE cair).
# Uso (raiz):
#   .\scripts\start_deploy_completo_background.ps1
# Retomar apos regras+functions OK:
#   .\scripts\start_deploy_completo_background.ps1 -SkipRules -SkipFunctionsDeploy
# Ver progresso (UTF-8):
#   Get-Content D:\Temporarios\deploy_completo_latest.log -Wait -Tail 40 -Encoding UTF8

param(
    [string] $CopyTo = 'D:\Temporarios',
    [switch] $SkipGitPush,
    [switch] $ForceFunctions,
    [switch] $ForceClean,
    [switch] $SkipProductionGate,
    [switch] $SkipRules,
    [switch] $SkipFunctionsDeploy,
    [switch] $SkipWeb
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path $CopyTo)) {
    New-Item -ItemType Directory -Path $CopyTo -Force | Out-Null
}

$logPath = Join-Path $CopyTo 'deploy_completo_latest.log'
$errPath = Join-Path $CopyTo 'deploy_completo_latest.err'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
@(
    "=== Deploy iniciado $stamp ===",
    "Repo: $RepoRoot",
    "CopyTo: $CopyTo",
    "SkipRules: $SkipRules",
    "SkipFunctionsDeploy: $SkipFunctionsDeploy",
    ""
) | Set-Content -Path $logPath -Encoding UTF8
Set-Content -Path $errPath -Value '' -Encoding UTF8

$deployScript = Join-Path $RepoRoot 'scripts\deploy_completo.ps1'
$psArgs = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $deployScript,
    '-CopyTo', $CopyTo
)
if ($SkipGitPush)           { $psArgs += '-SkipGitPush' }
if ($ForceFunctions)        { $psArgs += '-ForceFunctions' }
if ($ForceClean)            { $psArgs += '-ForceClean' }
if ($SkipProductionGate)    { $psArgs += '-SkipProductionGate' }
if ($SkipRules)             { $psArgs += '-SkipRules' }
if ($SkipFunctionsDeploy)   { $psArgs += '-SkipFunctionsDeploy' }
if ($SkipWeb)               { $psArgs += '-SkipWeb' }

$p = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList $psArgs `
    -WorkingDirectory $RepoRoot `
    -PassThru `
    -WindowStyle Minimized `
    -RedirectStandardOutput $logPath `
    -RedirectStandardError $errPath

Write-Host "Deploy em background (PID $($p.Id))." -ForegroundColor Green
Write-Host "Log:  $logPath" -ForegroundColor Cyan
Write-Host "Erro: $errPath" -ForegroundColor DarkGray
Write-Host "Acompanhar: Get-Content '$logPath' -Wait -Tail 40 -Encoding UTF8" -ForegroundColor DarkGray
