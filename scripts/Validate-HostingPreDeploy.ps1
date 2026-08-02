# Validacao OBRIGATORIA antes de qualquer deploy do Firebase Hosting (Gestao YAHWEH).
# Garante que o site nao fique fora do ar (Page Not Found).
# Uso: .\scripts\Validate-HostingPreDeploy.ps1

param(
    [string]$Root = ""
)

if ($Root -and (Test-Path (Join-Path $Root "firebase.json"))) {
    $repoRoot = $Root
} elseif (Test-Path (Join-Path $PSScriptRoot "..\firebase.json")) {
    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} elseif (Test-Path "firebase.json") {
    $repoRoot = (Get-Location).Path
} else {
    $repoRoot = (Get-Location).Path
}

$ErrorActionPreference = "Stop"
$failed = $false

$firebaseJsonPath = Join-Path $repoRoot "firebase.json"
if (-not (Test-Path $firebaseJsonPath)) {
    Write-Host "[BLINDAGEM] ERRO: firebase.json nao encontrado. Execute na RAIZ do projeto." -ForegroundColor Red
    exit 1
}
$firebaseContent = Get-Content $firebaseJsonPath -Raw -ErrorAction SilentlyContinue
if (-not ($firebaseContent -match '"public"\s*:\s*"flutter_app/build/web"')) {
    Write-Host "[BLINDAGEM] ERRO: firebase.json deve ter hosting.public = 'flutter_app/build/web'." -ForegroundColor Red
    exit 1
}
Write-Host "[BLINDAGEM] Raiz e firebase.json OK." -ForegroundColor Green

$publicDir = Join-Path $repoRoot "flutter_app\build\web"
$requiredFiles = @("index.html", "flutter_bootstrap.js", "main.dart.js", "version.json")
foreach ($f in $requiredFiles) {
    $path = Join-Path $publicDir $f
    if (-not (Test-Path $path)) {
        Write-Host "[BLINDAGEM] ERRO: Ausente flutter_app\build\web\$f" -ForegroundColor Red
        Write-Host "  Rode build web ou .\deploy.ps1 -WebOnly" -ForegroundColor Yellow
        $failed = $true
    }
}
if ($failed) { exit 1 }
Write-Host "[BLINDAGEM] Arquivos obrigatorios presentes." -ForegroundColor Green

$fileCount = (Get-ChildItem $publicDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
if ($fileCount -lt 10) {
    Write-Host "[BLINDAGEM] ERRO: build/web com poucos arquivos ($fileCount). Build incompleto." -ForegroundColor Red
    exit 1
}
Write-Host "[BLINDAGEM] build/web OK ($fileCount arquivos)." -ForegroundColor Green
exit 0
