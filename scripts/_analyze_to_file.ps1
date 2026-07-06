$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$flutter = Join-Path $repo 'flutter_app'
$out = Join-Path $repo 'artifacts\analyze_after_fix.txt'
Push-Location $flutter
try {
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $an = dart analyze lib --no-fatal-warnings 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $prev
  $an | Set-Content -Path $out -Encoding utf8
  Add-Content -Path $out -Value "ANALYZE_EXIT=$code"
} finally {
  Pop-Location
}
Write-Output "OK_ANALYZE:$out"
exit $code
