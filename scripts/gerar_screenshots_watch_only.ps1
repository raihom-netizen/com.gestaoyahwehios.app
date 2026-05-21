param(
    [string]$SourceDir = "C:\gestao_yahweh_premium_final\IMAGENS PARA IPHONE APROVAR",
    [string]$OutDir = "D:\Temporarios\APP_STORE_SCREENSHOTS"
)

& "$PSScriptRoot\gerar_screenshots_app_store.ps1" -OnlyWatch -SkipOriginais -SourceDir $SourceDir -OutDir $OutDir

# Pasta unica para arrastar no separador Apple Watch (10 ficheiros, 416x496 exactos)
$src = Join-Path $OutDir "AppleWatch_FORMATO_ASC\Series11_416x496"
$upload = Join-Path $OutDir "AppleWatch_PARA_ARRASTAR_NO_ASC_416x496"
if (Test-Path $src) {
    New-Item -ItemType Directory -Path $upload -Force | Out-Null
    Get-ChildItem $src -Filter *.jpg | Sort-Object Name | Select-Object -First 10 | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $upload $_.Name) -Force
    }
    @"
APPLE WATCH — formato correcto App Store Connect
===============================================
Arraste os 10 JPG desta pasta para: App Store Connect → Apple Watch
Dimensao exacta: 416 x 496 px (Series 11 — aceite pelo ASC)

Outros tamanhos (se o validador pedir):
  AppleWatch_FORMATO_ASC\Ultra3_422x514
  AppleWatch_FORMATO_ASC\Ultra3_410x502
  AppleWatch_FORMATO_ASC\Series9_396x484
  AppleWatch_FORMATO_ASC\Series6_368x448
  AppleWatch_FORMATO_ASC\Series3_312x390

Maximo 10 capturas. Use os mesmos numeros 01-10 que no iPhone.
"@ | Set-Content (Join-Path $upload "LEIA-ME.txt") -Encoding UTF8
    Write-Host "Upload pronto: $upload"
}
