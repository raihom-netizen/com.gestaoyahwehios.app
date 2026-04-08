@echo off
REM Sobe a versao automaticamente: app_version.dart, pubspec.yaml e web/version.json
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bump_version.ps1" %*
exit /b %ERRORLEVEL%
