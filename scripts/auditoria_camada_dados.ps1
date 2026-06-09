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
    Write-Output ""
    Write-Output "=== $Label ($SubPath) ==="
    $total = 0
    $base = Join-Path $lib $SubPath
    if (-not (Test-Path $base)) { Write-Output "(ausente)"; return 0 }
    $files = Get-ChildItem -Path $base -Recurse -Filter $Glob -File -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $lineNum = 0
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            $lineNum++
            if ($line -match $Regex) {
                $rel = $file.FullName.Substring($root.Length + 1) -replace '\\', '/'
                $sn = $line.Trim()
                if ($sn.Length -gt 100) { $sn = $sn.Substring(0, 100) + '...' }
                Write-Output "${rel}:${lineNum}:${sn}"
                $total++
            }
        }
    }
    Write-Output "Total $Label : $total"
    return $total
}

Write-Output "AUDITORIA CAMADA DADOS - Gestao YAHWEH"
Write-Output "Gerado: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Regra: painel igreja deve usar ChurchRepository + ChurchStorageService"
Write-Output ""

$grand = 0
foreach ($p in $patterns) {
    $grand += Scan-Dir -Label $p.Name -Regex $p.Regex -SubPath 'ui' -Glob '*.dart'
    $grand += Scan-Dir -Label "$($p.Name) [services]" -Regex $p.Regex -SubPath 'services' -Glob '*.dart'
}

Write-Output ""
Write-Output "TOTAL UI+SERVICES (padroes legado/acesso direto): $grand"
Write-Output ""
Write-Output "API unica existente (sem Web*Repository duplicado):"
Write-Output "  ChurchRepository, ChurchStorageService, ChurchContextService"
Write-Output "  ChurchTenantResilientReads (delega ChurchRepository.churchDoc)"
