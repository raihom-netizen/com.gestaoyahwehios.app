# Alinha domínios web + CORS Storage + checklist Firebase Auth (gestaoyahweh.com.br + web.app).
# Uso (raiz): .\scripts\ensure_firebase_domains_aligned.ps1
# Requer: firebase login; gcloud auth login (para CORS).

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot
. (Join-Path $RepoRoot 'scripts\ensure_gestao_yahweh_toolchain_path.ps1')

Write-Host ''
Write-Host '=== Gestao YAHWEH — dominios alinhados ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Hosting (mesmo build Flutter):' -ForegroundColor Yellow
Write-Host '  https://gestaoyahweh.com.br' -ForegroundColor White
Write-Host '  https://gestaoyahweh-21e23.web.app' -ForegroundColor White
Write-Host ''
Write-Host 'Firebase Console (OBRIGATORIO — uma vez ou apos novo dominio):' -ForegroundColor Yellow
Write-Host '  https://console.firebase.google.com/project/gestaoyahweh-21e23/authentication/settings' -ForegroundColor DarkGray
Write-Host '  Authorized domains — adicionar se faltar:' -ForegroundColor White
Write-Host '    gestaoyahweh.com.br' -ForegroundColor Green
Write-Host '    www.gestaoyahweh.com.br' -ForegroundColor Green
Write-Host '    gestaoyahweh-21e23.web.app' -ForegroundColor Green
Write-Host '    gestaoyahweh-21e23.firebaseapp.com' -ForegroundColor Green
Write-Host ''
Write-Host 'Google Cloud Console — OAuth (login Google web):' -ForegroundColor Yellow
Write-Host '  https://console.cloud.google.com/apis/credentials?project=gestaoyahweh-21e23' -ForegroundColor DarkGray
Write-Host '  Web client → Authorized JavaScript origins:' -ForegroundColor White
Write-Host '    https://gestaoyahweh.com.br' -ForegroundColor Green
Write-Host '    https://www.gestaoyahweh.com.br' -ForegroundColor Green
Write-Host '    https://gestaoyahweh-21e23.web.app' -ForegroundColor Green
Write-Host ''

if (Get-Command gsutil -ErrorAction SilentlyContinue) {
    Write-Host 'Aplicando CORS Storage (ambos dominios)...' -ForegroundColor Cyan
    & (Join-Path $RepoRoot 'scripts\apply_firebase_storage_cors.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'CORS falhou — ver gcloud auth login' -ForegroundColor Yellow
    }
} else {
    Write-Host 'gsutil ausente — CORS nao aplicado. Instale Google Cloud SDK ou corra apply_firebase_storage_cors.ps1 depois.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'Deploy web (mesmo artefacto nos dois URLs apos DNS/custom domain):' -ForegroundColor Yellow
Write-Host '  .\scripts\deploy_web_hosting.ps1' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Apos deploy: Ctrl+F5 em ambos os dominios.' -ForegroundColor Green
Write-Host ''
