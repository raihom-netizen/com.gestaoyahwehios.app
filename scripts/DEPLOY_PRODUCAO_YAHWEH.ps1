$ErrorActionPreference = 'Stop'

# Raiz do projeto = pasta acima de /scripts (funciona em qualquer pasta, sem hardcode)
$ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Projeto Firebase (pode manter fixo; se vazio, tenta ler o default do .firebaserc)
$PROJECT = "gestaoyahweh-21e23"
if (-not $PROJECT -or $PROJECT.Trim() -eq "") {
  $rc = Join-Path $ROOT ".firebaserc"
  if (Test-Path $rc) {
    try {
      $json = Get-Content $rc -Raw | ConvertFrom-Json
      if ($json.projects.default) { $PROJECT = $json.projects.default }
    } catch {}
  }
}
if (-not $PROJECT -or $PROJECT.Trim() -eq "") {
  throw "Nao consegui detectar o Firebase project. Defina a variavel $PROJECT em: $PSScriptRoot\DEPLOY_PRODUCAO_YAHWEH.ps1"
}

Write-Host "==> Build Functions" -ForegroundColor Cyan
cd "$ROOT\functions"
npm i
npm run build

Write-Host "==> Deploy Firestore rules/indexes + Functions" -ForegroundColor Cyan
cd "$ROOT"
firebase deploy --only "firestore:rules,firestore:indexes,functions" --project $PROJECT

Write-Host "==> Build Flutter Web" -ForegroundColor Cyan
cd "$ROOT\flutter_app"
flutter pub get
flutter build web --release --no-tree-shake-icons --pwa-strategy=none

Write-Host "==> Deploy Hosting" -ForegroundColor Cyan
cd "$ROOT"
firebase deploy --only hosting --project $PROJECT

Write-Host "✅ Deploy produção concluído." -ForegroundColor Green
