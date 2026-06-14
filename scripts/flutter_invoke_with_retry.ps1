# Executa comando Flutter com retry em falhas de rede/SSL/Gradle transitórias.
# Uso: . .\scripts\flutter_invoke_with_retry.ps1
#      Invoke-FlutterWithRetry -Label "AAB" -Arguments @("build","appbundle",...) -MaxAttempts 5

function Invoke-FlutterWithRetry {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Label,
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,
        [int] $MaxAttempts = 5,
        [int] $InitialWaitSec = 20
    )

    $transientPattern = 'SSLException|Tag mismatch|timed out|timeout|503|504|429|network|Gradle threw an error|Service Unavailable|Connection reset|ECONNRESET|SocketException|Unable to resolve host|HandshakeException'

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        if ($attempt -gt 1) {
            $wait = [Math]::Min($InitialWaitSec * $attempt, 180)
            Write-Host "[$Label] Retry $attempt/${MaxAttempts} apos falha transitoria - aguardar ${wait}s..." -ForegroundColor Yellow
            Start-Sleep -Seconds $wait
            $gradleDir = Join-Path (Get-Location) "android"
            if (Test-Path (Join-Path $gradleDir "gradlew.bat")) {
                Push-Location $gradleDir
                try { .\gradlew.bat --stop 2>&1 | Out-Null } catch {}
                finally { Pop-Location }
            }
        }

        Write-Host "[$Label] tentativa $attempt/${MaxAttempts}: flutter $($Arguments -join ' ')" -ForegroundColor Cyan
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = & flutter @Arguments 2>&1
        $exit = $LASTEXITCODE
        $ErrorActionPreference = $prevEap
        $text = ($output | Out-String)
        $output | ForEach-Object { Write-Host $_ }

        if ($exit -eq 0) {
            return 0
        }

        if ($text -notmatch $transientPattern -and $attempt -ge $MaxAttempts) {
            Write-Host "[$Label] falha nao transitoria (exit $exit)." -ForegroundColor Red
            return $exit
        }
        if ($text -notmatch $transientPattern) {
            Write-Host "[$Label] falha de compilacao/logica (exit $exit) - sem retry." -ForegroundColor Red
            return $exit
        }
        if ($text -match 'Tag mismatch|GradleWrapperMain|gradle\.wrapper') {
            $gradleDists = Join-Path $env:USERPROFILE ".gradle\wrapper\dists"
            if (Test-Path $gradleDists) {
                Write-Host "[$Label] cache Gradle wrapper possivelmente corrompido - limpando $gradleDists" -ForegroundColor DarkYellow
                Get-ChildItem -Path $gradleDists -Directory -ErrorAction SilentlyContinue |
                    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host "[$Label] falha transitoria detectada (exit $exit)." -ForegroundColor DarkYellow
    }

    return $exit
}
