& "$PSScriptRoot\package_ios_sources_zip.ps1" -CopyTo "D:\Temporarios"
$code = $LASTEXITCODE
Write-Output "EXIT_CODE=$code"
Get-ChildItem "D:\Temporarios" -Filter "GestaoYahweh_ios_sources_11.2.305_build2066.zip" | Select-Object FullName,Length,LastWriteTime | Format-List
exit $code
