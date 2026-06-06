# Remove utilizadores Firebase Auth somente anonimos (mantem Gmail, Apple, email/senha).
# Uso:
#   .\scripts\purge_anonymous_firebase_users.ps1              # simulacao
#   .\scripts\purge_anonymous_firebase_users.ps1 -Execute     # apaga de verdade

param(
  [switch]$Execute
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$functionsDir = Join-Path $root "functions"
Push-Location $functionsDir
try {
  if (-not (Test-Path "node_modules")) {
    Write-Host "npm ci em functions..."
    npm ci
  }
  if ($Execute) {
    Write-Host "ATENCAO: vai apagar todos os utilizadores (anonimo) do Firebase Auth."
    node scripts/purge-anonymous-auth-users.js --execute
  } else {
    Write-Host "Simulacao - nada sera apagado. Use -Execute para apagar."
    node scripts/purge-anonymous-auth-users.js --dry-run
  }
} finally {
  Pop-Location
}
