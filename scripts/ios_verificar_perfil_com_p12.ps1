# Verifica localmente (antes do Codemagic) se gestaoyahwehiosapp.mobileprovision
# inclui o certificado Apple Distribution do gestaoyahwehiosapp.p12.
#
# Uso na raiz do repo:
#   .\scripts\ios_verificar_perfil_com_p12.ps1
#   .\scripts\ios_verificar_perfil_com_p12.ps1 -P12Password "sua_senha"
#
# Requer: Python 3 + openssl no PATH (Git for Windows inclui openssl).

param(
    [string] $IosDir = "",
    [string] $P12Password = ""
)

$ErrorActionPreference = "Stop"
# scripts\ -> raiz do repositório
$RepoRoot = Split-Path -Parent $PSScriptRoot

$py = Join-Path $RepoRoot "scripts\ios_verify_profile_p12.py"
if (-not (Test-Path $py)) {
    Write-Host "ERRO: nao encontrado $py" -ForegroundColor Red
    exit 1
}

$pythonCmd = $null
foreach ($name in @("python", "python3")) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c -and $c.Source) {
        $pythonCmd = $name
        break
    }
}
if (-not $pythonCmd) {
    Write-Host "ERRO: Python nao encontrado no PATH (instale Python 3 ou use 'Git Bash' com python)." -ForegroundColor Red
    exit 1
}

$iosArg = @()
if ($IosDir -and $IosDir.Trim().Length -gt 0) {
    $iosArg = @("--ios-dir", $IosDir.Trim())
}

$pwdArg = @()
if ($P12Password.Length -gt 0) {
    $pwdArg = @("--p12-password", $P12Password)
} elseif ($env:YW_IOS_P12_PASSWORD) {
    $pwdArg = @("--p12-password", $env:YW_IOS_P12_PASSWORD)
} else {
    $sec = Read-Host "Password do gestaoyahwehiosapp.p12 (Enter se vazio)" -AsSecureString
    if ($sec.Length -gt 0) {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
            $pwdArg = @("--p12-password", $plain)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) | Out-Null
        }
    }
}

& $pythonCmd $py @iosArg @pwdArg
exit $LASTEXITCODE
