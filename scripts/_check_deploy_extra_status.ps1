param(
  [string]$LogPath = 'D:\Temporarios\deploy_extra_confirmacao.log'
)

$ErrorActionPreference = 'Stop'
$log = $LogPath
if (-not (Test-Path $log)) {
  Write-Output 'log-nao-encontrado'
  exit 2
}
$c = Get-Content -Path $log -Encoding Unicode
$patterns = @('[1/6]','[2/6]','[3/6]','[4/6]','[5/6]','[6/6]','Copiado:','ZIP iOS:','Deploy complete!','release complete','Concluido em')
foreach ($p in $patterns) {
  $hit = $c | Select-String -SimpleMatch $p | Select-Object -First 1
  if ($hit) { Write-Output $hit.Line }
}
$tail = $c | Select-Object -Last 30
Write-Output '---TAIL---'
$tail
