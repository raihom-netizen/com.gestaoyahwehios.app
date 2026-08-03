# Grava config/telegram_tdlib no Firestore (Admin SDK).
# Uso (raiz): .\scripts\publish_telegram_tdlib_config.ps1
# Ou: .\scripts\publish_telegram_tdlib_config.ps1 -ApiId 37029102 -ApiHash "...."

param(
    [string] $Project = 'gestaoyahweh-21e23',
    [Parameter(Mandatory = $true)][int] $ApiId,
    [Parameter(Mandatory = $true)][string] $ApiHash,
    [string] $DeviceModel = 'Gestao YAHWEH',
    [string] $SystemLanguageCode = 'pt-br'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FunctionsDir = Join-Path $RepoRoot 'functions'

if ($ApiId -le 0 -or $ApiHash.Trim().Length -lt 16) {
    Write-Error 'ApiId/ApiHash invalidos. Ex.: -ApiId 123 -ApiHash "seu_hash"'
    exit 1
}

if (-not (Test-Path (Join-Path $FunctionsDir 'node_modules\firebase-admin'))) {
    Push-Location $FunctionsDir
    try {
        if (Test-Path 'package-lock.json') { npm ci 2>&1 | Out-Host }
        else { npm install 2>&1 | Out-Host }
    } finally { Pop-Location }
}

$apiHashEsc = $ApiHash.Trim().Replace('\', '\\').Replace("'", "\'")
$deviceEsc = $DeviceModel.Trim().Replace('\', '\\').Replace("'", "\'")
$langEsc = $SystemLanguageCode.Trim().Replace('\', '\\').Replace("'", "\'")

$nodeScript = @"
const admin = require('firebase-admin');
admin.initializeApp({ projectId: '$Project' });
const payload = {
  apiId: $ApiId,
  apiHash: '$apiHashEsc',
  api_id: $ApiId,
  api_hash: '$apiHashEsc',
  deviceModel: '$deviceEsc',
  systemLanguageCode: '$langEsc',
  configured: true,
  source: 'publish_telegram_tdlib_config.ps1',
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedByEmail: 'script@gestao-yahweh',
};
admin.firestore().doc('config/telegram_tdlib').set(payload, { merge: true })
  .then(async () => {
    const snap = await admin.firestore().doc('config/telegram_tdlib').get();
    const d = snap.data() || {};
    console.log('OK config/telegram_tdlib', JSON.stringify({
      apiId: d.apiId,
      apiHashLen: String(d.apiHash || '').length,
      deviceModel: d.deviceModel,
      configured: d.configured,
      exists: snap.exists,
    }));
    process.exit(0);
  })
  .catch((e) => { console.error(e); process.exit(1); });
"@

$tmp = Join-Path $FunctionsDir ("_telegram_tdlib_" + [Guid]::NewGuid().ToString('N') + '.js')
Set-Content -Path $tmp -Value $nodeScript -Encoding UTF8
Push-Location $FunctionsDir
try {
    node (Split-Path -Leaf $tmp)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
}

Write-Host "Telegram TDLib config publicado (projeto $Project)" -ForegroundColor Green
