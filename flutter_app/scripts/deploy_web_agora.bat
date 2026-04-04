@echo off
REM Deploy web urgente - versao 11.0.32
cd /d "%~dp0.."
echo === Build web (release) ===
call flutter pub get
call flutter build web --release
if errorlevel 1 exit /b 1
cd ..
echo.
echo === Deploy Firebase Hosting ===
call firebase deploy --only hosting
if errorlevel 1 exit /b 1
echo.
echo === Concluido. Web online com versao 11.0.32 ===
pause
