# Repara Wi-Fi no Windows — execute como Administrador (clique direito > Executar como administrador)
# Uso: .\scripts\wifi_reparar_windows.ps1

$ErrorActionPreference = "Continue"
Write-Host "=== Reparo Wi-Fi Gestao YAHWEH / PC ===" -ForegroundColor Cyan

# 1) Servico WLAN
Write-Host "`n[1] Reiniciar servico WlanSvc..." -ForegroundColor Yellow
Stop-Service WlanSvc -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service WlanSvc
Start-Sleep -Seconds 2

# 2) Desabilitar adaptador USB Realtek conflitante (se existir)
Write-Host "`n[2] Desabilitar dongle USB Wi-Fi extra (se houver)..." -ForegroundColor Yellow
Get-PnpDevice -Class Net -ErrorAction SilentlyContinue |
    Where-Object { $_.FriendlyName -match 'RTL8188|USB.*Wireless|802.11n USB' } |
    ForEach-Object {
        Write-Host "   Desabilitando: $($_.FriendlyName)" -ForegroundColor DarkYellow
        Disable-PnpDevice -InstanceId $_.InstanceId -Confirm:$false -ErrorAction SilentlyContinue
    }

# 3) Reiniciar adaptador Intel Wi-Fi
Write-Host "`n[3] Reiniciar adaptador Wi-Fi (Intel)..." -ForegroundColor Yellow
netsh interface set interface "Wi-Fi" disable
Start-Sleep -Seconds 3
netsh interface set interface "Wi-Fi" enable
Start-Sleep -Seconds 5

# 4) Limpar cache de rede sem apagar perfis (scan fresco)
Write-Host "`n[4] Atualizar lista de redes..." -ForegroundColor Yellow
netsh wlan disconnect | Out-Null
Start-Sleep -Seconds 2

# 5) Redes visiveis
Write-Host "`n[5] Redes detectadas agora:" -ForegroundColor Green
netsh wlan show networks mode=bssid

Write-Host "`n=== Se o roteador NAO aparecer ===" -ForegroundColor Cyan
Write-Host "  - Confirme que o roteador esta ligado e perto do PC."
Write-Host "  - No roteador: ative rede 2,4 GHz (obrigatorio para Intel AC 9462)."
Write-Host "  - Evite so 6 GHz / Wi-Fi 6E — este PC nao ve banda 6 GHz."
Write-Host "  - SSID visivel (nao oculto); WPA2 ou WPA2+WPA3 misto."
Write-Host "  - Reinicie o roteador (desligar 30 s e ligar)."
Write-Host "`nSe ainda falhar: Gerenciador de Dispositivos > Wi-Fi Intel > Propriedades > Driver > Reverter ou Atualizar."
Write-Host "Relatorio Wi-Fi: netsh wlan show wlanreport  (como Admin, abre pasta com log HTML)."
