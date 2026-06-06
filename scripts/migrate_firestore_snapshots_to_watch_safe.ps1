# Migra .snapshots() directo para .watchSafe() em flutter_app/lib
$ErrorActionPreference = "Stop"
$root = Join-Path (Split-Path -Parent $PSScriptRoot) "flutter_app\lib"
$importLine = "import 'package:gestao_yahweh/services/firestore_stream_utils.dart';"
$skip = @("firestore_stream_utils.dart")
$changed = 0

Get-ChildItem -Path $root -Recurse -Filter "*.dart" | ForEach-Object {
  $path = $_.FullName
  $rel = $_.FullName
  foreach ($s in $skip) {
    if ($rel -like "*$s*") { return }
  }

  $content = [System.IO.File]::ReadAllText($path)
  if (-not $content.Contains(".snapshots()")) { return }

  $original = $content
  $content = $content.Replace(".snapshots()", ".watchSafe()")

  do {
    $prev = $content
    $content = [regex]::Replace(
      $content,
      'FirestoreStreamUtils\.resilientQuery\(\s*([\s\S]*?)\.watchSafe\(\)\s*\)',
      '$1.watchSafe()'
    )
    $content = [regex]::Replace(
      $content,
      'FirestoreStreamUtils\.resilientDocument\(\s*([\s\S]*?)\.watchSafe\(\)\s*\)',
      '$1.watchSafe()'
    )
  } while ($prev -ne $content)

  if ($content.Contains(".watchSafe(") -and -not $content.Contains($importLine)) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.AddRange([string[]]($content -split "`n"))
    $insertAt = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i].StartsWith("import ")) {
        $insertAt = $i + 1
        # Continuação de import multi-linha (show/hide/as)
        while ($insertAt -lt $lines.Count -and -not $lines[$insertAt - 1].TrimEnd().EndsWith(";")) {
          $insertAt++
        }
      }
    }
    $lines.Insert($insertAt, $importLine)
    $content = ($lines -join "`n")
  }

  if ($content -ne $original) {
    [System.IO.File]::WriteAllText($path, $content)
    $script:changed++
    Write-Host "OK $($_.FullName.Substring($root.Length))"
  }
}

Write-Host "`nMigrated $changed files."
