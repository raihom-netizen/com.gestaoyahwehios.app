$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

git add -A
$msg = 'chore: deploy completo producao 2026-07-03'
$status = git diff --cached --name-only
if ($status) {
  git commit -m $msg
} else {
  Write-Host 'Sem mudanças staged para commit.'
}

git push -u origin main
