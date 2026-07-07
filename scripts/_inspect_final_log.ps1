$src = 'c:\gestao_yahweh_premium_final\artifacts\deploy_completo_build2066_final.log'
if (-not (Test-Path $src)) { Write-Output 'MISSING_LOG'; exit 1 }
Get-Content -Path $src -Encoding Unicode -Tail 220
