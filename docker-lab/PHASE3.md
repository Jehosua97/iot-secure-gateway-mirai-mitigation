# Phase 3 - Docker Performance and Evidence Testing

This guide extends the basic Docker lab with repeatable Phase 3 testing focused on accuracy, efficiency, and scalability.

## What changed for Phase 3

- The firewall rules use nftables `counter` actions so blocked and allowed packets can be measured directly.
- The IoT container exposes controlled listeners on TCP `22`, `23`, and `2323` so scans are targeting real services.
- The firewall now has a separate `internet_net` interface so outbound traffic behaves like the Vagrant lab NAT interface.
- A PowerShell automation script saves test evidence into `docker-lab/results/<timestamp>/`.

## 1. Start or rebuild the lab

```powershell
cd "c:\Users\Jehosua Joya\Desktop\Github Repos\iot-secure-gateway-mirai-mitigation\docker-lab"
docker compose up --build -d
```

## 2. Confirm the controlled IoT services exist

```powershell
docker compose exec iot ss -lntp
```

Expected result: listeners appear on `:22`, `:23`, and `:2323`.

## 3. Reset firewall counters before testing

```powershell
docker compose exec fw nft reset counters
docker compose exec fw nft list chain inet filter forward
```

## 4. Watch the firewall in real time

Packet view:

```powershell
docker compose exec fw tcpdump -n -i any host 10.20.0.10
```

Counter view:

```powershell
docker compose exec fw watch -n 1 nft list chain inet filter forward
```

Trace view:

```powershell
docker compose exec fw nft insert rule inet filter forward ip daddr 10.20.0.10 meta nftrace set 1
docker compose exec fw nft monitor trace
```

When you finish tracing, remove the temporary rule:

```powershell
docker compose exec fw nft delete rule inet filter forward handle <handle-number>
```

Use `docker compose exec fw nft -a list chain inet filter forward` to find the handle.

## 5. Accuracy tests

Mirai-style scan from attacker:

```powershell
docker compose exec atk nmap -Pn -p 22,23,2323 10.20.0.10
```

Direct connection attempts from attacker:

```powershell
docker compose exec atk nc -vz -w 5 10.20.0.10 22
docker compose exec atk nc -vz -w 5 10.20.0.10 23
docker compose exec atk nc -vz -w 5 10.20.0.10 2323
```

Show the firewall counters after the attack:

```powershell
docker compose exec fw nft list chain inet filter forward
```

## 6. Outbound policy tests

Verify the IoT route and outbound DNS path:

```powershell
docker compose exec iot ip route
docker compose exec iot dig @1.1.1.1 +time=2 +tries=1 example.com
```

Allowed outbound HTTPS with simple timing:

```powershell
docker compose exec iot sh -lc 'for i in 1 2 3 4 5; do curl -sS -o /dev/null -w "run=$i time_namelookup=%{time_namelookup} time_connect=%{time_connect} time_appconnect=%{time_appconnect} time_total=%{time_total}\n" https://example.com; done'
```

Blocked outbound services on ports `22`, `23`, and `2323`:

```powershell
docker compose exec iot nc -vz -w 5 1.1.1.1 22
docker compose exec iot nc -vz -w 5 1.1.1.1 23
docker compose exec iot nc -vz -w 5 1.1.1.1 2323
```

Show the firewall forward counters again:

```powershell
docker compose exec fw nft list chain inet filter forward
```

## 7. Scalability test

Run 50 parallel blocked connection attempts from the attacker:

```powershell
docker compose exec atk sh -lc 'for i in $(seq 1 50); do nc -vz -w 2 10.20.0.10 2323 >/dev/null 2>&1 & done; wait'
```

Then check the counters and container resource usage:

```powershell
docker compose exec fw nft list chain inet filter forward
docker stats --no-stream iot-fw iot-device attacker-outside
```

## 8. Automated run

To execute the full Phase 3 suite and save evidence automatically:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-phase3.ps1
```

The script creates a timestamped results folder containing:

- baseline network and rules snapshots
- IoT listener proof
- inbound attack outputs
- outbound DNS and HTTPS timing outputs
- blocked outbound 22, 23, and 2323 outputs
- scalability test output
- firewall counters before and after each stage
- container resource snapshots
