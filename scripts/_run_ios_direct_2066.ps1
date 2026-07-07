& "c:\gestao_yahweh_premium_final\scripts\package_ios_sources_zip.ps1" -CopyTo "D:\Temporarios"
$code = $LASTEXITCODE
Write-Output "EXIT_CODE=$code"
if (Test-Path "D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2066.zip") { Get-Item "D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2066.zip" | Select-Object FullName,Length,LastWriteTime | Format-List } else { Write-Output "ZIP_MISSING" }
exit $code
