$p = 'c:\gestao_yahweh_premium_final\flutter_app\lib\ui\pages\church_avisos_page.dart'
$i = 0
Get-Content $p | ForEach-Object {
  $i++
  if ($i -ge 940 -and $i -le 970) {
    '{0,4}: {1}' -f $i, $_
  }
}
