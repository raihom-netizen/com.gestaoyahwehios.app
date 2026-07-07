@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\gestao_yahweh_premium_final\scripts\_trigger_ios_then_check.ps1"
exit /b %errorlevel%
