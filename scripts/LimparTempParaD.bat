@echo off
REM Joga arquivos temporarios para D:\TEMPORARIOS (pode apagar essa pasta sem medo)
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0LimparTempParaD.ps1" %*
pause
