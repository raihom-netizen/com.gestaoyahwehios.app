$f = Get-Item "c:\gestao_yahweh_premium_final\artifacts\deploy_completo_after_fix.log"
Write-Output $f.Length
Write-Output ($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))