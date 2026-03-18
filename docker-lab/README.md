# Docker Lab - IoT Secure Gateway

This folder contains a Docker-based equivalent of the current Vagrant lab. It keeps the same three roles:

- `fw`: firewall and gateway
- `iot`: internal IoT device on `10.20.0.0/24`
- `atk`: external attacker on `192.168.56.0/24`

The Docker version mirrors the current nftables policy:

- block inbound attacker-to-IoT forwarding
- allow IoT outbound DNS (`53`), NTP (`123`), and HTTPS (`443`)
- masquerade IoT traffic through the firewall external interface
- expose controlled Telnet-like listeners on the IoT container (`23` and `2323`) for stronger filtering evidence

## Layout

```text
docker-lab/
  atk/
  fw/
  iot/
  docker-compose.yml
  README.md
  Testing.md
```

## Prerequisites

- Docker Engine
- Docker Compose v2

## Start the lab

```bash
docker compose up --build -d
```

Run the command from this `docker-lab` directory.

## Stop the lab

```bash
docker compose down
```

To remove containers, networks, and volumes created by the stack:

```bash
docker compose down --volumes
```

## Quick checks

Check container status:

```bash
docker compose ps
```

Inspect the firewall rules:

```bash
docker compose exec fw nft list ruleset
```

Verify the attacker route to the IoT subnet:

```bash
docker compose exec atk ip route
```

Verify the IoT default route through the firewall:

```bash
docker compose exec iot ip route
```

Verify that the IoT test services are listening:

```bash
docker compose exec iot ss -lntp
```

## Notes

- This stack uses Docker bridge networks instead of full virtual machines, so containers share the host kernel.
- The internal network is marked `internal: true` so the IoT container cannot reach the internet unless traffic is forwarded through `fw`.
- Interface names are detected dynamically inside the firewall container to avoid the interface-name mismatch issue noted in the Vagrant lab.
- The IoT container rewrites `/etc/resolv.conf` to `1.1.1.1` at startup so outbound name resolution traverses the firewall path instead of relying on Docker's embedded resolver.
- Runtime evidence created at startup is written into `docker-lab/results/`.
- The firewall rules now include nftables counters so you can measure blocked and allowed traffic after each test.

## Phase 3

Run the automated Phase 3 suite from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-phase3.ps1
```

The script starts the lab, resets counters, runs baseline and attack tests, and writes evidence into `docker-lab/results/<timestamp>/`.

For the manual Phase 3 workflow and live monitoring commands, see `PHASE3.md`.

## Equivalent validation commands

Inbound Mirai-style scan from the attacker:

```bash
docker compose exec atk nmap -p 22,23,2323 10.20.0.10
```

Firewall packet observation:

```bash
docker compose exec fw tcpdump -i any host 10.20.0.10
```

Live firewall counters:

```bash
docker compose exec fw watch -n 1 nft list chain inet filter forward
```

Allowed outbound HTTPS from the IoT device:

```bash
docker compose exec iot curl https://example.com
```

Blocked outbound Telnet attempt from the IoT device:

```bash
docker compose exec iot nc -vz -w 5 1.1.1.1 23
```
