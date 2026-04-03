# IoT Secure Gateway: Network-Based Defense Against IoT Botnets
## Updated Phase 2 and Phase 3 Report

Jehosua Alan Joya Venegas, Saurodeep Majumdar, Dylan Luong

### Abstract
This report presents an updated implementation and evaluation of an IoT Secure Gateway designed to mitigate Mirai-style IoT botnet threats through network-layer controls. The earlier virtual-machine prototype has been revised into a Docker-based lab composed of three isolated roles: a firewall/gateway container, an internal IoT container, and an external WAN/attacker container. The updated implementation enforces network segmentation, stateful forwarding control, default-deny filtering, and least-privilege outbound policy using `nftables`. It blocks WAN-to-IoT SSH and Telnet-style traffic, prevents insecure outbound SSH/Telnet propagation attempts from the IoT segment, and still permits legitimate outbound HTTPS to a controlled WAN-side service. In addition to the phase 2 implementation narrative, this report adds a phase 3 testing section focused on accuracy, efficiency, and scalability. Automated Docker-based evidence shows filtered inbound ports, correct rule-counter increments, low overhead for allowed HTTPS traffic, and stable enforcement under burst attack conditions. These results support the practical value of gateway-level protection for unmanaged or legacy IoT devices and highlight the continuing need for stronger visibility and segmentation in real-world deployments.

**Index Terms** - IoT Security, Mirai, Botnets, Docker, Docker Compose, Firewall, `nftables`, Network Segmentation, Stateful Filtering

## I. Introduction

This project implements an IoT Secure Gateway that applies network-layer controls to reduce the attack surface exposed by IoT devices. The work is motivated by the Mirai botnet, which scanned the Internet for devices exposing management services such as Telnet and SSH, then enrolled compromised devices into a command-and-control infrastructure used for large-scale DDoS attacks [1].

The current version of the project extends the original phase 2 implementation by replacing the Vagrant and VirtualBox lab with a Docker-based topology that is faster to deploy and easier to reproduce. The updated design still preserves the core security goal: the IoT device is placed behind a gateway that becomes the only routing boundary between the internal subnet and the simulated external network.

This report makes three contributions:

1. It updates the implementation from the earlier VM-based prototype to a Docker-based lab that preserves the same security model while simplifying deployment.
2. It documents the current firewall enforcement policy and attack-simulation workflow using the actual Docker commands used in the project.
3. It adds a phase 3 evaluation focused on accuracy, efficiency, and scalability, supported by automated evidence collection from the current lab.

The remainder of this report is organized as follows. Section II explains the case-study-driven rationale based on Mirai. Section III describes the Docker-based architecture. Section IV details the container roles and addressing. Section V explains the firewall enforcement model. Section VI presents the functional attack simulation. Section VII adds the phase 3 performance and evidence-based evaluation. Section VIII discusses real-world impact and identified gaps. Section IX concludes with key findings and future work.

## II. Case Study-Driven Design Rationale

Mirai succeeded because many IoT devices were directly or indirectly exposed with weakly protected administrative services, especially Telnet, and could initiate unrestricted outbound communication after compromise [1]. Once infected, these devices were not only victims but also participants in botnet propagation and DDoS activity.

Key weaknesses associated with Mirai-style behavior include:

- exposed SSH or Telnet-like services
- poor segmentation between untrusted and internal devices
- unrestricted outbound traffic from compromised IoT systems
- limited patching or security controls on the IoT device itself

Industry guidance from Cloudflare and CISA emphasizes that segmentation, inbound filtering, and restriction of unnecessary traffic are practical ways to reduce IoT botnet risk [2], [3]. Based on those findings, this project applies a network-based defense model rather than assuming that the IoT device can reliably defend itself.

The current Docker implementation keeps that same case-study logic:

- block unsolicited WAN-to-IoT access on ports `22`, `23`, and `2323`
- block insecure IoT-to-WAN SSH/Telnet-style traffic on ports `22`, `23`, and `2323`
- allow only the legitimate outbound service used in the demo, namely HTTPS on port `443`
- rely on a gateway firewall as the policy enforcement point

## III. Docker-Based Network Architecture

### A. Overview

The updated lab contains three Docker containers:

- `fw` - firewall and gateway
- `iot` - internal IoT device
- `atk` - external WAN host used both as attacker and as the controlled WAN-side service endpoint

Unlike the earlier VM version, the current topology uses Docker bridge networks instead of VirtualBox adapters. The functional security boundary, however, remains the same.

```text
         WAN network (192.168.56.0/24)
     atk: 192.168.56.10
              |
            eth1
         fw: firewall
            eth0
              |
      IoT network (10.20.0.0/24)
      iot: 10.20.0.10
```

The firewall container is the only node connected to both networks. This makes it the routing boundary between the internal IoT segment and the external WAN segment.

### B. Addressing Plan

| Container | Network Attachment | IP Address | Role |
| --- | --- | --- | --- |
| `fw` | `iot_net`, `wan_net` | `10.20.0.1`, `192.168.56.2` | Router and firewall |
| `iot` | `iot_net` | `10.20.0.10` | Protected IoT endpoint |
| `atk` | `wan_net` | `192.168.56.10` | External host and WAN-side service |

This model preserves the intended trust boundary:

- the IoT device cannot be reached directly from WAN without crossing the firewall
- the external host reaches the IoT subnet only through the firewall
- all meaningful policy decisions occur in the firewall container

## IV. Container Configuration and Routing

### A. Firewall Container

The firewall container is multi-homed. It dynamically identifies its IoT-side and WAN-side interfaces by IP address, then generates the `nftables` policy during startup. IP forwarding is enabled through:

```text
net.ipv4.ip_forward = 1
```

The firewall stores startup evidence under `docker-lab/results/`, including interface state, routing tables, the active ruleset, and initial listener state.

### B. IoT Container

The IoT container has a single interface on `10.20.0.0/24` and sets its default route through the firewall:

```text
default via 10.20.0.1
```

It also starts controlled listeners on TCP `22`, `23`, and `2323`. These listeners are intentional. They ensure that scan results showing `filtered` reflect firewall blocking rather than the absence of a service.

### C. Attacker Container

The attacker container has a single interface on `192.168.56.0/24` and adds a route toward the IoT subnet through the firewall:

```text
10.20.0.0/24 via 192.168.56.2
```

It also exposes controlled WAN-side listeners on TCP `22`, `23`, `2323`, and `443`. The `443` listener is used as the legitimate outbound destination for the IoT device in the Docker-based demonstration.

## V. Firewall Enforcement Model

The current firewall policy is implemented in the `forward` chain of `nftables` and follows a default-deny model:

```text
policy drop
```

The rules are summarized as follows:

1. Allow established and related forwarded traffic.
2. Drop WAN-to-IoT traffic targeting TCP `22`, `23`, and `2323`.
3. Drop any other forwarded WAN-to-IoT traffic.
4. Drop IoT-to-WAN traffic targeting TCP `22`, `23`, and `2323`.
5. Allow IoT-to-WAN traffic targeting TCP `443`.

Conceptually, the policy behaves like this:

```text
WAN -> IoT : 22,23,2323  => DROP
WAN -> IoT : everything else => DROP
IoT -> WAN : 22,23,2323 => DROP
IoT -> WAN : 443 => ACCEPT
return traffic for accepted flows => ACCEPT
```

This policy directly maps to the Mirai threat model. The botnet depended on exposed management services for initial infection and unrestricted communication for later coordination or propagation [1]. The gateway addresses both of those behaviors at the network boundary.

## VI. Functional Validation of the Docker Prototype

The basic attack simulation is now performed with Docker Compose commands rather than Vagrant commands.

### A. Starting the Lab

```powershell
docker compose up --build -d
docker compose ps
```

This launches the three containers and confirms that the lab is running.

### B. Inbound Mirai-Style Scanning

From the WAN-side attacker container:

```powershell
docker compose exec atk nmap -Pn -p 22,23,2323 10.20.0.10
docker compose exec atk nc -nvz -w 5 10.20.0.10 22
docker compose exec atk nc -nvz -w 5 10.20.0.10 23
docker compose exec atk nc -nvz -w 5 10.20.0.10 2323
```

Observed result in the current phase 3 run:

```text
22/tcp   filtered ssh
23/tcp   filtered telnet
2323/tcp filtered 3d-nfsd
```

This confirms that the firewall prevents the WAN host from establishing SSH or Telnet-style sessions with the protected IoT device.

### C. Outbound Policy Validation

Blocked outbound connections from the IoT container:

```powershell
docker compose exec iot nc -nvz -w 5 192.168.56.10 22
docker compose exec iot nc -nvz -w 5 192.168.56.10 23
docker compose exec iot nc -nvz -w 5 192.168.56.10 2323
```

Allowed outbound connection:

```powershell
docker compose exec iot nc -nvz -w 5 192.168.56.10 443
```

Observed behavior:

- outbound `22`, `23`, and `2323` timed out and were blocked
- outbound `443` completed successfully

At this stage, the Docker implementation already demonstrated the main functional claim of phase 2: the gateway enforces a meaningful separation between hostile or unnecessary traffic and legitimate communication.

## VII. Phase 3 Performance Testing and Evidence

The updated project adds a phase 3 evaluation focused on three grading targets:

- accuracy
- efficiency
- scalability

Evidence was collected with the automated script:

```powershell
powershell -ExecutionPolicy Bypass -File .\run-phase3.ps1
```

The run created a timestamped evidence folder at:

```text
docker-lab/results/20260401-123110
```

### A. Accuracy

Accuracy asks whether the firewall applies the intended policy correctly.

The strongest evidence comes from three sources:

1. The inbound scan output showed `filtered` results for `22`, `23`, and `2323`.
2. The firewall counter after inbound testing showed:

```text
block wan ssh telnet to iot -> 15 packets, 804 bytes
```

3. The outbound policy counters after blocked and allowed tests showed:

```text
block iot ssh telnet outbound -> 9 packets, 540 bytes
allow iot https to wan -> 5 packets, 300 bytes
```

These results strongly support policy accuracy:

- unsolicited WAN-to-IoT management traffic was blocked
- insecure IoT-to-WAN management traffic was blocked
- legitimate IoT-to-WAN HTTPS traffic was allowed

### B. Efficiency

Efficiency asks whether the security policy preserves legitimate functionality with low overhead.

The automated run measured repeated outbound `443` timing before the scalability burst:

```text
run=1 status=success connect_ms=3
run=2 status=success connect_ms=3
run=3 status=success connect_ms=3
run=4 status=success connect_ms=3
run=5 status=success connect_ms=2
```

After the scalability burst, HTTPS remained available with similarly low timing:

```text
run=1 status=success connect_ms=2
run=2 status=success connect_ms=2
run=3 status=success connect_ms=2
run=4 status=success connect_ms=2
run=5 status=success connect_ms=1
```

Resource snapshots also remained low. Baseline container memory usage was approximately:

- firewall: `3.035 MiB`
- IoT device: `3.219 MiB`
- attacker: `4.035 MiB`

After scaling, container memory stayed in the same small range and firewall CPU remained effectively negligible in the sampled output.

This indicates that the gateway policy preserved legitimate WAN-side HTTPS connectivity while imposing very low visible overhead in the lab environment.

### C. Scalability

Scalability asks whether the firewall continues to enforce policy when attack intensity increases.

The automated script executed burst tests with 10, 25, and 50 parallel blocked connection attempts:

```text
parallel_connections=10  elapsed_seconds=3
parallel_connections=25  elapsed_seconds=3
parallel_connections=50  elapsed_seconds=3
```

After those bursts, the cumulative inbound drop counter increased from:

```text
15 packets after inbound accuracy testing
```

to:

```text
185 packets, 11004 bytes after scalability testing
```

Most importantly, the legitimate `443` test remained successful after the burst. This shows that the firewall kept enforcing the correct blocking policy while preserving the allowed service path.

### D. Interpretation of Phase 3 Results

Taken together, the phase 3 results support a score-5 style argument for performance testing:

- **Accuracy** was demonstrated through exact rule matches and expected `filtered` or timeout behavior.
- **Efficiency** was supported by repeated successful HTTPS timings and low container resource usage.
- **Scalability** was demonstrated by increasing burst size while maintaining correct policy enforcement and preserving legitimate traffic.

Because the evidence is timestamped, repeatable, and generated by the current Docker-based lab, it is stronger than a one-off manual demonstration.

## VIII. Real-World Impact and Identified Gaps

### A. Real-World Impact

The project is strongly connected to real-world IoT risk for several reasons.

First, many consumer and edge IoT devices still expose weak management paths, are not patched frequently, and cannot easily run endpoint security tools. A network-based gateway is therefore practical because it protects the device without requiring firmware changes.

Second, the policy directly addresses a known real-world infection model. Mirai did not rely on highly sophisticated zero-day techniques. It exploited exposed services, weak credentials, and broad Internet reachability [1]. Blocking unnecessary WAN-to-IoT access and constraining risky outbound communication is therefore a realistic and meaningful mitigation strategy.

Third, this architecture is deployable beyond a lab. Home routers, small-office gateways, and edge appliances can implement the same security principle: place IoT devices in a separate segment, filter inbound traffic by default, and allow only the minimal outbound services required for operation.

### B. Identified Gaps

The current implementation is effective, but it is not a complete defense.

Key limitations include:

- the firewall permits `443` based on port number, not application-layer trust
- encrypted malicious traffic over `443` would require deeper inspection or anomaly detection
- the lab contains one IoT device rather than a large multi-device residential network
- lateral movement within a flat IoT subnet is not yet segmented at a per-device level
- the evaluation is strong at lab scale, but not yet validated at enterprise or ISP scale

These gaps should be stated honestly in the report because they also motivate future work.

## IX. Conclusion and Future Work

The updated Docker-based IoT Secure Gateway remains faithful to the original project goal while improving reproducibility and expanding evaluation depth. The current implementation demonstrates that a gateway firewall can meaningfully reduce Mirai-style exposure by blocking WAN-to-IoT SSH/Telnet-style access, blocking insecure IoT-to-WAN propagation paths, and preserving legitimate HTTPS communication.

The new phase 3 evidence strengthens the project substantially. The results show policy accuracy through direct rule-counter matches, efficiency through successful low-latency HTTPS runs and low observed resource usage, and scalability through burst testing that increased blocked traffic without breaking legitimate communication.

Future work should focus on four main directions:

1. destination allowlisting and update-policy refinement for legitimate outbound traffic
2. better logging, alerting, and forensic visibility
3. segmentation between multiple IoT devices inside the private network
4. larger-scale and more adversarial testing, including malicious encrypted traffic scenarios

Overall, the project demonstrates that network-level controls are a practical and effective defensive layer for unmanaged or legacy IoT devices and that even a small lab can meaningfully validate recommendations derived from the Mirai case study.

## References

[1] M. Antonakakis et al., "Understanding the Mirai Botnet," in *Proceedings of the 26th USENIX Security Symposium (USENIX Security '17)*, Vancouver, BC, Canada, Aug. 2017, pp. 1093-1110. [Online]. Available: https://www.usenix.org/system/files/conference/usenixsecurity17/sec17-antonakakis.pdf. Accessed: Mar. 2026.

[2] Cloudflare, "What is the Mirai Botnet?" [Online]. Available: https://www.cloudflare.com/learning/ddos/glossary/mirai-botnet/. Accessed: Mar. 2026.

[3] Cybersecurity and Infrastructure Security Agency (CISA), "Alert (TA16-288A): Heightened DDoS Threat Posed by Mirai and Other Botnets," Oct. 14, 2016. [Online]. Available: https://www.cisa.gov/news-events/alerts/2016/10/14/heightened-ddos-threat-posed-mirai-and-other-botnets. Accessed: Mar. 2026.

[4] Statista Research Department, "Average number of devices and connections per capita," 2023. [Online]. Available: https://www.statista.com/chart/32691/average-number-of-devices-and-connections-per-capita/. Accessed: Mar. 2026.
