# Gera capturas App Store — iPad 13" (Gestão YAHWEH)
# Dimensões aceites: 2064x2752, 2752x2064, 2048x2732, 2732x2048
param(
    [string] $SourceDir = "C:\gestao_yahweh_premium_final\IMAGENS PARA IPHONE APROVAR",
    [string] $OutDir = "D:\Temporarios\AppStore_iPad_13_GestaoYahweh"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function Resize-ToAppStore {
    param(
        [System.Drawing.Image] $Source,
        [int] $TargetW,
        [int] $TargetH
    )
    $dest = New-Object System.Drawing.Bitmap $TargetW, $TargetH
    $g = [System.Drawing.Graphics]::FromImage($dest)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Black)

    $scale = [Math]::Max($TargetW / $Source.Width, $TargetH / $Source.Height)
    $nw = [int][Math]::Round($Source.Width * $scale)
    $nh = [int][Math]::Round($Source.Height * $scale)
    $x = ($TargetW - $nw) / 2
    $y = ($TargetH - $nh) / 2
    $g.DrawImage($Source, $x, $y, $nw, $nh)
    $g.Dispose()
    return $dest
}

if (-not (Test-Path $SourceDir)) {
    Write-Host "Pasta origem nao encontrada: $SourceDir" -ForegroundColor Red
    exit 1
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$specs = @(
    @{ W = 2064; H = 2752; Sub = "2064x2752" },
    @{ W = 2048; H = 2732; Sub = "2048x2732" }
)

foreach ($spec in $specs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $OutDir $spec.Sub) | Out-Null
}

$files = Get-ChildItem $SourceDir -File | Where-Object {
    $_.Extension -match '^\.(jpe?g|png)$' -and $_.Name -notmatch 'desktop\.ini'
} | Sort-Object Name

if ($files.Count -eq 0) {
    Write-Host "Nenhuma imagem em $SourceDir" -ForegroundColor Red
    exit 1
}

$i = 0
foreach ($f in $files) {
    $i++
    $num = '{0:D2}' -f $i
    $base = "GestaoYahweh_iPad13_$num"
    $src = [System.Drawing.Image]::FromFile($f.FullName)
    try {
        foreach ($spec in $specs) {
            $bmp = Resize-ToAppStore -Source $src -TargetW $spec.W -TargetH $spec.H
            $outPath = Join-Path (Join-Path $OutDir $spec.Sub) "$base.png"
            $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            Write-Host "OK $($spec.Sub)\$base.png" -ForegroundColor Green
        }
    }
    finally {
        $src.Dispose()
    }
}

Write-Host ""
Write-Host "Concluido: $($files.Count) capturas x 2 tamanhos em:" -ForegroundColor Cyan
Write-Host "  $OutDir" -ForegroundColor Cyan
Write-Host "App Store Connect (iPad 13 pol.): use 2064x2752 (recomendado) ou 2048x2732." -ForegroundColor DarkGray
