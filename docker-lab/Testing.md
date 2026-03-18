# IoT Secure Gateway - Docker Attack Simulation Test Commands

## 1. Start the Docker Lab

Launch the three containers defined in `docker-compose.yml`.

```bash
docker compose up --build -d
```

This starts the firewall (`fw`), IoT device (`iot`), and attacker (`atk`) containers.

## 2. Verify Container Status

Check that the full stack is running.

```bash
docker compose ps
```

Expected result: all three services show an `Up` status.

## 3. Verify IoT Services and DNS

Confirm the controlled listeners and DNS configuration inside the IoT container.

```bash
docker compose exec iot ss -lntp
docker compose exec iot cat /etc/resolv.conf
```

Expected result:

- listeners on TCP `23` and `2323`
- `nameserver 1.1.1.1` in `/etc/resolv.conf`

## 4. Reset and Inspect Firewall Counters

Reset counters before a clean measurement, then inspect the forward chain.

```bash
docker compose exec fw nft reset counters
docker compose exec fw nft list chain inet filter forward
```

## 5. Perform Mirai-Style Port Scanning

From the attacker container, simulate Mirai-style scanning of common IoT service ports.

```bash
docker compose exec atk nmap -Pn -p 22,23,2323 10.20.0.10
```

Expected result:

```text
PORT     STATE    SERVICE
22/tcp   filtered ssh
23/tcp   filtered telnet
2323/tcp filtered telnet-alt
```

## 6. Attempt Direct Service Access

Attempt to connect directly to the IoT listeners from the attacker.

```bash
docker compose exec atk nc -vz -w 5 10.20.0.10 23
docker compose exec atk nc -vz -w 5 10.20.0.10 2323
```

Expected behavior: the connections time out or are filtered.

## 7. Observe the Firewall in Real Time

Packet view:

```bash
docker compose exec fw tcpdump -n -i any host 10.20.0.10
```

Counter view:

```bash
docker compose exec fw watch -n 1 nft list chain inet filter forward
```

## 8. Test Allowed Outbound Traffic

DNS through the firewall path:

```bash
docker compose exec iot dig @1.1.1.1 +time=2 +tries=1 example.com
```

HTTPS timing:

```bash
docker compose exec iot sh -lc 'for i in 1 2 3 4 5; do curl -sS -o /dev/null -w "run=$i time_namelookup=%{time_namelookup} time_connect=%{time_connect} time_appconnect=%{time_appconnect} time_total=%{time_total}\n" https://example.com; done'
```

## 9. Test Blocked Outbound Traffic

```bash
docker compose exec iot nc -vz -w 5 1.1.1.1 23
```

Expected result: the Telnet attempt fails.

## 10. Run the Automated Phase 3 Suite

From PowerShell in the `docker-lab` directory, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-phase3.ps1
```

This creates a timestamped evidence folder under `docker-lab/results/`.
