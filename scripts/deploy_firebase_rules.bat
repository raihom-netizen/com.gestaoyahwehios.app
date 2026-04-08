@echo off
REM Atalho Windows: deploy Firestore + Storage rules
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_firebase_rules.ps1"
exit /b %ERRORLEVEL%
