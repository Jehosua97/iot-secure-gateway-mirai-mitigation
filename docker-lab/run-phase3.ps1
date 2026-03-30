param(
    [string]$ComposeFile = '',
    [string]$ResultsRoot = '',
    [switch]$TearDown
)

$ErrorActionPreference = 'Stop'

function Invoke-LoggedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string[]]$CommandArgs,

        [switch]$AllowFailure
    )

    Write-Host "[$Label] docker $($CommandArgs -join ' ')"
    $stdoutPath = Join-Path $RunDir "$Label.stdout.txt"
    $stderrPath = Join-Path $RunDir "$Label.stderr.txt"
    $argumentString = ($CommandArgs | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }) -join ' '

    $process = Start-Process -FilePath 'docker' `
        -ArgumentList $argumentString `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath

    $exitCode = $process.ExitCode
    $stdoutText = if (Test-Path $stdoutPath) { Get-Content -Path $stdoutPath -Raw } else { '' }
    $stderrText = if (Test-Path $stderrPath) { Get-Content -Path $stderrPath -Raw } else { '' }

    $combinedOutput = @()
    if ($stdoutText) {
        $combinedOutput += $stdoutText.TrimEnd("`r", "`n")
    }
    if ($stderrText) {
        $combinedOutput += $stderrText.TrimEnd("`r", "`n")
    }

    Set-Content -Path (Join-Path $RunDir "$Label.txt") -Value ($combinedOutput -join [Environment]::NewLine) -Encoding utf8
    Set-Content -Path (Join-Path $RunDir "$Label.exitcode.txt") -Value $exitCode -Encoding ascii

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Command failed for $Label with exit code $exitCode."
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is not installed or not available in PATH.'
}

if (-not $ComposeFile) {
    $ComposeFile = Join-Path $PSScriptRoot 'docker-compose.yml'
}

if (-not $ResultsRoot) {
    $ResultsRoot = Join-Path $PSScriptRoot 'results'
}

if (-not (Test-Path $ComposeFile)) {
    throw "Compose file not found: $ComposeFile"
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunDir = Join-Path $ResultsRoot $timestamp
New-Item -ItemType Directory -Force -Path $RunDir | Out-Null

$compose = @('compose', '-f', $ComposeFile)

Set-Content -Path (Join-Path $RunDir 'run-info.txt') -Value @(
    "timestamp=$timestamp"
    "compose_file=$ComposeFile"
    "results_dir=$RunDir"
) -Encoding utf8

Invoke-LoggedCommand -Label 'compose-up' -CommandArgs ($compose + @('up', '--build', '-d'))
Start-Sleep -Seconds 8

Invoke-LoggedCommand -Label 'compose-ps' -CommandArgs ($compose + @('ps'))
Invoke-LoggedCommand -Label 'docker-stats-baseline' -CommandArgs @('stats', '--no-stream', 'iot-fw', 'iot-device', 'attacker-outside')

Invoke-LoggedCommand -Label 'fw-ip-addr-baseline' -CommandArgs ($compose + @('exec', '-T', 'fw', 'ip', '-br', 'addr'))
Invoke-LoggedCommand -Label 'fw-routes-baseline' -CommandArgs ($compose + @('exec', '-T', 'fw', 'ip', 'route'))
Invoke-LoggedCommand -Label 'fw-ip-forward-baseline' -CommandArgs ($compose + @('exec', '-T', 'fw', 'cat', '/proc/sys/net/ipv4/ip_forward'))
Invoke-LoggedCommand -Label 'fw-ruleset-baseline' -CommandArgs ($compose + @('exec', '-T', 'fw', 'nft', 'list', 'ruleset'))
Invoke-LoggedCommand -Label 'iot-ip-addr-baseline' -CommandArgs ($compose + @('exec', '-T', 'iot', 'ip', '-br', 'addr'))
Invoke-LoggedCommand -Label 'iot-routes-baseline' -CommandArgs ($compose + @('exec', '-T', 'iot', 'ip', 'route'))
Invoke-LoggedCommand -Label 'iot-listeners-baseline' -CommandArgs ($compose + @('exec', '-T', 'iot', 'ss', '-lntp'))
Invoke-LoggedCommand -Label 'atk-ip-addr-baseline' -CommandArgs ($compose + @('exec', '-T', 'atk', 'ip', '-br', 'addr'))
Invoke-LoggedCommand -Label 'atk-routes-baseline' -CommandArgs ($compose + @('exec', '-T', 'atk', 'ip', 'route'))
Invoke-LoggedCommand -Label 'atk-listeners-baseline' -CommandArgs ($compose + @('exec', '-T', 'atk', 'ss', '-lntp'))

Invoke-LoggedCommand -Label 'fw-reset-counters' -CommandArgs ($compose + @('exec', '-T', 'fw', 'nft', 'reset', 'counters'))
Invoke-LoggedCommand -Label 'fw-forward-counters-before-tests' -CommandArgs ($compose + @('exec', '-T', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Invoke-LoggedCommand -Label 'atk-nmap-inbound' -CommandArgs ($compose + @('exec', '-T', 'atk', 'nmap', '-Pn', '-p', '22,23,2323', '10.20.0.10'))
Invoke-LoggedCommand -Label 'atk-nc-port22' -CommandArgs ($compose + @('exec', '-T', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '22')) -AllowFailure
Invoke-LoggedCommand -Label 'atk-nc-port23' -CommandArgs ($compose + @('exec', '-T', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '23')) -AllowFailure
Invoke-LoggedCommand -Label 'atk-nc-port2323' -CommandArgs ($compose + @('exec', '-T', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '2323')) -AllowFailure
Invoke-LoggedCommand -Label 'fw-forward-counters-after-inbound' -CommandArgs ($compose + @('exec', '-T', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Invoke-LoggedCommand -Label 'iot-blocked-22-to-wan' -CommandArgs ($compose + @('exec', '-T', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '22')) -AllowFailure
Invoke-LoggedCommand -Label 'iot-blocked-23-to-wan' -CommandArgs ($compose + @('exec', '-T', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '23')) -AllowFailure
Invoke-LoggedCommand -Label 'iot-blocked-2323-to-wan' -CommandArgs ($compose + @('exec', '-T', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '2323')) -AllowFailure
Invoke-LoggedCommand -Label 'iot-allowed-443-to-wan' -CommandArgs ($compose + @('exec', '-T', 'iot', 'sh', '-lc', 'for i in 1 2 3 4 5; do start=$(date +%s%3N); if nc -nvz -w 3 192.168.56.10 443 >/dev/null 2>&1; then status=success; else status=fail; fi; end=$(date +%s%3N); echo "run=$i status=$status connect_ms=$((end-start))"; done'))
Invoke-LoggedCommand -Label 'fw-forward-counters-after-outbound' -CommandArgs ($compose + @('exec', '-T', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Invoke-LoggedCommand -Label 'atk-scale-10' -CommandArgs ($compose + @('exec', '-T', 'atk', 'sh', '-lc', 'start=$(date +%s); for i in $(seq 1 10); do nc -vz -w 2 10.20.0.10 2323 >/dev/null 2>&1 & done; wait; end=$(date +%s); echo "parallel_connections=10"; echo "elapsed_seconds=$((end-start))"'))
Invoke-LoggedCommand -Label 'atk-scale-25' -CommandArgs ($compose + @('exec', '-T', 'atk', 'sh', '-lc', 'start=$(date +%s); for i in $(seq 1 25); do nc -vz -w 2 10.20.0.10 2323 >/dev/null 2>&1 & done; wait; end=$(date +%s); echo "parallel_connections=25"; echo "elapsed_seconds=$((end-start))"'))
Invoke-LoggedCommand -Label 'atk-scale-50' -CommandArgs ($compose + @('exec', '-T', 'atk', 'sh', '-lc', 'start=$(date +%s); for i in $(seq 1 50); do nc -vz -w 2 10.20.0.10 2323 >/dev/null 2>&1 & done; wait; end=$(date +%s); echo "parallel_connections=50"; echo "elapsed_seconds=$((end-start))"'))
Invoke-LoggedCommand -Label 'fw-forward-counters-after-scale' -CommandArgs ($compose + @('exec', '-T', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))
Invoke-LoggedCommand -Label 'docker-stats-after-scale' -CommandArgs @('stats', '--no-stream', 'iot-fw', 'iot-device', 'attacker-outside')
Invoke-LoggedCommand -Label 'iot-allowed-443-to-wan-after-scale' -CommandArgs ($compose + @('exec', '-T', 'iot', 'sh', '-lc', 'for i in 1 2 3 4 5; do start=$(date +%s%3N); if nc -nvz -w 3 192.168.56.10 443 >/dev/null 2>&1; then status=success; else status=fail; fi; end=$(date +%s%3N); echo "run=$i status=$status connect_ms=$((end-start))"; done'))

if ($TearDown) {
    Invoke-LoggedCommand -Label 'compose-down' -CommandArgs ($compose + @('down'))
}

Write-Host "Phase 3 results saved to: $RunDir"
