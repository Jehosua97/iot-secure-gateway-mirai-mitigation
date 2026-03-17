Perfect — here are the **same 10 test steps**, but written in **clear technical English with short descriptions** (good for documentation, GitHub, or a lab report).

---

# IoT Secure Gateway – Attack Simulation Test Commands

## 1. Start the Virtual Lab Environment

Launch all virtual machines defined in the Vagrantfile.

```bash
vagrant up
```

This command initializes and boots the **firewall (fw)**, **IoT device (iot)**, and **attacker (atk)** virtual machines.

---

## 2. Verify VM Status

Check that all virtual machines are running correctly.

```bash
vagrant status
```

Expected output:

```
fw   running
iot  running
atk  running
```

This confirms that the full lab infrastructure is operational.

---

## 3. Connect to the Firewall VM

Open an SSH session to the firewall gateway machine.

```bash
vagrant ssh fw
```

The firewall acts as the **routing and filtering boundary** between the WAN and the IoT network.

Exit the session when finished:

```bash
exit
```

---

## 4. Connect to the IoT Device VM

Access the simulated IoT device.

```bash
vagrant ssh iot
```

Verify its network configuration:

```bash
ip a
```

Expected IP address:

```
10.20.0.10
```

Exit the machine:

```bash
exit
```

---

## 5. Connect to the Attacker Machine

Open an SSH session to the attacker VM.

```bash
vagrant ssh atk
```

Verify its network address:

```bash
ip a
```

Expected address:

```
192.168.56.10
```

This machine simulates an **external host attempting to attack the IoT device**.

---

## 6. Perform Mirai-Style Port Scanning

From the attacker machine, simulate Mirai-style scanning targeting common IoT service ports.

```bash
nmap -p 22,23,2323 10.20.0.10
```

These ports correspond to:

* 22 → SSH
* 23 → Telnet
* 2323 → Alternate Telnet port

Expected result:

```
PORT     STATE    SERVICE
22/tcp   filtered ssh
23/tcp   filtered telnet
2323/tcp filtered telnet-alt
```

This confirms that the **firewall blocks inbound scanning attempts**.

---

## 7. Attempt Direct Service Access

Attempt to directly connect to services on the IoT device.

```bash
nc -vz 10.20.0.10 23
```

and

```bash
nc -vz 10.20.0.10 22
```

Expected behavior:

```
Connection timed out
```

This demonstrates that **unauthorized inbound connections are blocked**.

---

## 8. Monitor Network Traffic on the Firewall

Connect to the firewall VM and observe packets in real time.

```bash
sudo tcpdump -i any host 10.20.0.10
```

While this command is running, repeat the attack scan from the attacker VM.

This allows visualization of **incoming attack traffic being filtered by the firewall**.

---

## 9. Inspect Firewall Rules

Verify that the firewall configuration is active.

```bash
sudo nft list ruleset
```

Example output:

```
chain forward {
 type filter hook forward priority 0;
 policy drop;
}
```

This confirms that the gateway is enforcing a **default-deny forwarding policy**.

---

## 10. Test Outbound IoT Connectivity

From the IoT device, test outbound Internet access.

```bash
curl https://example.com
```

Expected result: successful HTTP response.

Then test a blocked outbound connection:

```bash
nc -vz 1.1.1.1 23
```

Expected result:

```
Connection blocked
```

This verifies that the firewall **restricts outbound traffic while still allowing legitimate services**.

---

If you want, I can also give you a **very strong GitHub README section** called:

### `Attack Simulation Procedure`

that would make this project look **very professional in your cybersecurity portfolio**.
