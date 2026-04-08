@echo off
setlocal

echo ============================================
echo  GESTAO YAHWEH - Setup automatico (Windows)
echo ============================================

where node >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Node.js nao encontrado. Instale em https://nodejs.org (LTS) e rode novamente.
  pause
  exit /b 1
)

where firebase >nul 2>nul
if errorlevel 1 (
  echo [INFO] Instalando Firebase CLI...
  npm install -g firebase-tools
)

echo [OK] Firebase CLI:
firebase --version

echo.
echo [PASSO] Login no Firebase (vai abrir o navegador)...
firebase login

echo.
echo [PASSO] Gerando firebase_options.dart (FlutterFire)...
cd flutter_app
call flutter pub get
call flutterfire configure --project=gestaoyahweh-21e23
cd ..

echo.
echo [PASSO] Instalando dependencias das Cloud Functions...
cd functions
call npm install
call npm run build
cd ..

echo.
echo [PASSO] Deploy das Cloud Functions (necessario para login CPF e onboarding)...
firebase deploy --only functions

echo.
echo [PASSO] Rodando Flutter (Chrome)...
cd flutter_app
call flutter clean
call flutter pub get
call flutter run -d chrome

endlocal
