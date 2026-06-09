# Substitui ChurchOperationalPaths.resolveCached por ChurchRepository.churchId nas telas.
$root = Join-Path $PSScriptRoot '..\flutter_app\lib\ui\pages'
$files = Get-ChildItem -Path $root -Recurse -Filter '*.dart'
$changed = 0

foreach ($file in $files) {
    $content = [IO.File]::ReadAllText($file.FullName)
    if ($content -notmatch 'ChurchOperationalPaths') { continue }

    $original = $content
    # await resolveCached(...) -> ChurchRepository.churchId(...)
    $content = $content -replace 'await\s+ChurchOperationalPaths\.resolveCached\s*\(', 'ChurchRepository.churchId('
    # .then((op) após resolveCached
    $content = $content -replace 'ChurchOperationalPaths\.resolveCached\s*\(([^)]+)\)\.then\s*\(\s*\(\s*(\w+)\s*\)', 'Future<void>.microtask(() { final $2 = ChurchRepository.churchId($1);'
    # resolveCached sem await (Future return)
    $content = $content -replace 'ChurchOperationalPaths\.resolveCached\s*\(', 'Future.value(ChurchRepository.churchId('

    if ($content -eq $original) { continue }

    if ($content -match 'ChurchRepository\.' -and $content -notmatch "import 'package:gestao_yahweh/core/repositories/church_repository.dart'") {
        $content = $content -replace "(import 'package:flutter/material.dart';)", "`$1`nimport 'package:gestao_yahweh/core/repositories/church_repository.dart';"
    }

    if ($content -notmatch 'ChurchOperationalPaths' -and $content -match "import 'package:gestao_yahweh/services/church_operational_paths.dart';") {
        $content = $content -replace "\r?\nimport 'package:gestao_yahweh/services/church_operational_paths.dart';", ''
    }

    [IO.File]::WriteAllText($file.FullName, $content)
    $changed++
    Write-Host "OK $($file.Name)"
}

Write-Host "Arquivos alterados: $changed"
