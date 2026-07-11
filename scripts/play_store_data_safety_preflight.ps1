# Google Play - pre-voo Seguranca dos dados (evita rejeicao por formulario invalido).
#
# Uso (raiz do repo):
#   .\scripts\play_store_data_safety_preflight.ps1
#   .\scripts\play_store_data_safety_preflight.ps1 -Strict

param(
    [switch] $Strict,
    [switch] $Quiet
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Pubspec = Join-Path $RepoRoot "flutter_app\pubspec.yaml"
$Doc = Join-Path $RepoRoot "docs\PLAY_STORE_SEGURANCA_DADOS_EMAIL.md"

$ver = "?"
if (Test-Path $Pubspec) {
    $line = Select-String -Path $Pubspec -Pattern "^version:\s*" | Select-Object -First 1
    if ($line) { $ver = ($line.Line -replace '^version:\s*', '').Trim() }
}

$vc = if ($ver -match '\+(\d+)') { $Matches[1] } else { "?" }

function Write-Block([string]$msg, [string]$color = "Yellow") {
    if (-not $Quiet) { Write-Host $msg -ForegroundColor $color }
}

Write-Block ""
Write-Block "================================================================" "Cyan"
Write-Block " GOOGLE PLAY - Seguranca dos dados (OBRIGATORIO antes do AAB)" "Cyan"
Write-Block " App: Gestao Yahweh - Igrejas  |  com.gestaoyahweh.app" "Cyan"
Write-Block " Build alvo: $ver  (versionCode $vc)" "Cyan"
Write-Block "================================================================" "Cyan"
Write-Block ""
Write-Block "Rejeicao tipica: E-mail transmitido mas NAO declarado na ficha." "Red"
Write-Block "Correcao = Play Console. NAO remover e-mail do app." "Red"
Write-Block ""
Write-Block "Checklist ANTES de enviar o AAB:" "White"
Write-Block "  [1] Politica do app - Seguranca dos dados - Gerenciar" "Gray"
Write-Block "  [2] Coleta de dados: SIM" "Gray"
Write-Block "  [3] Tipo: Informacoes pessoais - Endereco de e-mail" "Yellow"
Write-Block "      Coletado Sim | Compartilhado Sim (Firebase/Google)" "Gray"
Write-Block "      Finalidade: Funcionalidade + Gerenciamento de contas" "Gray"
Write-Block "      Criptografado em transito: Sim" "Gray"
Write-Block "  [4] Revisar: Nome, Fotos, Telefone, CPF, FCM, Crashlytics" "Gray"
Write-Block "  [5] URL privacidade: gestaoyahweh.com.br/privacidade" "Gray"
Write-Block "  [6] Salvar ficha e Enviar para analise" "Gray"
Write-Block "  [7] Depois upload AAB versionCode $vc" "Gray"
Write-Block ""
Write-Block "Guia: $Doc" "DarkGray"
Write-Block ""

if ($Strict) {
    $ans = Read-Host "Confirmou itens 1-6 na Play Console? (s/N)"
    if ($ans -notmatch '^(s|sim|y|yes)$') {
        Write-Block "ABORTADO: atualize Seguranca dos dados antes do AAB." "Red"
        exit 1
    }
}

exit 0
