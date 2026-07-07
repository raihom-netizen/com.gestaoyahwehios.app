Write-Output "START_WEB_2066"
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\gestao_yahweh_premium_final\scripts\deploy_web_hosting.ps1"
Write-Output ("INNER_EXIT=" + $LASTEXITCODE)
Get-Content "c:\gestao_yahweh_premium_final\flutter_app\web\version.json"
if (Test-Path "c:\gestao_yahweh_premium_final\flutter_app\build\web") { Get-ChildItem "c:\gestao_yahweh_premium_final\flutter_app\build\web" -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName,Length,LastWriteTime | Format-List }
exit $LASTEXITCODE
