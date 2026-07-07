@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\gestao_yahweh_premium_final\scripts\package_ios_sources_zip.ps1" -CopyTo "D:\Temporarios"
if exist "D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2066.zip" powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Item 'D:\Temporarios\GestaoYahweh_ios_sources_11.2.305_build2066.zip' | Select-Object FullName,Length,LastWriteTime | Format-List"
exit /b %errorlevel%
