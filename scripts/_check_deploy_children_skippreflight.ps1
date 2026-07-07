$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'scripts\\deploy_completo\.ps1' -and $_.CommandLine -match 'deploy_completo_build2066_skippreflight\.log' }
if (-not $procs) { Write-Output 'NO_DEPLOY_PROCESS'; exit 0 }
$ids = $procs | Select-Object -ExpandProperty ProcessId
Write-Output ('DEPLOY_PIDS: ' + ($ids -join ','))
$children = Get-CimInstance Win32_Process | Where-Object { $ids -contains $_.ParentProcessId }
if (-not $children) { Write-Output 'NO_CHILDREN'; exit 0 }
$children | Select-Object ProcessId,ParentProcessId,Name,CreationDate,CommandLine | Format-List
