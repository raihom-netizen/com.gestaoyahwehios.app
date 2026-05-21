# Ativa symlinks para Flutter (plugins) no Windows 10/11.
# Requer Modo de programador OU terminal como Administrador.
#
# Uso: .\scripts\enable_windows_developer_mode.ps1
# Depois: reinicie o terminal e .\scripts\build_android_play_store_aab.ps1

$ErrorActionPreference = 'Continue'
Write-Host '=== Modo de programador (symlinks Flutter) ===' -ForegroundColor Cyan

try {
    reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\DeveloperSettings' /v AllowDevelopmentWithoutDevLicense /t REG_DWORD /d 1 /f | Out-Null
    reg add 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' /v DeveloperMode /t REG_DWORD /d 1 /f | Out-Null
    Write-Host 'Registo HKCU actualizado (pode exigir reinicio ou toggle na UI).' -ForegroundColor Green
} catch {
    Write-Host "AVISO: registo HKCU: $_" -ForegroundColor Yellow
}

Write-Host 'A abrir Definicoes > Modo de programador...' -ForegroundColor Cyan
Start-Process 'ms-settings:developers'

Write-Host ''
Write-Host '1. Ligue "Modo de programador" na janela que abriu.' -ForegroundColor Yellow
Write-Host '2. Feche e reabra o terminal (ou reinicie o PC se symlink ainda falhar).' -ForegroundColor Yellow
Write-Host '3. Execute: .\scripts\build_android_play_store_aab.ps1' -ForegroundColor Yellow
