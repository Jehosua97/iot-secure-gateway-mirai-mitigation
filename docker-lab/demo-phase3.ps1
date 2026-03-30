param(
    [string]$ComposeFile = '',
    [switch]$FreshStart,
    [switch]$ClearResults,
    [switch]$TearDown
)

$ErrorActionPreference = 'Stop'

if (-not $ComposeFile) {
    $ComposeFile = Join-Path $PSScriptRoot 'docker-compose.yml'
}

$ResultsRoot = Join-Path $PSScriptRoot 'results'
$compose = @('compose', '-f', $ComposeFile)

function Convert-ToDockerArgumentString {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$CommandArgs
    )

    ($CommandArgs | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }) -join ' '
}

function Invoke-DockerLive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string[]]$CommandArgs,

        [switch]$AllowFailure
    )

    Write-Host ""
    Write-Host "=== $Label ===" -ForegroundColor Cyan
    Write-Host "docker $($CommandArgs -join ' ')" -ForegroundColor DarkGray

    $argumentString = Convert-ToDockerArgumentString -CommandArgs $CommandArgs
    & cmd /c "docker $argumentString"
    $exitCode = $LASTEXITCODE

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "Command failed for $Label with exit code $exitCode."
    }
}

function Pause-Demo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Read-Host "$Message"
}

function Clear-DemoResults {
    if (-not (Test-Path $ResultsRoot)) {
        return
    }

    $resultsPath = Resolve-Path $ResultsRoot
    Get-ChildItem -LiteralPath $resultsPath -Force |
        Where-Object { $_.Name -ne '.gitkeep' } |
        Remove-Item -Recurse -Force

    Write-Host "Results cleared in $ResultsRoot" -ForegroundColor Yellow
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is not installed or not available in PATH.'
}

if ($ClearResults) {
    Clear-DemoResults
}

if ($FreshStart) {
    Invoke-DockerLive -Label 'Docker Compose Down' -CommandArgs ($compose + @('down')) -AllowFailure
}

Invoke-DockerLive -Label 'Docker Compose Up' -CommandArgs ($compose + @('up', '--build', '-d'))
Invoke-DockerLive -Label 'Compose Status' -CommandArgs ($compose + @('ps'))

Write-Host ""
Write-Host "Open a second terminal if you want to watch the firewall live:" -ForegroundColor Green
Write-Host "docker compose exec fw watch -n 1 nft list chain inet filter forward" -ForegroundColor Yellow
Write-Host "docker compose exec fw tcpdump -n -i any host 10.20.0.10" -ForegroundColor Yellow
Write-Host "docker compose exec fw tcpdump -n -i any host 192.168.56.10" -ForegroundColor Yellow

Pause-Demo -Message 'Press Enter to show the lab baseline'

Invoke-DockerLive -Label 'Firewall Interfaces' -CommandArgs ($compose + @('exec', 'fw', 'ip', '-br', 'addr'))
Invoke-DockerLive -Label 'IoT Routes' -CommandArgs ($compose + @('exec', 'iot', 'ip', 'route'))
Invoke-DockerLive -Label 'Attacker Routes' -CommandArgs ($compose + @('exec', 'atk', 'ip', 'route'))
Invoke-DockerLive -Label 'IoT Services' -CommandArgs ($compose + @('exec', 'iot', 'ss', '-lntp'))
Invoke-DockerLive -Label 'WAN Services on Attacker' -CommandArgs ($compose + @('exec', 'atk', 'ss', '-lntp'))
Invoke-DockerLive -Label 'Reset Firewall Counters' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'reset', 'counters'))
Invoke-DockerLive -Label 'Firewall Forward Chain Baseline' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Pause-Demo -Message 'Press Enter to analyze the inbound SSH and Telnet-style attack'

Invoke-DockerLive -Label 'Inbound Nmap Scan' -CommandArgs ($compose + @('exec', 'atk', 'nmap', '-Pn', '-p', '22,23,2323', '10.20.0.10'))
Invoke-DockerLive -Label 'Inbound Netcat Port 22' -CommandArgs ($compose + @('exec', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '22')) -AllowFailure
Invoke-DockerLive -Label 'Inbound Netcat Port 23' -CommandArgs ($compose + @('exec', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '23')) -AllowFailure
Invoke-DockerLive -Label 'Inbound Netcat Port 2323' -CommandArgs ($compose + @('exec', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '2323')) -AllowFailure
Invoke-DockerLive -Label 'Firewall Counters After Inbound' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Pause-Demo -Message 'Press Enter to validate the outbound policy: blocked SSH and Telnet, allowed HTTPS'

Invoke-DockerLive -Label 'Blocked Outbound Port 22 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '22')) -AllowFailure
Invoke-DockerLive -Label 'Blocked Outbound Port 23 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '23')) -AllowFailure
Invoke-DockerLive -Label 'Blocked Outbound Port 2323 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '2323')) -AllowFailure
Invoke-DockerLive -Label 'Firewall Counters After Blocked Outbound' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Invoke-DockerLive -Label 'Allowed Outbound Port 443 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'sh', '-lc', 'for i in 1 2 3; do start=$(date +%s%3N); if nc -nvz -w 3 192.168.56.10 443 >/dev/null 2>&1; then status=success; else status=fail; fi; end=$(date +%s%3N); echo "run=$i status=$status connect_ms=$((end-start))"; done'))
Invoke-DockerLive -Label 'Firewall Counters After Legitimate Outbound' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

if ($TearDown) {
    Pause-Demo -Message 'Press Enter to shut down the lab'
    Invoke-DockerLive -Label 'Docker Compose Down' -CommandArgs ($compose + @('down'))
}

Write-Host ""
Write-Host 'Phase 3 demo completed.' -ForegroundColor Green
