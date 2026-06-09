# Auditoria obrigatoria - acessos diretos Firestore/Storage e paths legados.
# Uso: .\scripts\auditoria_acessos_firestore_storage.ps1
# Saida: arquivo:linha:trecho (colar no chat do Cursor como prova)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$lib = Join-Path $root 'flutter_app\lib'
$functions = Join-Path $root 'functions\src'

$patterns = @(
    @{ Name = 'FirebaseFirestore.instance'; Regex = 'FirebaseFirestore\.instance' },
    @{ Name = 'FirebaseStorage.instance'; Regex = 'FirebaseStorage\.instance' },
    @{ Name = 'collection(tenants)'; Regex = "collection\(\s*['\`"]tenants['\`"]\s*\)" },
    @{ Name = 'collection(church_aliases)'; Regex = "collection\(\s*['\`"]church_aliases['\`"]\s*\)" },
    @{ Name = 'collection(church_roots)'; Regex = "collection\(\s*['\`"]church_roots['\`"]\s*\)" },
    @{ Name = 'resolveOperationalChurchDocId'; Regex = 'resolveOperationalChurchDocId' },
    @{ Name = 'TenantResolverService'; Regex = 'TenantResolverService' },
    @{ Name = 'canonicalTenant'; Regex = 'canonicalTenant' },
    @{ Name = 'operationalTenant'; Regex = 'operationalTenant' }
)

function Search-PatternInTree {
    param(
        [string]$Label,
        [string]$Regex,
        [string[]]$Paths
    )
    Write-Host ''
    Write-Host "=== $Label ===" -ForegroundColor Cyan
    $total = 0
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) { continue }
        $files = Get-ChildItem -Path $p -Recurse -Include *.dart,*.ts,*.js -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $lineNum = 0
            foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
                $lineNum++
                if ($line -match $Regex) {
                    $rel = $file.FullName.Substring($root.Length + 1) -replace '\\', '/'
                    $snippet = $line.Trim()
                    if ($snippet.Length -gt 120) { $snippet = $snippet.Substring(0, 120) + '...' }
                    Write-Host "${rel}:${lineNum}:${snippet}"
                    $total++
                }
            }
        }
    }
    Write-Host "Total $Label : $total" -ForegroundColor Yellow
    return $total
}

Write-Host 'AUDITORIA GESTAO YAHWEH - Firestore/Storage e legado' -ForegroundColor Green
Write-Host "Raiz: $root"
Write-Host "Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

$searchPaths = @($lib)
if (Test-Path $functions) { $searchPaths += $functions }

$grand = 0
foreach ($pat in $patterns) {
    $grand += Search-PatternInTree -Label $pat.Name -Regex $pat.Regex -Paths $searchPaths
}

Write-Host ''
Write-Host "=== collection(igrejas) [informativo - preferir ChurchRepository] ===" -ForegroundColor Cyan
$null = Search-PatternInTree -Label 'collection(igrejas)' -Regex "collection\(\s*['\`"]igrejas['\`"]\s*\)" -Paths $searchPaths

$color = if ($grand -eq 0) { 'Green' } else { 'Red' }
Write-Host ''
Write-Host "TOTAL OCORRENCIAS (padroes de risco): $grand" -ForegroundColor $color
Write-Host ''
Write-Host 'Criterio painel igreja: ChurchRepository + ChurchStorageService apenas.' -ForegroundColor DarkGray
Write-Host 'Encerrar tarefa somente com DEBUG CHURCH (3 plataformas) + este grep.' -ForegroundColor DarkGray
