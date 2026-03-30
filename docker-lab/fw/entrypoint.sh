#!/bin/bash
set -euo pipefail

IOT_NET="${IOT_NET:-10.20.0.0/24}"
IOT_IP="${IOT_IP:-10.20.0.1}"
WAN_SIM_NET="${WAN_SIM_NET:-192.168.56.0/24}"
WAN_SIM_IP="${WAN_SIM_IP:-192.168.56.2}"

find_interface_by_ip() {
  local target_ip="$1"
  ip -o -4 addr show | awk -v target="$target_ip" '$4 ~ ("^" target "/") {print $2; exit}'
}

IOT_IF="$(find_interface_by_ip "$IOT_IP")"
EXT_IF="$(find_interface_by_ip "$WAN_SIM_IP")"

if [[ -z "${IOT_IF}" || -z "${EXT_IF}" ]]; then
  echo "Unable to determine firewall interfaces from container IPs." >&2
  ip -o -4 addr show >&2
  exit 1
fi

cat >/etc/nftables.conf <<EOF
flush ruleset

define IOT_NET = ${IOT_NET}
define WAN_SIM_NET = ${WAN_SIM_NET}

define IOT_IF = "${IOT_IF}"
define EXT_IF = "${EXT_IF}"

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    iifname "lo" counter accept comment "allow loopback"
    ct state established,related counter accept comment "allow established input"

    iifname \$IOT_IF icmp type echo-request counter accept comment "allow iot ping"
    iifname \$EXT_IF icmp type echo-request counter accept comment "allow wan ping"
    iifname \$EXT_IF ip saddr \$WAN_SIM_NET tcp dport 22 counter drop comment "block ssh to firewall from wan lab"
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;

    ct state established,related counter accept comment "allow established forward"

    iifname \$EXT_IF oifname \$IOT_IF tcp dport {22,23,2323} counter drop comment "block wan ssh telnet to iot"
    iifname \$EXT_IF oifname \$IOT_IF counter drop comment "block other wan to iot"

    iifname \$IOT_IF oifname \$EXT_IF tcp dport {22,23,2323} counter drop comment "block iot ssh telnet outbound"
    iifname \$IOT_IF oifname \$EXT_IF tcp dport 443 counter accept comment "allow iot https to wan"
  }
}
EOF

sysctl -w net.ipv4.ip_forward=1 >/dev/null
nft -f /etc/nftables.conf

mkdir -p /results

ip -br addr >/results/fw-ip-addr-startup.txt
ip route >/results/fw-routes-startup.txt
cat /proc/sys/net/ipv4/ip_forward >/results/fw-ip-forward-startup.txt
nft list ruleset >/results/fw-ruleset-startup.txt
nft list chain inet filter input >/results/fw-input-chain-startup.txt
nft list chain inet filter forward >/results/fw-forward-chain-startup.txt
ss -lntp >/results/fw-listeners-startup.txt

echo "Firewall container ready."
echo "IoT interface: ${IOT_IF}"
echo "WAN interface: ${EXT_IF}"

exec "$@"
