param(
  [string]$LogPath = 'D:\Temporarios\deploy_extra_confirmacao_ok.log'
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $LogPath)) { Write-Error "Log nao encontrado: $LogPath"; exit 2 }
$c = Get-Content -Path $LogPath -Encoding Unicode
$errs = $c | Where-Object { $_ -match '^\s*error\s*-\s' }
if (-not $errs -or $errs.Count -eq 0) {
  Write-Output 'sem-linhas-error'
  $c | Select-Object -Last 80
  exit 0
}
$errs | Set-Content -Path 'C:\gestao_yahweh_premium_final\artifacts\deploy_error_lines.txt' -Encoding UTF8
Write-Output 'ok:C:\gestao_yahweh_premium_final\artifacts\deploy_error_lines.txt'
$errs
