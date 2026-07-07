Get-ChildItem "c:\gestao_yahweh_premium_final\flutter_app\build\web" -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName,Length,LastWriteTime | Format-List
