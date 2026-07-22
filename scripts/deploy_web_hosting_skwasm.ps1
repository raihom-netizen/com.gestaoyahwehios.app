# Deploy web Gestão YAHWEH -- Skwasm (bundle inicial mais leve em browsers modernos)
# Alternativa ao CanvasKit padrão: ver scripts/deploy_web_hosting.ps1 (FLUTTER_WEB_USE_SKIA=true)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "ensure_gestao_yahweh_toolchain_path.ps1")

Push-Location (Join-Path $root "flutter_app")
try {
  flutter pub get
  Write-Host "`n=== flutter build web --release (Skwasm) ===" -ForegroundColor Cyan
  flutter build web --release --no-tree-shake-icons --pwa-strategy=none `
    --dart-define=FLUTTER_WEB_USE_SKIA=false `
    --dart-define=FLUTTER_WEB_USE_SKWASM=true
}
finally {
  Pop-Location
}

Push-Location $root
try {
  firebase deploy --only hosting
  Write-Host "`nWeb: https://gestaoyahweh-21e23.web.app (Ctrl+F5)" -ForegroundColor Green
}
finally {
  Pop-Location
}
