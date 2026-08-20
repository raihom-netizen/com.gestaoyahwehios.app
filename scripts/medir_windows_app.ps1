# Mede o app Windows: responde? quantas threads? sobrevive?
#
# Existe porque "compilou" nao e prova de nada aqui: o congelamento do desktop
# e um bloqueio na camada nativa (Firestore C++), e ja foi dado como corrigido
# uma vez so porque o build passou. Nao publicar instalador sem esta medicao.
#
# Uso: .\scripts\medir_windows_app.ps1 [-Exe <caminho>] [-Ciclos 12] [-Intervalo 5]
param(
    [string] $Exe = "C:\gestao_yahweh_premium_final\flutter_app\build\windows\x64\runner\Release\gestao_yahweh.exe",
    [int] $Ciclos = 12,
    [int] $Intervalo = 5
)

$ErrorActionPreference = "Continue"
if (-not (Test-Path $Exe)) { Write-Error "Executavel nao encontrado: $Exe"; exit 1 }

$inicio = Get-Date
$p = Start-Process -FilePath $Exe -PassThru
Start-Sleep -Seconds 2
$cpuAnterior = 0.0
$respondeuAlgumaVez = $false
$morreuAos = -1

"{0,5} | {1,-8} | {2,-9} | {3,7} | {4,8}" -f "s", "responde", "CPU/ciclo", "MB", "threads"
"------+----------+-----------+---------+---------"

foreach ($i in 1..$Ciclos) {
    Start-Sleep -Seconds $Intervalo
    if ($p.HasExited) { $morreuAos = $i * $Intervalo; break }
    try { $p.Refresh() } catch { $morreuAos = $i * $Intervalo; break }
    if ($p.HasExited) { $morreuAos = $i * $Intervalo; break }

    $cpu = 0.0
    try { $cpu = $p.TotalProcessorTime.TotalSeconds } catch {}
    $delta = [math]::Round($cpu - $cpuAnterior, 2)
    $cpuAnterior = $cpu

    $resp = "NAO"
    try { if ($p.Responding) { $resp = "SIM"; $respondeuAlgumaVez = $true } } catch {}

    "{0,5} | {1,-8} | {2,9:N2} | {3,7:N0} | {4,8}" -f ($i * $Intervalo), $resp, $delta,
        ($p.WorkingSet64 / 1MB), $p.Threads.Count
}

$duracao = [int]((Get-Date) - $inicio).TotalSeconds
""
if ($morreuAos -ge 0) {
    "RESULTADO: o processo MORREU aos ~$morreuAos s (exit code $($p.ExitCode))."
} else {
    try { $p.Kill() } catch {}
    "RESULTADO: sobreviveu $duracao s (encerrado pela medicao)."
}
"Respondeu em algum momento: $(if ($respondeuAlgumaVez) { 'SIM' } else { 'NAO' })"

# O crash nativo nao aparece no stdout: fica no Visualizador de Eventos, com o
# offset. Offset igual entre execucoes = defeito deterministico.
""
"=== Application Error nos ultimos 10 min ==="
try {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Error';
        StartTime = (Get-Date).AddMinutes(-10) } -ErrorAction Stop |
        Select-Object -First 3 |
        ForEach-Object { ($_.Message -split "`n" | Select-Object -First 6) -join " | " }
} catch { "(nenhum evento)" }
