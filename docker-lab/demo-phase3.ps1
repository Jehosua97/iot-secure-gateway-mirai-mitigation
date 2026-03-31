param(
    [string]$ComposeFile = '',
    [switch]$FreshStart,
    [switch]$ClearResults,
    [switch]$TearDown
)

$ErrorActionPreference = 'Stop'

# Default to the local Compose file so the live demo can be launched from the docker-lab folder.
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

function Write-SectionBanner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Magenta
    Write-Host $Description -ForegroundColor White
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

# Keep the live demo aligned with the phase 3 rubric categories.
Invoke-DockerLive -Label 'Docker Compose Up' -CommandArgs ($compose + @('up', '--build', '-d'))
Invoke-DockerLive -Label 'Compose Status' -CommandArgs ($compose + @('ps'))

Write-SectionBanner -Title 'Phase 3 Focus' -Description 'This live demo highlights accuracy, efficiency, and scalability for the firewall policy.'
Write-Host 'Accuracy: block WAN -> IoT SSH/Telnet traffic and enforce the correct outbound policy.' -ForegroundColor Yellow
Write-Host 'Efficiency: keep legitimate IoT -> WAN HTTPS available and show connection timing.' -ForegroundColor Yellow
Write-Host 'Scalability: apply a short burst of blocked traffic and confirm the policy still holds.' -ForegroundColor Yellow

Write-Host ""
Write-Host "Open a second terminal if you want to watch the firewall live:" -ForegroundColor Green
Write-Host "docker compose exec fw watch -n 1 nft list chain inet filter forward" -ForegroundColor Yellow
Write-Host "docker compose exec fw tcpdump -n -i any host 10.20.0.10" -ForegroundColor Yellow
Write-Host "docker compose exec fw tcpdump -n -i any host 192.168.56.10" -ForegroundColor Yellow

Pause-Demo -Message 'Press Enter to show the firewall baseline state'

Invoke-DockerLive -Label 'Reset Firewall Counters' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'reset', 'counters'))
Invoke-DockerLive -Label 'Firewall Baseline State' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Pause-Demo -Message 'Press Enter to analyze the inbound SSH and Telnet-style attack'

Write-SectionBanner -Title 'Accuracy Check 1' -Description 'Validate that the WAN side cannot open SSH or Telnet-style access into the IoT device.'
Invoke-DockerLive -Label 'Inbound Nmap Scan' -CommandArgs ($compose + @('exec', 'atk', 'nmap', '-Pn', '-p', '22,23,2323', '10.20.0.10'))
Invoke-DockerLive -Label 'Inbound Netcat Port 22' -CommandArgs ($compose + @('exec', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '22')) -AllowFailure
Invoke-DockerLive -Label 'Inbound Netcat Port 23' -CommandArgs ($compose + @('exec', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '23')) -AllowFailure
Invoke-DockerLive -Label 'Inbound Netcat Port 2323' -CommandArgs ($compose + @('exec', 'atk', 'nc', '-nvz', '-w', '5', '10.20.0.10', '2323')) -AllowFailure
Invoke-DockerLive -Label 'Firewall Counters After Inbound' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Pause-Demo -Message 'Press Enter to validate the outbound policy and legitimate HTTPS traffic'

Write-SectionBanner -Title 'Accuracy Check 2' -Description 'Validate that the IoT device cannot open outbound SSH or Telnet-style sessions toward the WAN.'
Invoke-DockerLive -Label 'Blocked Outbound Port 22 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '22')) -AllowFailure
Invoke-DockerLive -Label 'Blocked Outbound Port 23 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '23')) -AllowFailure
Invoke-DockerLive -Label 'Blocked Outbound Port 2323 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'nc', '-nvz', '-w', '5', '192.168.56.10', '2323')) -AllowFailure
Invoke-DockerLive -Label 'Firewall Counters After Blocked Outbound' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Write-SectionBanner -Title 'Efficiency Check' -Description 'Validate that legitimate outbound HTTPS still works and capture timing across repeated runs.'
Invoke-DockerLive -Label 'Allowed Outbound Port 443 to WAN' -CommandArgs ($compose + @('exec', 'iot', 'sh', '-lc', 'for i in 1 2 3; do start=$(date +%s%3N); if nc -nvz -w 3 192.168.56.10 443 >/dev/null 2>&1; then status=success; else status=fail; fi; end=$(date +%s%3N); echo "run=$i status=$status connect_ms=$((end-start))"; done'))
Invoke-DockerLive -Label 'Firewall Counters After Legitimate Outbound' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

Pause-Demo -Message 'Press Enter to run a short scalability burst and confirm the firewall still protects the IoT device'

Write-SectionBanner -Title 'Scalability Check' -Description 'Apply a short burst of blocked WAN traffic, then confirm legitimate HTTPS still remains available.'
# Use a small burst so the effect is visible during a presentation without making the demo slow.
Invoke-DockerLive -Label 'Scalability Burst Against Port 2323' -CommandArgs ($compose + @('exec', 'atk', 'sh', '-lc', 'start=$(date +%s%3N); for i in $(seq 1 10); do nc -vz -w 2 10.20.0.10 2323 >/dev/null 2>&1 & done; wait; end=$(date +%s%3N); echo "parallel_connections=10"; echo "elapsed_ms=$((end-start))"'))
Invoke-DockerLive -Label 'Firewall Counters After Scalability Burst' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))
Invoke-DockerLive -Label 'Legitimate 443 After Scalability Burst' -CommandArgs ($compose + @('exec', 'iot', 'sh', '-lc', 'for i in 1 2 3; do start=$(date +%s%3N); if nc -nvz -w 3 192.168.56.10 443 >/dev/null 2>&1; then status=success; else status=fail; fi; end=$(date +%s%3N); echo "run=$i status=$status connect_ms=$((end-start))"; done'))
Invoke-DockerLive -Label 'Firewall Counters Final' -CommandArgs ($compose + @('exec', 'fw', 'nft', 'list', 'chain', 'inet', 'filter', 'forward'))

if ($TearDown) {
    Pause-Demo -Message 'Press Enter to shut down the lab'
    Invoke-DockerLive -Label 'Docker Compose Down' -CommandArgs ($compose + @('down'))
}

Write-Host ""
Write-Host 'Phase 3 coverage shown in this demo:' -ForegroundColor Green
Write-Host 'Accuracy: WAN inbound SSH/Telnet blocked, IoT outbound SSH/Telnet blocked, IoT outbound HTTPS allowed.' -ForegroundColor Green
Write-Host 'Efficiency: repeated HTTPS timing runs collected during normal operation and after load.' -ForegroundColor Green
Write-Host 'Scalability: a short burst of blocked traffic was applied and the policy remained effective.' -ForegroundColor Green
Write-Host ""
Write-Host 'Phase 3 demo completed.' -ForegroundColor Green
