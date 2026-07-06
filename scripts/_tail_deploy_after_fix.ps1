$log = 'c:\gestao_yahweh_premium_final\artifacts\deploy_completo_after_fix.log'
if (-not (Test-Path $log)) {
  Write-Output 'LOG_NOT_FOUND'
  exit 1
}
Get-Content -Path $log -Encoding Unicode -Tail 140
