@echo off
setlocal
cd /d %~dp0

firebase use gestaoyahweh-21e23

REM ====== Build Flutter Web (atualiza a pasta flutter_app\build\web) ======
cd flutter_app
flutter pub get
flutter build web --release
cd ..

cd functions
npm ci
cd ..

firebase deploy --only hosting,functions,firestore:rules

pause
