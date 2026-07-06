$ErrorActionPreference = 'Stop'
$src = 'c:\gestao_yahweh_premium_final\artifacts\deploy_completo_run.log'
$dst = 'c:\gestao_yahweh_premium_final\artifacts\deploy_completo_run_utf8.txt'
if (-not (Test-Path $src)) {
  Write-Output 'MISSING_LOG'
  exit 1
}
Get-Content -Path $src -Encoding Unicode | Set-Content -Path $dst -Encoding utf8
Write-Output "OK_CONVERT:$dst"
