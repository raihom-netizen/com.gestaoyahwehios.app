@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~1"
exit /b %errorlevel%
