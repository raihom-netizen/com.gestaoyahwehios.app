$f = Get-Item "c:\gestao_yahweh_premium_final\artifacts\deploy_completo_build2066_retry.log"
Write-Output $f.Length
Write-Output ($f.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss"))
