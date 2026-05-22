# OPCIONAL — dispara build via API (o normal é Start new build na UI, manual).
# Uso quando a UI fica "Branches are loading" ou prefere linha de comando.
# Uso:
#   $env:CODEMAGIC_API_TOKEN = "..."   # Codemagic → User settings → Integrations → Codemagic API
#   .\scripts\trigger_codemagic_ios_build.ps1
#   .\scripts\trigger_codemagic_ios_build.ps1 -AppId "xxxxxxxx" -WorkflowId "ios-release" -Branch "main"
#
# App ID: Codemagic → app → Application settings → Application ID (ou URL .../app/<APP_ID>/...)
param(
    [string]$AppId = $env:CODEMAGIC_APP_ID,
    [string]$WorkflowId = "ios-release",
    [string]$Branch = "main",
    [string]$ApiToken = $env:CODEMAGIC_API_TOKEN
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ApiToken)) {
    Write-Host "ERRO: defina CODEMAGIC_API_TOKEN (User settings -> Integrations -> Codemagic API)." -ForegroundColor Red
    exit 1
}

$headers = @{
    "x-auth-token"   = $ApiToken.Trim()
    "Content-Type"   = "application/json"
}

if ([string]::IsNullOrWhiteSpace($AppId)) {
    Write-Host "A listar apps Codemagic (defina CODEMAGIC_APP_ID para saltar)..." -ForegroundColor Cyan
    try {
        $apps = Invoke-RestMethod -Uri "https://api.codemagic.io/apps" -Headers $headers -Method Get
    } catch {
        Write-Host "ERRO ao listar apps: $_" -ForegroundColor Red
        exit 1
    }
    $list = @($apps.applications)
    if ($list.Count -eq 0) { $list = @($apps) }
    foreach ($a in $list) {
        $id = $a._id
        if (-not $id) { $id = $a.id }
        $name = $a.appName
        if (-not $name) { $name = $a.name }
        Write-Host "  AppId=$id  name=$name"
    }
    Write-Host ""
    Write-Host "Copie o AppId de com.gestaoyahwehios.app e volte a correr:" -ForegroundColor Yellow
    Write-Host '  $env:CODEMAGIC_APP_ID="..."; .\scripts\trigger_codemagic_ios_build.ps1'
    exit 0
}

$body = @{
    appId      = $AppId.Trim()
    workflowId = $WorkflowId.Trim()
    branch     = $Branch.Trim()
} | ConvertTo-Json -Compress

Write-Host "A disparar build: app=$AppId workflow=$WorkflowId branch=$Branch" -ForegroundColor Cyan
try {
    $resp = Invoke-RestMethod -Uri "https://api.codemagic.io/builds" -Headers $headers -Method Post -Body $body
} catch {
    Write-Host "ERRO API: $_" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message }
    exit 1
}

$buildId = $resp.buildId
if (-not $buildId) { $buildId = $resp._id }
Write-Host "OK: build iniciado." -ForegroundColor Green
if ($buildId) {
    Write-Host "  buildId: $buildId"
    Write-Host "  Abra: https://codemagic.io/apps/$AppId/build/$buildId"
}
