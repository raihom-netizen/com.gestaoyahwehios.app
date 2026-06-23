# Auditoria camada de dados - Web deve usar mesma API que Android/iOS
# Uso: .\scripts\auditoria_camada_dados.ps1 > AUDITORIA_CAMADA_DADOS_SAIDA.txt

$root = Split-Path -Parent $PSScriptRoot
$lib = Join-Path $root 'flutter_app\lib'

$patterns = @(
    @{ Name = 'FirebaseFirestore.instance'; Regex = 'FirebaseFirestore\.instance' },
    @{ Name = 'FirebaseStorage.instance'; Regex = 'FirebaseStorage\.instance' },
    @{ Name = 'TenantResolverService'; Regex = 'TenantResolverService' },
    @{ Name = 'resolveOperationalChurchDocId'; Regex = 'resolveOperationalChurchDocId' },
    @{ Name = 'church_aliases'; Regex = 'church_aliases' },
    @{ Name = 'collection(tenants)'; Regex = "collection\(\s*['\`"]tenants['\`"]" },
    @{ Name = 'canonicalTenant'; Regex = 'canonicalTenant' },
    @{ Name = 'getAllTenantIdsWithSameSlugOrAlias'; Regex = 'getAllTenantIdsWithSameSlugOrAlias' }
)

function Scan-Dir {
    param([string]$Label, [string]$Regex, [string]$SubPath, [string]$Glob)
    Write-Host ""
    Write-Host "=== $Label ($SubPath) ==="
    $total = 0
    $base = Join-Path $lib $SubPath
    if (-not (Test-Path $base)) { Write-Host "(ausente)"; return 0 }
    $files = Get-ChildItem -Path $base -Recurse -Filter $Glob -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $lineNum = 0
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $lineNum++
            if ($line -match $Regex) {
                $rel = $file.FullName.Substring($root.Length + 1) -replace '\\', '/'
                $sn = $line.Trim()
                if ($sn.Length -gt 100) { $sn = $sn.Substring(0, 100) + '...' }
                Write-Host "${rel}:${lineNum}:${sn}"
                $total++
            }
        }
    }
    Write-Host "Total $Label : $total"
    return $total
}

Write-Host "AUDITORIA CAMADA DADOS - Gestao YAHWEH"
Write-Host "Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Regra: painel igreja deve usar ChurchRepository + ChurchStorageService"
Write-Host ""

[int]$grand = 0
foreach ($p in $patterns) {
    $grand += [int](Scan-Dir -Label $p.Name -Regex $p.Regex -SubPath 'ui' -Glob '*.dart')
    $grand += [int](Scan-Dir -Label "$($p.Name) [services]" -Regex $p.Regex -SubPath 'services' -Glob '*.dart')
}

Write-Host ""
Write-Host "TOTAL UI+SERVICES (padroes legado/acesso direto): $grand"
Write-Host ""
Write-Host "API unica existente (sem Web*Repository duplicado):"
Write-Host "  ChurchRepository, ChurchStorageService, ChurchContextService"
Write-Host "  ChurchTenantResilientReads (delega ChurchRepository.churchDoc)"
