# IoT Secure Gateway - Mirai Mitigation

Phase 3 leaves the lab ready for reproducible performance and security testing with a 3-VM Vagrant setup:

- `fw`: gateway + nftables enforcement
- `iot`: protected IoT host behind the gateway
- `atk`: external attacker on a simulated WAN segment

## Topology

- IoT LAN: `10.20.0.0/24`
- Firewall IoT IP: `10.20.0.1`
- Simulated WAN: `192.168.56.0/24`
- Firewall WAN-sim IP: `192.168.56.2`
- IoT host: `10.20.0.10`
- Attacker host: `192.168.56.10`

## What Phase 3 Measures

- Accuracy: `ip_forward`, loaded nftables rules, IoT default route through the gateway, attacker route toward IoT through the gateway
- Allowed functionality: DNS and HTTPS egress from the IoT VM
- Security blocks: unauthorized HTTP from IoT, Mirai-style scans from `atk`, repeated Telnet attempts
- Enforcement evidence: nftables counters for WAN-to-IoT drops, allowed HTTPS, and NAT

## Quick Start

```powershell
vagrant up
vagrant provision
powershell -ExecutionPolicy Bypass -File .\scripts\run-phase3-evaluation.ps1 -Provision
```

For a clean report run:

```powershell
vagrant destroy -f
vagrant up
powershell -ExecutionPolicy Bypass -File .\scripts\run-phase3-evaluation.ps1 -Provision
```

## Generated Artifacts

The evaluation runner writes timestamped output under:

```text
artifacts\phase3\<timestamp>\
```

Expected files include:

- `summary.md`
- `summary.json`
- `fw-snapshot.txt`
- `fw-counters.txt`
- `iot-https-benchmark.txt`
- `iot-http-block.txt`
- `atk-scan.txt`
- `atk-telnet-burst.txt`

## Project Layout

```text
scripts/
  provision-fw.sh
  provision-iot.sh
  provision-atk.sh
  run-phase3-evaluation.ps1
  remote/
    fw-snapshot.sh
    fw-counters.sh
    iot-tests.sh
    atk-tests.sh
```
