$ErrorActionPreference = 'Stop'
$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
cd "$ROOT\flutter_app"
flutter pub get

Write-Host "==> APK release" -ForegroundColor Cyan
flutter build apk --release

Write-Host "==> AAB release (Play Store)" -ForegroundColor Cyan
flutter build appbundle --release

Write-Host "✅ Android gerado." -ForegroundColor Green
Write-Host "APK: build\app\outputs\flutter-apk\app-release.apk"
Write-Host "AAB: build\app\outputs\bundle\release\app-release.aab"
