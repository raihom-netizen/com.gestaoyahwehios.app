$ErrorActionPreference = 'Stop'
$path = 'D:\Temporarios'
$out = 'C:\gestao_yahweh_premium_final\artifacts\d_temporarios_inventory.txt'
Get-ChildItem $path -Force | Sort-Object Length -Descending | ForEach-Object {
  "$($_.FullName)`t$($_.Length)`t$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
} | Set-Content -Path $out -Encoding UTF8
Write-Output "ok:$out"
