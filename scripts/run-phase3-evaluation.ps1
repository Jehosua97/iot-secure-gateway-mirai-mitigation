[CmdletBinding()]
param(
    [switch]$Provision,
    [string]$ArtifactsRoot = "artifacts/phase3"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $RepoRoot

function Write-Info {
    param([string]$Message)
    Write-Host "[phase3] $Message"
}

function Join-Lines {
    param([object[]]$Lines)
    return ($Lines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
}

function Invoke-VagrantCommand {
    param(
        [string[]]$Arguments,
        [string]$Description
    )

    if ($Description) {
        Write-Info $Description
    }

    $output = & vagrant @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = Join-Lines $output

    if ($exitCode -ne 0) {
        throw "vagrant $($Arguments -join ' ') failed with exit code $exitCode.`n$text"
    }

    return $text
}

function Quote-BashArgument {
    param([string]$Value)
    $escapedValue = $Value -replace "'", "'\''"
    return "'$escapedValue'"
}

function Join-BashCommand {
    param([string[]]$Parts)
    return ($Parts | ForEach-Object { Quote-BashArgument $_ }) -join " "
}

function Invoke-RemoteScript {
    param(
        [string]$Vm,
        [string]$ScriptPath,
        [string[]]$Arguments = @(),
        [switch]$Sudo
    )

    $parts = @("bash", $ScriptPath) + $Arguments
    $command = Join-BashCommand $parts
    if ($Sudo) {
        $command = "sudo $command"
    }

    return Invoke-VagrantCommand -Arguments @("ssh", $Vm, "-c", $command) -Description "Running remote check on $Vm"
}

function Get-VmStates {
    $raw = Invoke-VagrantCommand -Arguments @("status", "--machine-readable") -Description "Reading VM status"
    $states = @{}

    foreach ($line in ($raw -split "`r?`n")) {
        $parts = $line.Split(",")
        if ($parts.Length -ge 4 -and $parts[2] -eq "state") {
            $states[$parts[1]] = $parts[3]
        }
    }

    return $states
}

function Ensure-LabReady {
    $required = "fw", "iot", "atk"
    $states = Get-VmStates
    $needsUp = $false

    foreach ($vm in $required) {
        if (-not $states.ContainsKey($vm) -or $states[$vm] -ne "running") {
            $needsUp = $true
        }
    }

    if ($needsUp) {
        Invoke-VagrantCommand -Arguments @("up") -Description "Starting Vagrant lab"
    }

    if ($Provision) {
        Invoke-VagrantCommand -Arguments @("provision") -Description "Re-provisioning all VMs"
    }
}

function New-ArtifactDirectory {
    param([string]$BasePath)

    $resolvedBase = Join-Path $RepoRoot $BasePath
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fullPath = Join-Path $resolvedBase $timestamp
    New-Item -ItemType Directory -Force -Path $fullPath | Out-Null
    return $fullPath
}

function Write-Utf8File {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Add-Result {
    param(
        [System.Collections.Generic.List[object]]$Collection,
        [string]$Category,
        [string]$Name,
        [bool]$Passed,
        [string]$Details,
        [string]$Artifact
    )

    $Collection.Add([pscustomobject]@{
        category = $Category
        name = $Name
        status = if ($Passed) { "PASS" } else { "FAIL" }
        details = $Details
        artifact = $Artifact
    })
}

function Parse-NftRuleset {
    param([string]$JsonText)

    $start = $JsonText.IndexOf("{")
    $end = $JsonText.LastIndexOf("}")
    if ($start -lt 0 -or $end -lt $start) {
        throw "Unable to find nft JSON payload in remote output."
    }

    $payload = $JsonText.Substring($start, ($end - $start + 1))
    return $payload | ConvertFrom-Json -Depth 50
}

function Get-NftCounter {
    param(
        [object]$Ruleset,
        [string]$Comment
    )

    foreach ($entry in $Ruleset.nftables) {
        if (-not $entry.rule) {
            continue
        }

        $rule = $entry.rule
        if ($rule.comment -ne $Comment) {
            continue
        }

        foreach ($expr in $rule.expr) {
            if ($expr.counter) {
                return [pscustomobject]@{
                    packets = [int64]$expr.counter.packets
                    bytes = [int64]$expr.counter.bytes
                }
            }
        }
    }

    return $null
}

function Get-CounterDelta {
    param(
        [object]$Before,
        [object]$After,
        [string]$Comment
    )

    $beforeCounter = Get-NftCounter -Ruleset $Before -Comment $Comment
    $afterCounter = Get-NftCounter -Ruleset $After -Comment $Comment

    if (-not $afterCounter) {
        return $null
    }

    $beforePackets = if ($beforeCounter) { $beforeCounter.packets } else { 0 }
    $beforeBytes = if ($beforeCounter) { $beforeCounter.bytes } else { 0 }

    return [pscustomobject]@{
        comment = $Comment
        before_packets = $beforePackets
        after_packets = $afterCounter.packets
        delta_packets = $afterCounter.packets - $beforePackets
        before_bytes = $beforeBytes
        after_bytes = $afterCounter.bytes
        delta_bytes = $afterCounter.bytes - $beforeBytes
    }
}

function New-MarkdownSummary {
    param(
        [object[]]$Results,
        [object[]]$Counters,
        [string]$RelativeArtifactDir
    )

    $passed = @($Results | Where-Object status -eq "PASS").Count
    $failed = @($Results | Where-Object status -eq "FAIL").Count
    $sections = "Accuracy", "Allowed Functionality", "Security Blocks", "Enforcement Evidence"

    $lines = @(
        "# Phase 3 Evaluation Summary",
        "",
        "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')",
        "",
        "Artifacts directory: ``$RelativeArtifactDir``",
        "",
        "Overall: **$passed passed**, **$failed failed**.",
        ""
    )

    foreach ($section in $sections) {
        $sectionResults = @($Results | Where-Object category -eq $section)
        if (-not $sectionResults) {
            continue
        }

        $lines += "## $section"
        $lines += ""
        $lines += "| Test | Status | Details | Artifact |"
        $lines += "| --- | --- | --- | --- |"
        foreach ($result in $sectionResults) {
            $artifactText = if ($result.artifact) { $result.artifact } else { "-" }
            $details = ($result.details -replace "\|", "/")
            $lines += "| $($result.name) | $($result.status) | $details | $artifactText |"
        }
        $lines += ""
    }

    if ($Counters) {
        $lines += "## Counter Deltas"
        $lines += ""
        $lines += "| Counter | Before | After | Delta |"
        $lines += "| --- | --- | --- | --- |"
        foreach ($counter in $Counters) {
            $lines += "| $($counter.comment) | $($counter.before_packets) | $($counter.after_packets) | $($counter.delta_packets) |"
        }
        $lines += ""
    }

    return ($lines -join [Environment]::NewLine)
}

if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
    throw "Vagrant is not available in PATH."
}

$artifactDir = New-ArtifactDirectory -BasePath $ArtifactsRoot
$relativeArtifactDir = Resolve-Path -Relative $artifactDir
$results = New-Object 'System.Collections.Generic.List[object]'

Write-Info "Artifacts will be written to $artifactDir"
Ensure-LabReady

$beforeRulesetText = Invoke-RemoteScript -Vm "fw" -ScriptPath "/vagrant/scripts/remote/fw-counters.sh" -Arguments @("--json") -Sudo
$beforeRuleset = Parse-NftRuleset $beforeRulesetText

$fwSnapshot = Invoke-RemoteScript -Vm "fw" -ScriptPath "/vagrant/scripts/remote/fw-snapshot.sh" -Sudo
Write-Utf8File -Path (Join-Path $artifactDir "fw-snapshot.txt") -Content $fwSnapshot

$iotRoute = Invoke-RemoteScript -Vm "iot" -ScriptPath "/vagrant/scripts/remote/iot-tests.sh" -Arguments @("route")
Write-Utf8File -Path (Join-Path $artifactDir "iot-route.txt") -Content $iotRoute

$atkRoute = Invoke-RemoteScript -Vm "atk" -ScriptPath "/vagrant/scripts/remote/atk-tests.sh" -Arguments @("route", "10.20.0.10")
Write-Utf8File -Path (Join-Path $artifactDir "atk-route.txt") -Content $atkRoute

$dnsOutput = Invoke-RemoteScript -Vm "iot" -ScriptPath "/vagrant/scripts/remote/iot-tests.sh" -Arguments @("dns")
Write-Utf8File -Path (Join-Path $artifactDir "iot-dns.txt") -Content $dnsOutput

$httpsOutput = Invoke-RemoteScript -Vm "iot" -ScriptPath "/vagrant/scripts/remote/iot-tests.sh" -Arguments @("https")
Write-Utf8File -Path (Join-Path $artifactDir "iot-https-benchmark.txt") -Content $httpsOutput

$httpBlockOutput = Invoke-RemoteScript -Vm "iot" -ScriptPath "/vagrant/scripts/remote/iot-tests.sh" -Arguments @("http-block")
Write-Utf8File -Path (Join-Path $artifactDir "iot-http-block.txt") -Content $httpBlockOutput

$scanOutput = Invoke-RemoteScript -Vm "atk" -ScriptPath "/vagrant/scripts/remote/atk-tests.sh" -Arguments @("scan", "10.20.0.10")
Write-Utf8File -Path (Join-Path $artifactDir "atk-scan.txt") -Content $scanOutput

$burstOutput = Invoke-RemoteScript -Vm "atk" -ScriptPath "/vagrant/scripts/remote/atk-tests.sh" -Arguments @("telnet-burst", "10.20.0.10", "12")
Write-Utf8File -Path (Join-Path $artifactDir "atk-telnet-burst.txt") -Content $burstOutput

$afterRulesetText = Invoke-RemoteScript -Vm "fw" -ScriptPath "/vagrant/scripts/remote/fw-counters.sh" -Arguments @("--json") -Sudo
$afterRuleset = Parse-NftRuleset $afterRulesetText

$fwCountersText = Invoke-RemoteScript -Vm "fw" -ScriptPath "/vagrant/scripts/remote/fw-counters.sh" -Sudo
Write-Utf8File -Path (Join-Path $artifactDir "fw-counters.txt") -Content $fwCountersText
Write-Utf8File -Path (Join-Path $artifactDir "fw-counters.json") -Content $afterRulesetText

$ipForwardPassed = $fwSnapshot -match "== ip_forward ==\s+1\b"
$rulesLoadedPassed = $fwSnapshot -match "table inet filter" -and $fwSnapshot -match 'comment "wan_to_iot_drop"'
$iotRoutePassed = $iotRoute -match "default via 10\.20\.0\.1"
$atkRoutePassed = $atkRoute -match "via 192\.168\.56\.2"
$dnsPassed = $dnsOutput -match "(?m)^\d{1,3}(?:\.\d{1,3}){3}$"
$httpsPassed = $httpsOutput -match "http_code=200"
$httpBlockedPassed = $httpBlockOutput -match "blocked as expected"
$scanBlockedPassed = (($scanOutput -notmatch "23/tcp\s+open") -and ($scanOutput -notmatch "2323/tcp\s+open")) -and (($scanOutput -match "filtered") -or ($scanOutput -match "0 hosts up") -or ($scanOutput -match "host seems down"))
$burstBlockedPassed = $burstOutput -match "SUCCESSFUL_CONNECTIONS=0"

$counterComments = "wan_to_iot_drop", "iot_https_allow", "iot_nat"
$counterDeltas = foreach ($comment in $counterComments) {
    Get-CounterDelta -Before $beforeRuleset -After $afterRuleset -Comment $comment
}

$wanDropCounter = @($counterDeltas | Where-Object { $_ -and $_.comment -eq "wan_to_iot_drop" })[0]
$httpsCounter = @($counterDeltas | Where-Object { $_ -and $_.comment -eq "iot_https_allow" })[0]
$natCounter = @($counterDeltas | Where-Object { $_ -and $_.comment -eq "iot_nat" })[0]

Add-Result -Collection $results -Category "Accuracy" -Name "IP forwarding enabled" -Passed $ipForwardPassed -Details "Expected /proc/sys/net/ipv4/ip_forward to equal 1." -Artifact "fw-snapshot.txt"
Add-Result -Collection $results -Category "Accuracy" -Name "Firewall rules loaded" -Passed $rulesLoadedPassed -Details "Expected nftables filter/NAT rules with named comments." -Artifact "fw-snapshot.txt"
Add-Result -Collection $results -Category "Accuracy" -Name "IoT routes through gateway" -Passed $iotRoutePassed -Details ($iotRoute.Trim()) -Artifact "iot-route.txt"
Add-Result -Collection $results -Category "Accuracy" -Name "Attacker reaches IoT via gateway" -Passed $atkRoutePassed -Details ($atkRoute.Trim()) -Artifact "atk-route.txt"

Add-Result -Collection $results -Category "Allowed Functionality" -Name "DNS from IoT" -Passed $dnsPassed -Details ("Resolved address: " + ($dnsOutput.Trim())) -Artifact "iot-dns.txt"
Add-Result -Collection $results -Category "Allowed Functionality" -Name "HTTPS from IoT" -Passed $httpsPassed -Details (($httpsOutput -split "`r?`n" | Where-Object { $_ -match "^(http_code|time_total|remote_ip)=" }) -join "; ") -Artifact "iot-https-benchmark.txt"

Add-Result -Collection $results -Category "Security Blocks" -Name "Unauthorized HTTP blocked" -Passed $httpBlockedPassed -Details ($httpBlockOutput.Trim()) -Artifact "iot-http-block.txt"
Add-Result -Collection $results -Category "Security Blocks" -Name "Mirai-style scan blocked" -Passed $scanBlockedPassed -Details "Expected no open Telnet-style ports on 10.20.0.10." -Artifact "atk-scan.txt"
Add-Result -Collection $results -Category "Security Blocks" -Name "Repeated Telnet attempts blocked" -Passed $burstBlockedPassed -Details ($burstOutput.Trim()) -Artifact "atk-telnet-burst.txt"

Add-Result -Collection $results -Category "Enforcement Evidence" -Name "WAN to IoT drop counter increments" -Passed ([bool]($wanDropCounter -and $wanDropCounter.delta_packets -gt 0)) -Details ("Delta packets: " + ($(if ($wanDropCounter) { $wanDropCounter.delta_packets } else { "missing" }))) -Artifact "fw-counters.txt"
Add-Result -Collection $results -Category "Enforcement Evidence" -Name "HTTPS allow counter increments" -Passed ([bool]($httpsCounter -and $httpsCounter.delta_packets -gt 0)) -Details ("Delta packets: " + ($(if ($httpsCounter) { $httpsCounter.delta_packets } else { "missing" }))) -Artifact "fw-counters.txt"
Add-Result -Collection $results -Category "Enforcement Evidence" -Name "NAT counter increments" -Passed ([bool]($natCounter -and $natCounter.delta_packets -gt 0)) -Details ("Delta packets: " + ($(if ($natCounter) { $natCounter.delta_packets } else { "missing" }))) -Artifact "fw-counters.txt"

$summaryMarkdown = New-MarkdownSummary -Results $results.ToArray() -Counters @($counterDeltas | Where-Object { $_ }) -RelativeArtifactDir $relativeArtifactDir
Write-Utf8File -Path (Join-Path $artifactDir "summary.md") -Content $summaryMarkdown

$summaryObject = [pscustomobject]@{
    generated_at = (Get-Date).ToString("o")
    artifact_dir = $artifactDir
    passed = @($results | Where-Object status -eq "PASS").Count
    failed = @($results | Where-Object status -eq "FAIL").Count
    results = $results.ToArray()
    counters = @($counterDeltas | Where-Object { $_ })
}

$summaryJson = $summaryObject | ConvertTo-Json -Depth 10
Write-Utf8File -Path (Join-Path $artifactDir "summary.json") -Content $summaryJson

Write-Info "Evaluation completed. Summary: $artifactDir"
