$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'scripts\\deploy_completo\.ps1' -and $_.CommandLine -match 'deploy_completo_build2066_skipweb\.log' }
if ($procs) {
  $ids = $procs | Select-Object -ExpandProperty ProcessId
  Wait-Process -Id $ids
}
Write-Output 'DONE_WAIT'
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\gestao_yahweh_premium_final\scripts\_check_running_deploy_process.ps1"
Select-String -Path "c:\gestao_yahweh_premium_final\flutter_app\pubspec.yaml" -Pattern '^version:' | ForEach-Object { $_.Line }
Get-ChildItem "D:\Temporarios" -Filter "GestaoYahweh_*_play.aab" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 FullName,Length,LastWriteTime | Format-List
