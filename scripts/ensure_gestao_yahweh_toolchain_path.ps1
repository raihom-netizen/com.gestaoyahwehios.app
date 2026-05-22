# Coloca Flutter + Firebase CLI + npm no PATH (evita «firebase não reconhecido» no deploy).
# Uso: . .\scripts\ensure_gestao_yahweh_toolchain_path.ps1
# Ou importado automaticamente por deploy_completo / deploy_firebase_rules / deploy_web_hosting.

$root = $env:GESTAO_YAHWEH_TOOLCHAIN_ROOT
if (-not $root -or -not (Test-Path $root)) {
    $root = 'C:\dev\gestao-yahweh-toolchain'
}
$nodeDir = Join-Path $root 'node'
$flutterBin = Join-Path $root 'flutter\bin'
$prepend = @()
if (Test-Path $nodeDir) { $prepend += $nodeDir }
if (Test-Path $flutterBin) { $prepend += $flutterBin }
if ($prepend.Count -gt 0) {
    $env:Path = (($prepend -join ';') + ';' + $env:Path)
}
