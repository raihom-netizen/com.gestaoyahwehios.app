Get-Content "c:\gestao_yahweh_premium_final\flutter_app\web\version.json"
if (Test-Path "c:\gestao_yahweh_premium_final\flutter_app\build\web") { Get-ChildItem "c:\gestao_yahweh_premium_final\flutter_app\build\web" -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName,Length,LastWriteTime | Format-List } else { Write-Output "WEB_BUILD_MISSING" }
