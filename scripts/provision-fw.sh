#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

IOT_ADDR="10.20.0.1/24"
EXT_ADDR="192.168.56.2/24"
IOT_NET="10.20.0.0/24"

apt-get update -y
apt-get install -y nftables iproute2 tcpdump curl

WAN_IF="$(ip route show default | awk '/default/ {print $5; exit}')"
IOT_IF="$(ip -4 -o addr show | awk '$4 == "'"${IOT_ADDR}"'" {print $2; exit}')"
EXT_IF="$(ip -4 -o addr show | awk '$4 == "'"${EXT_ADDR}"'" {print $2; exit}')"

if [[ -z "${WAN_IF}" || -z "${IOT_IF}" || -z "${EXT_IF}" ]]; then
  echo "Unable to detect one or more firewall interfaces." >&2
  ip -4 -o addr show >&2
  ip route >&2
  exit 1
fi

cat <<'EOF' > /etc/sysctl.d/99-ipforward.conf
net.ipv4.ip_forward=1
EOF

sysctl --system >/dev/null

cat <<EOF > /etc/nftables.conf
flush ruleset

define IOT_NET = ${IOT_NET}
define WAN_IF = "${WAN_IF}"
define IOT_IF = "${IOT_IF}"
define EXT_IF = "${EXT_IF}"

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;

    iifname "lo" accept
    ct state established,related accept
    meta l4proto icmp counter accept comment "icmp_allow"

    iifname \$WAN_IF udp sport 67 udp dport 68 counter accept comment "wan_dhcp_allow"
    iifname \$WAN_IF tcp dport 22 counter accept comment "wan_ssh_allow"
    iifname \$EXT_IF tcp dport 22 counter accept comment "ext_ssh_allow"
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;

    ct state established,related counter accept comment "forward_established"

    iifname \$EXT_IF oifname \$IOT_IF log prefix "WAN_TO_IOT_DROP " flags all counter drop comment "wan_to_iot_drop"

    iifname \$IOT_IF oifname \$WAN_IF udp dport { 53, 123 } counter accept comment "iot_udp_allow"
    iifname \$IOT_IF oifname \$WAN_IF tcp dport 53 counter accept comment "iot_dns_tcp_allow"
    iifname \$IOT_IF oifname \$WAN_IF tcp dport 443 counter accept comment "iot_https_allow"

    iifname \$IOT_IF oifname \$WAN_IF tcp dport 80 log prefix "IOT_HTTP_DROP " flags all counter drop comment "iot_http_drop"
    iifname \$IOT_IF oifname \$WAN_IF log prefix "IOT_EGRESS_DROP " flags all counter drop comment "iot_egress_drop"
  }
}

table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    oifname \$WAN_IF ip saddr \$IOT_NET counter masquerade comment "iot_nat"
  }
}
EOF

systemctl enable nftables
systemctl restart nftables

nft list ruleset
