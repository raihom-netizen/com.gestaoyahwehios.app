# Gera TODAS as capturas App Store Connect a partir de JPEGs (ex.: WhatsApp).
# Uso: .\scripts\gerar_screenshots_app_store.ps1
#      .\scripts\gerar_screenshots_app_store.ps1 -MaxUpload 10   # pasta SUGESTAO_top10

param(
    [string]$SourceDir = "C:\gestao_yahweh_premium_final\IMAGENS PARA IPHONE APROVAR",
    [string]$OutDir = "D:\Temporarios\APP_STORE_SCREENSHOTS",
    [int]$MaxUpload = 0,
    [switch]$OnlyWatch,
    [switch]$SkipOriginais
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

function Get-HighQualityGraphics {
    param([System.Drawing.Bitmap]$Bitmap)
    $g = [System.Drawing.Graphics]::FromImage($Bitmap)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    return $g
}

function New-GradientBrush {
    param([int]$W, [int]$H)
    $top = [System.Drawing.Color]::FromArgb(255, 12, 59, 138)
    $bottom = [System.Drawing.Color]::FromArgb(255, 6, 32, 88)
    return New-Object System.Drawing.Drawing2D.LinearGradientBrush (
        (New-Object System.Drawing.Rectangle 0, 0, $W, $H),
        $top,
        $bottom,
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
}

function Resize-Cover {
    param([System.Drawing.Image]$Src, [int]$TargetW, [int]$TargetH)
    $scale = [Math]::Max($TargetW / $Src.Width, $TargetH / $Src.Height)
    $sw = [int][Math]::Round($Src.Width * $scale)
    $sh = [int][Math]::Round($Src.Height * $scale)
    $bmp = New-Object System.Drawing.Bitmap $TargetW, $TargetH
    $g = Get-HighQualityGraphics $bmp
    $brush = New-GradientBrush $TargetW $TargetH
    $g.FillRectangle($brush, 0, 0, $TargetW, $TargetH)
    $brush.Dispose()
    $x = [int](($TargetW - $sw) / 2)
    $y = [int](($TargetH - $sh) / 2)
    $g.DrawImage($Src, $x, $y, $sw, $sh)
    $g.Dispose()
    return $bmp
}

function Resize-Contain {
    param([System.Drawing.Image]$Src, [int]$TargetW, [int]$TargetH)
    $scale = [Math]::Min($TargetW / $Src.Width, $TargetH / $Src.Height)
    $sw = [int][Math]::Round($Src.Width * $scale)
    $sh = [int][Math]::Round($Src.Height * $scale)
    $bmp = New-Object System.Drawing.Bitmap $TargetW, $TargetH
    $g = Get-HighQualityGraphics $bmp
    $brush = New-GradientBrush $TargetW $TargetH
    $g.FillRectangle($brush, 0, 0, $TargetW, $TargetH)
    $brush.Dispose()
    $x = [int](($TargetW - $sw) / 2)
    $y = [int](($TargetH - $sh) / 2)
    $g.DrawImage($Src, $x, $y, $sw, $sh)
    $g.Dispose()
    return $bmp
}

function Save-Jpeg {
    param([System.Drawing.Bitmap]$Bmp, [string]$Path, [long]$Quality = 95L)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if ($Bmp.Width -lt 1 -or $Bmp.Height -lt 1) { throw "Bitmap invalido" }
    $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $enc = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $enc.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, $Quality)
    $Bmp.Save($Path, $codec, $enc)
    $enc.Dispose()
}

function Save-Png {
    param([System.Drawing.Bitmap]$Bmp, [string]$Path)
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $Bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Process-One {
    param(
        [System.IO.FileInfo]$File,
        [int]$Index,
        [hashtable]$Target,
        [string]$FolderPath
    )
    $src = [System.Drawing.Image]::FromFile($File.FullName)
    try {
        if ($Target.Mode -eq "cover") {
            $out = Resize-Cover $src $Target.W $Target.H
        } else {
            $out = Resize-Contain $src $Target.W $Target.H
        }
        $safe = ($File.BaseName -replace '[^\w\-\.]', '_')
        $name = "{0:D2}_{1}" -f $Index, $safe
        $ext = if ($Target.Format -eq "png") { ".png" } else { ".jpg" }
        $dest = Join-Path $FolderPath ($name + $ext)
        if ($Target.Format -eq "png") { Save-Png $out $dest } else { Save-Jpeg $out $dest 95 }
        if ($out.Width -ne $Target.W -or $out.Height -ne $Target.H) {
            throw "Dimensao errada: esperado $($Target.W)x$($Target.H) obtido $($out.Width)x$($out.Height)"
        }
        $out.Dispose()
        return @{ Name = $name; Path = $dest; Source = $File.Name; W = $Target.W; H = $Target.H }
    } finally {
        $src.Dispose()
    }
}

if (-not (Test-Path $SourceDir)) {
    Write-Error "Pasta origem nao encontrada: $SourceDir"
}

$files = Get-ChildItem $SourceDir -File | Where-Object {
    $_.Extension -match '^\.(jpe?g|png)$' -and $_.Name -notmatch 'desktop\.ini'
} | Sort-Object Name

if ($files.Count -eq 0) {
    Write-Error "Nenhuma imagem em $SourceDir"
}

# Apple Watch: modo COVER = quadro exacto W x H (sem letterbox) — exigido pelo ASC.
$watchTargets = @(
    @{ Folder = "AppleWatch_FORMATO_ASC/Ultra3_422x514"; W = 422; H = 514; Mode = "cover"; Note = "Ultra 3 422x514" }
    @{ Folder = "AppleWatch_FORMATO_ASC/Ultra3_410x502"; W = 410; H = 502; Mode = "cover"; Note = "Ultra 3 410x502" }
    @{ Folder = "AppleWatch_FORMATO_ASC/Series11_416x496"; W = 416; H = 496; Mode = "cover"; Format = "jpg"; Note = "Series 11 416x496 ARRASTAR ASC" }
    @{ Folder = "AppleWatch_FORMATO_ASC/Series9_396x484"; W = 396; H = 484; Mode = "cover"; Note = "Series 9 396x484" }
    @{ Folder = "AppleWatch_FORMATO_ASC/Series6_368x448"; W = 368; H = 448; Mode = "cover"; Note = "Series 6 368x448" }
    @{ Folder = "AppleWatch_FORMATO_ASC/Series3_312x390"; W = 312; H = 390; Mode = "cover"; Note = "Series 3 312x390" }
)

$phonePadTargets = @(
    @{ Folder = "iPhone_6.5_1284x2778_TODAS"; W = 1284; H = 2778; Mode = "cover"; Note = "iPhone 6.5 - TODAS para escolher (ate 10 no ASC)" }
    @{ Folder = "iPhone_6.5_1242x2688_TODAS"; W = 1242; H = 2688; Mode = "cover"; Note = "iPhone 6.5 alt - TODAS" }
    @{ Folder = "iPad_13_2064x2752_TODAS"; W = 2064; H = 2752; Mode = "contain"; Note = "iPad 13 - TODAS" }
    @{ Folder = "iPad_13_2048x2732_TODAS"; W = 2048; H = 2732; Mode = "contain"; Note = "iPad 13 alt - TODAS" }
)

$targets = if ($OnlyWatch) { $watchTargets } else { $phonePadTargets + $watchTargets }

if ($MaxUpload -gt 0 -and -not $OnlyWatch) {
    $targets += @(
        @{ Folder = "SUGESTAO_top${MaxUpload}_iPhone_1284x2778"; W = 1284; H = 2778; Mode = "cover"; Note = "Sugestao $MaxUpload primeiras (ordem nome)"; Max = $MaxUpload }
        @{ Folder = "SUGESTAO_top${MaxUpload}_iPad_2064x2752"; W = 2064; H = 2752; Mode = "contain"; Note = "Sugestao iPad"; Max = $MaxUpload }
    )
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Copias das originais (739x1600) para comparar no Explorer
if (-not $SkipOriginais) {
$origDir = Join-Path $OutDir "00_ORIGINAIS_whatsapp"
New-Item -ItemType Directory -Path $origDir -Force | Out-Null
}
$indexLines = @(
    "GESTAO YAHWEH - INDICE DE CAPTURAS PARA ESCOLHER",
    "Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
    "Origem: $SourceDir",
    "Total: $($files.Count) imagens",
    "",
    "COMO ESCOLHER",
    "-------------",
    "1) Abra 00_ORIGINAIS_whatsapp e veja 01..15 (mesma ordem abaixo).",
    "2) Escolha ate 10 numeros para o iPhone (App Store Connect max 10).",
    "3) Arraste da pasta iPhone_6.5_1284x2778_TODAS os ficheiros com o MESMO numero.",
    "4) iPad: mesmos numeros em iPad_13_2064x2752_TODAS (opcional, max 10).",
    "5) Ou use SUGESTAO_top10_* se quiser as 10 primeiras por ordem de nome.",
    "",
    "NUM | ORIGINAL (whatsapp) | iPhone 1284x2778 | iPad 2064x2752",
    "----+----------------------------------------+------------------"
)

if (-not $SkipOriginais) {
$i = 0
foreach ($f in $files) {
    $i++
    $destOrig = Join-Path $origDir ("{0:D2}_{1}{2}" -f $i, ($f.BaseName -replace '[^\w\-\.]', '_'), $f.Extension)
    Copy-Item $f.FullName $destOrig -Force
    $indexLines += ("{0,3} | {1,-40} | 01_{2} ... (ver pasta TODAS)" -f $i, $f.Name, ($f.BaseName -replace '[^\w\-\.]', '_'))
}
}

$indexLines += ""
$indexLines += "PASTAS GERADAS:"
$results = @{}

foreach ($t in $targets) {
    $folder = Join-Path $OutDir $t.Folder
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $indexLines += "  - $($t.Folder) ($($t.W)x$($t.H)) - $($t.Note)"
    $idx = 0
    foreach ($f in $files) {
        $idx++
        if ($t.Max -and $idx -gt $t.Max) { break }
        $r = Process-One -File $f -Index $idx -Target $t -FolderPath $folder
        Write-Host "OK $($t.Folder)\$($r.Name).jpg"
    }
}

$indexLines += ""
$indexLines += "APP STORE CONNECT"
$indexLines += "  iPhone 6.5 pol.: iPhone_6.5_1284x2778_TODAS (max 10 ficheiros)"
$indexLines += "  iPad 13 pol.:    iPad_13_2064x2752_TODAS"
$indexLines += "  Apple Watch:    AppleWatch_Series11_416x496_TODAS (max 10; 3 primeiras no install sheet)"
$indexLines += "                  + pastas Ultra3 / Series9 / Series6 / Series3 se o ASC pedir"
$indexLines += ""
$indexLines += "REGRAS: sem precos de plano YAHWEH na app iOS; sem PIX dizimo dentro da app."

$indexPath = Join-Path $OutDir "INDICE_ESCOLHER.txt"
$indexLines | Out-File -FilePath $indexPath -Encoding UTF8

@"
GESTAO YAHWEH - Capturas App Store (TODAS para escolher)
Data: $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Total fontes: $($files.Count)

Abra INDICE_ESCOLHER.txt para a lista 01..15.

Pastas principais:
  00_ORIGINAIS_whatsapp     - copias pequenas (comparar)
  iPhone_6.5_1284x2778_TODAS - escolha ate 10 para upload iPhone
  iPad_13_2064x2752_TODAS    - escolha ate 10 para upload iPad
  SUGESTAO_top10_*           - se quiser as 10 primeiras ja prontas
  AppleWatch_*_TODAS         - capturas Apple Watch (todas as medidas do ASC)

"@ | Out-File -FilePath (Join-Path $OutDir "LEIA-ME.txt") -Encoding UTF8

Write-Host ""
Write-Host "Concluido: $OutDir"
Write-Host "$($files.Count) imagens x $($targets.Count) tamanhos"
Write-Host "INDICE: $indexPath"
