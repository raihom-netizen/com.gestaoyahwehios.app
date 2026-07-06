$ErrorActionPreference = 'Stop'
$path = 'D:\Temporarios'
$out = 'C:\gestao_yahweh_premium_final\artifacts\d_temporarios_dirs_inventory.txt'
$items = Get-ChildItem $path -Force
$lines = foreach ($i in $items) {
  if ($i.PSIsContainer) {
    $size = (Get-ChildItem $i.FullName -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
    if (-not $size) { $size = 0 }
    "$($i.FullName)`tDIR`t$size`t$($i.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
  } else {
    "$($i.FullName)`tFILE`t$($i.Length)`t$($i.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
  }
}
$lines | Sort-Object { [int64]($_ -split "`t")[2] } -Descending | Set-Content -Path $out -Encoding UTF8
Write-Output "ok:$out"
