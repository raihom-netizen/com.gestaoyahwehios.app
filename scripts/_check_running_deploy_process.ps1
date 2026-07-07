$procs = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -and (
    $_.CommandLine -like '*scripts\deploy_completo.ps1*' -or
    $_.CommandLine -like '*scripts\deploy_release_completo_regras_funcoes_web_aab_ios_zip.ps1*'
  )
}
if (-not $procs) {
  Write-Output 'NO_DEPLOY_PROCESS'
  exit 0
}
$procs | Select-Object ProcessId,Name,CreationDate,CommandLine | Format-List