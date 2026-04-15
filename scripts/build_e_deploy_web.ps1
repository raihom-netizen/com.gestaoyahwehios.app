# Build Flutter web e deploy no Firebase Hosting (Gestao YAHWEH)
# Execute na raiz do projeto: .\scripts\build_e_deploy_web.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path "$root\flutter_app\pubspec.yaml")) {
    $root = $PSScriptRoot
}
if (-not (Test-Path "$root\flutter_app\pubspec.yaml")) {
    Write-Host "Erro: pasta flutter_app nao encontrada. Execute na raiz do projeto."
    exit 1
}

Set-Location "$root\flutter_app"
Write-Host ">>> flutter pub get"
flutter pub get
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ">>> flutter build web"
flutter build web --no-tree-shake-icons
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Location $root
Write-Host ">>> firebase deploy --only hosting"
firebase deploy --only hosting
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Concluido. Acesse o site para ver o modulo Frotas atualizado."
