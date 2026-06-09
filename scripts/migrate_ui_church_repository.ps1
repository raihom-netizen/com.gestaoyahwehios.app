# Migra ChurchOperationalPaths.churchDoc(...).collection('x') -> ChurchUiCollections
$uiRoot = Join-Path $PSScriptRoot "..\flutter_app\lib\ui"
$colMap = @{
    'membros' = 'membros'
    'members' = 'membros'
    'departamentos' = 'departamentos'
    'cargos' = 'cargos'
    'eventos' = 'eventos'
    'noticias' = 'eventos'
    'avisos' = 'avisos'
    'chats' = 'chats'
    'patrimonio' = 'patrimonio'
    'finance' = 'financeiro'
    'financeiro' = 'financeiro'
    'fornecedores' = 'fornecedores'
    'escalas' = 'escalas'
    'agenda' = 'agenda'
    'lideres' = 'lideres'
    'administrativo' = 'administrativo'
    'doacoes' = 'doacoes'
    'mercadopago' = 'mercadopago'
    'cartoes' = 'cartoes'
    'certificados_emitidos' = 'certificados'
    'certificados' = 'certificados'
    'pedidosOracao' = 'pedidosOracao'
    'cartas_historico' = 'transferencias'
    'visitantes' = 'visitantes'
    'config' = 'config'
}

$importLine = "import 'package:gestao_yahweh/core/data/church_ui_collections.dart';"
$changed = 0

Get-ChildItem -Path $uiRoot -Filter *.dart -Recurse | ForEach-Object {
    $path = $_.FullName
    $text = [IO.File]::ReadAllText($path)
    $orig = $text

    foreach ($col in $colMap.Keys) {
        $helper = $colMap[$col]
        $pattern = "ChurchOperationalPaths\.churchDoc\(([^)]+)\)\s*(?:\.\s*)?\.collection\(\s*['""]$col['""]\s*\)"
        $text = [regex]::Replace($text, $pattern, "ChurchUiCollections.$helper(`$1)")
    }

    $text = [regex]::Replace($text, 'ChurchOperationalPaths\.churchDoc\(([^)]+)\)', 'ChurchUiCollections.churchDoc($1)')

    if ($text -ne $orig) {
        if ($text -notmatch 'church_ui_collections\.dart') {
            if ($text -match "import 'package:gestao_yahweh/core/repositories/church_repository\.dart';") {
                $text = $text -replace "import 'package:gestao_yahweh/core/repositories/church_repository\.dart';", "import 'package:gestao_yahweh/core/repositories/church_repository.dart';`n$importLine"
            } else {
                $idx = $text.IndexOf("`n", $text.LastIndexOf("import "))
                if ($idx -gt 0) {
                    $text = $text.Insert($idx + 1, "$importLine`n")
                }
            }
        }
        [IO.File]::WriteAllText($path, $text)
        $changed++
        Write-Host $_.FullName
    }
}

Write-Host "Migrated $changed files"
