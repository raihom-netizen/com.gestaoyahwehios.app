# Publica config/appVersion no Firestore — forceUpdate + webRefresh para build atual.
# Uso (raiz): .\scripts\publish_force_update_online.ps1
# Requer: Application Default Credentials (gcloud auth application-default login)
#         ou GOOGLE_APPLICATION_CREDENTIALS apontando para service account.

param(
    [string] $Project = 'gestaoyahweh-21e23'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FlutterApp = Join-Path $RepoRoot 'flutter_app'
$pubspec = Join-Path $FlutterApp 'pubspec.yaml'
$pubContent = Get-Content $pubspec -Raw -Encoding UTF8
if ($pubContent -notmatch 'version:\s*([\d.]+)\+(\d+)') {
    Write-Error 'Nao foi possivel ler version em pubspec.yaml'
    exit 1
}
$marketing = $Matches[1]
$buildNum = [int]$Matches[2]
$full = "$marketing+$buildNum"

$FunctionsDir = Join-Path $RepoRoot 'functions'
if (-not (Test-Path (Join-Path $FunctionsDir 'node_modules\firebase-admin'))) {
    Push-Location $FunctionsDir
    try {
        if (Test-Path 'package-lock.json') { npm ci 2>&1 | Out-Host }
        else { npm install 2>&1 | Out-Host }
    } finally { Pop-Location }
}

$nodeScript = @"
const admin = require('firebase-admin');
admin.initializeApp({ projectId: '$Project' });
const payload = {
  minVersion: '$marketing',
  minBuildNumber: $buildNum,
  latestVersion: '$full',
  publishedBuild: '$full',
  forceUpdate: true,
  webRefresh: true,
  message: 'Atualizacao obrigatoria disponivel. Instale a versao $full para continuar.',
  panelUpdateMessage: 'Nova versao $full — atualize para a melhor experiencia.',
  storeUrlAndroid: 'https://play.google.com/store/apps/details?id=com.gestaoyahweh.app',
  storeUrlIos: 'https://testflight.apple.com/join/4Zdptnh8',
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
};
admin.firestore().doc('config/appVersion').set(payload, { merge: true })
  .then(() => { console.log('OK config/appVersion', '$full', 'forceUpdate=true'); process.exit(0); })
  .catch((e) => { console.error(e); process.exit(1); });
"@

$tmp = Join-Path $FunctionsDir ("_force_update_" + [Guid]::NewGuid().ToString('N') + '.js')
Set-Content -Path $tmp -Value $nodeScript -Encoding UTF8
Push-Location $FunctionsDir
try {
    node (Split-Path -Leaf $tmp)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host "Force update publicado: $full (projeto $Project)" -ForegroundColor Green
