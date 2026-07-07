$targets = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -and (
    $_.CommandLine -like '*scripts\deploy_completo.ps1*' -or
    $_.CommandLine -like '*scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1*'
  )
}
if (-not $targets) {
  Write-Output 'NO_DEPLOY_PROCESS_FOUND'
  exit 0
}
foreach ($p in $targets) {
  try {
    Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop
    Write-Output ("STOPPED:" + $p.ProcessId)
  } catch {
    Write-Output ("FAILED:" + $p.ProcessId + ":" + $_.Exception.Message)
  }
}