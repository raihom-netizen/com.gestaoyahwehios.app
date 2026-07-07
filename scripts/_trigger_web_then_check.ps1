& "$PSScriptRoot\deploy_web_hosting.ps1"
$code = $LASTEXITCODE
Write-Output "EXIT_CODE=$code"
if (Test-Path "c:\gestao_yahweh_premium_final\flutter_app\build\web") {
  Get-ChildItem "c:\gestao_yahweh_premium_final\flutter_app\build\web" -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 FullName,Length,LastWriteTime | Format-List
}
Get-Content "c:\gestao_yahweh_premium_final\flutter_app\web\version.json"
exit $code
