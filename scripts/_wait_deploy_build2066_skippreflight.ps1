$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'scripts\\deploy_completo\.ps1' -and $_.CommandLine -match 'deploy_completo_build2066_skippreflight\.log' }
if ($procs) {
  $ids = $procs | Select-Object -ExpandProperty ProcessId
  Wait-Process -Id $ids
}

Write-Output 'DONE_WAIT'
Write-Output '---RUNNING_CHECK---'
powershell -NoProfile -ExecutionPolicy Bypass -File "c:\gestao_yahweh_premium_final\scripts\_check_running_deploy_process.ps1"

Write-Output '---PUBSPEC_VERSION---'
Select-String -Path "c:\gestao_yahweh_premium_final\flutter_app\pubspec.yaml" -Pattern '^version:' | ForEach-Object { $_.Line }

Write-Output '---LATEST_AAB_D_TEMP---'
Get-ChildItem "D:\Temporarios" -Filter "GestaoYahweh_*_play.aab" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 FullName,Length,LastWriteTime | Format-List

Write-Output '---LATEST_IOS_ZIP_D_TEMP---'
Get-ChildItem "D:\Temporarios" -Filter "GestaoYahweh_ios_sources_*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 FullName,Length,LastWriteTime | Format-List

Write-Output '---BRANCH---'
Set-Location "c:\gestao_yahweh_premium_final"
git rev-parse --abbrev-ref HEAD

Write-Output '---LAST_COMMIT---'
git log -1 --pretty=format:"%H%n%ci%n%s"
