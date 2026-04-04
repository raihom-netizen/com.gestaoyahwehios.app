@echo off
REM Atualiza os ícones do PWA a partir de assets/icon/app_icon.png
cd /d "%~dp0.."
echo Gerando ícones web a partir de assets/icon/app_icon.png...
call flutter pub get
if errorlevel 1 exit /b 1
call dart run flutter_launcher_icons
if errorlevel 1 exit /b 1
echo.
echo Icones atualizados em web/icons/
echo Proximo passo: flutter build web --release e deploy.
pause
