# Move arquivos temporarios para D:\TEMPORARIOS para nao encher o C:
# Pode apagar a pasta D:\TEMPORARIOS quando quiser.
# Uso: .\scripts\LimparTempParaD.ps1
# Ou:  .\scripts\LimparTempParaD.ps1 -IncluirBuildFlutter:$false  (nao move pasta build do Flutter)

param(
    [switch]$IncluirBuildFlutter = $true
)

$ErrorActionPreference = "Continue"
$destRaiz = "D:\TEMPORARIOS"
$dataHora = Get-Date -Format "yyyy-MM-dd_HH-mm"
$destPasta = Join-Path $destRaiz "Limpeza_$dataHora"

if (-not (Test-Path $destRaiz)) {
    New-Item -ItemType Directory -Path $destRaiz -Force | Out-Null
    Write-Host "Criada pasta: $destRaiz"
}
New-Item -ItemType Directory -Path $destPasta -Force | Out-Null
Write-Host "Destino desta limpeza: $destPasta"
Write-Host ""

$totalMovidos = 0
$totalErros = 0

function Mover-Conteudo {
    param([string]$Origem, [string]$NomeDestino)
    if (-not (Test-Path $Origem)) {
        Write-Host "  [Pulado] Nao existe: $Origem"
        return 0
    }
    $dest = Join-Path $destPasta $NomeDestino
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $itens = Get-ChildItem -Path $Origem -ErrorAction SilentlyContinue
    if (-not $itens) {
        Write-Host "  [Vazio] $Origem"
        return 0
    }
    $n = 0
    foreach ($item in $itens) {
        try {
            $alvo = Join-Path $dest $item.Name
            if (Test-Path $alvo) { Remove-Item $alvo -Recurse -Force -ErrorAction SilentlyContinue }
            Move-Item -Path $item.FullName -Destination $alvo -Force -ErrorAction Stop
            $n++
        } catch {
            $script:totalErros++
        }
    }
    if ($n -gt 0) {
        Write-Host "  [OK] $Origem -> $n itens movidos"
        $script:totalMovidos += $n
    }
    return $n
}

# 1) Temp do Windows (usuario atual)
$tempWin = [System.IO.Path]::GetTempPath()
if ($tempWin -and (Test-Path $tempWin)) {
    Write-Host "Movendo Temp Windows: $tempWin"
    Mover-Conteudo -Origem $tempWin -NomeDestino "Temp_Windows" | Out-Null
}
Write-Host ""

# 2) TEMP / TMP do ambiente
foreach ($var in @("TEMP","TMP")) {
    $p = [Environment]::GetEnvironmentVariable($var, "User")
    if (-not $p) { $p = [Environment]::GetEnvironmentVariable($var, "Process") }
    if ($p -and (Test-Path $p) -and ($p -notlike "*TEMPORARIOS*")) {
        Write-Host "Movendo $var : $p"
        Mover-Conteudo -Origem $p -NomeDestino "Temp_$var" | Out-Null
    }
}
Write-Host ""

# 3) Flutter build e .dart_tool (dentro do projeto) - opcional
$root = (Get-Item $PSScriptRoot).Parent.Parent.FullName
$flutterApp = Join-Path $root "flutter_app"
if ($IncluirBuildFlutter -and (Test-Path $flutterApp)) {
    $buildPath = Join-Path $flutterApp "build"
    if (Test-Path $buildPath) {
        Write-Host "Movendo Flutter build: $buildPath"
        Mover-Conteudo -Origem $buildPath -NomeDestino "Flutter_build" | Out-Null
    }
    $dartToolBuild = Join-Path $flutterApp ".dart_tool\flutter_build"
    if (Test-Path $dartToolBuild) {
        Write-Host "Movendo .dart_tool/flutter_build"
        Mover-Conteudo -Origem $dartToolBuild -NomeDestino "dart_tool_flutter_build" | Out-Null
    }
    Write-Host ""
}

# 4) Cache Pub (temp) - pasta pub temp dentro do Pub cache
$pubCache = Join-Path $env:LOCALAPPDATA "Pub\Cache"
$pubTemp = Join-Path $pubCache "tmp"
if (Test-Path $pubTemp) {
    Write-Host "Movendo Pub Cache tmp: $pubTemp"
    Mover-Conteudo -Origem $pubTemp -NomeDestino "Pub_cache_tmp" | Out-Null
}
Write-Host ""

Write-Host "Concluido. Itens movidos para: $destPasta"
Write-Host "Voce pode apagar a pasta D:\TEMPORARIOS quando quiser para liberar espaco."
if ($totalErros -gt 0) {
    Write-Host "Alguns arquivos estavam em uso e nao foram movidos (normal)."
}
