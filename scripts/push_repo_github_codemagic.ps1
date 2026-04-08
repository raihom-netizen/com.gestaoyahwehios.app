# Primeiro envio para GitHub (Codemagic precisa de codemagic.yaml na raiz do branch main).
# Uso (PowerShell, na raiz do repo local):
#   .\scripts\push_repo_github_codemagic.ps1
#   .\scripts\push_repo_github_codemagic.ps1 -RemoteUrl "https://github.com/SEU_USER/SEU_REPO.git"
#
# Depois: GitHub pede login (token PAT ou Git Credential Manager).

param(
    [string] $RemoteUrl = "https://github.com/raihom-netizen/com.gestaoyahwehios.app.git"
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path "codemagic.yaml")) {
    Write-Error "codemagic.yaml nao encontrado na raiz."
}

if (-not (Test-Path "flutter_app\pubspec.yaml")) {
    Write-Error "flutter_app nao encontrado."
}

if (-not (Test-Path ".git")) {
    git init
    git branch -M main
}

git add .gitignore codemagic.yaml flutter_app
git status

Write-Host ""
Write-Host "Se estiver correto, execute:" -ForegroundColor Cyan
Write-Host "  git commit -m `"Add Flutter app + codemagic.yaml for CI`""
Write-Host "  git remote add origin $RemoteUrl"
Write-Host "  (se origin ja existir: git remote set-url origin $RemoteUrl)"
Write-Host "  git push -u origin main"
Write-Host ""
Write-Host "Ou confirme para o assistente executar commit + remote (push manual se falhar auth)." -ForegroundColor Yellow
