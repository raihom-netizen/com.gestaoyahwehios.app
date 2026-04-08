# Re-encapsula MP4 com moov no início (fast start) — essencial para web / Firebase Storage.
# Uso (na raiz do repo): .\scripts\ffmpeg_faststart_public_videos.ps1
# Pré-requisito: ffmpeg no PATH (https://ffmpeg.org)
#
# Por defeito lê .\public\videos e grava ficheiros *_faststart.mp4 na mesma pasta.
# -Replace: substitui cada .mp4 in-place (usa ficheiro temporário).

param(
    [string] $InputDir = "",
    [string] $OutputDir = "",
    [switch] $Replace
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($InputDir)) {
    $InputDir = Join-Path $root "public\videos"
}
if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = $InputDir
}

if (-not (Test-Path -LiteralPath $InputDir)) {
    Write-Host "Criando pasta: $InputDir"
    New-Item -ItemType Directory -Path $InputDir -Force | Out-Null
}

$ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpeg) {
    Write-Error "ffmpeg não encontrado no PATH. Instale FFmpeg e tente de novo."
    exit 1
}

$mp4s = Get-ChildItem -LiteralPath $InputDir -Filter "*.mp4" -File
if ($mp4s.Count -eq 0) {
    Write-Host "Nenhum .mp4 em: $InputDir"
    exit 0
}

foreach ($f in $mp4s) {
    $in = $f.FullName
    if ($Replace) {
        $temp = [System.IO.Path]::GetTempFileName() + ".mp4"
        try {
            & ffmpeg -hide_banner -y -i $in -c copy -movflags +faststart $temp
            if ($LASTEXITCODE -ne 0) { throw "ffmpeg falhou (exit $LASTEXITCODE)" }
            Move-Item -LiteralPath $temp -Destination $in -Force
            Write-Host "OK (in-place): $($f.Name)"
        }
        finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        }
    }
    else {
        $outName = $f.BaseName + "_faststart.mp4"
        $out = Join-Path $OutputDir $outName
        & ffmpeg -hide_banner -y -i $in -c copy -movflags +faststart $out
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg falhou em $($f.Name) (exit $LASTEXITCODE)" }
        Write-Host "OK: $($f.Name) -> $outName"
    }
}

Write-Host "Concluído. Envie os MP4 para o Storage (ex.: public/videos/...) e atualize as URLs no CMS."
