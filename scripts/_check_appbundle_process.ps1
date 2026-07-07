$p = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'flutter\.bat"\s+build\s+appbundle' }
if ($p) { Write-Output 'APPBUNDLE_RUNNING'; $p | Select-Object ProcessId,CreationDate,Name | Format-List } else { Write-Output 'APPBUNDLE_NOT_RUNNING' }
