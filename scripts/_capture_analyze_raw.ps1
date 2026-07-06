$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $repo 'flutter_app'
$out = Join-Path $repo 'artifacts\analyze_raw.txt'
$exitOut = Join-Path $repo 'artifacts\analyze_raw_exit.txt'
Push-Location $flutter
try {
  dart analyze lib --no-fatal-warnings 2>&1 | Out-File -FilePath $out -Encoding utf8
  "exit=$LASTEXITCODE" | Out-File -FilePath $exitOut -Encoding utf8
} finally {
  Pop-Location
}
Write-Output "ok:$out"
