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

## 3. Access the Firewall Container

Open a shell inside the firewall container.

```bash
docker compose exec fw bash
```

The firewall acts as the routing and filtering boundary between the WAN and the IoT network.

Exit the shell when finished:

```bash
exit
```

## 4. Access the IoT Container

Open a shell inside the simulated IoT device.

```bash
docker compose exec iot bash
```

Verify its IP address:

```bash
ip a
```

Expected IP address:

```text
10.20.0.10
```

Exit the shell when finished:

```bash
exit
```

## 5. Access the Attacker Container

Open a shell inside the attacker container.

```bash
docker compose exec atk bash
```

Verify its IP address:

```bash
ip a
```

Expected IP address:

```text
192.168.56.10
```

This container simulates an external host attempting to attack the IoT device.

## 6. Perform Mirai-Style Port Scanning

From the attacker container, simulate Mirai-style scanning of common IoT service ports.

```bash
docker compose exec atk nmap -p 22,23,2323 10.20.0.10
```

Expected result:

```text
PORT     STATE    SERVICE
22/tcp   filtered ssh
23/tcp   filtered telnet
2323/tcp filtered telnet-alt
```

This confirms that the firewall blocks inbound scanning attempts from the attacker network.

## 7. Attempt Direct Service Access

Attempt to connect directly to the IoT device services from the attacker.

```bash
docker compose exec atk nc -vz 10.20.0.10 23
docker compose exec atk nc -vz 10.20.0.10 22
```

Expected behavior: the connections time out or are filtered.

## 8. Monitor Traffic on the Firewall

Observe packets on the firewall in real time.

```bash
docker compose exec fw tcpdump -i any host 10.20.0.10
```

While `tcpdump` is running, repeat the scan from step 6.

## 9. Inspect Firewall Rules

Verify that the nftables rules are active.

```bash
docker compose exec fw nft list ruleset
```

The `forward` chain should show a default `drop` policy and explicit allow rules for outbound DNS, NTP, and HTTPS traffic.

## 10. Test Outbound IoT Connectivity

From the IoT container, test allowed outbound HTTPS access.

```bash
docker compose exec iot curl https://example.com
```

Then test a blocked outbound Telnet connection:

```bash
docker compose exec iot nc -vz -w 5 1.1.1.1 23
```

Expected result: HTTPS succeeds while the Telnet attempt fails.
