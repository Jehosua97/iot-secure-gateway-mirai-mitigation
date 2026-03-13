#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

IOT_ADDR="10.20.0.10/24"
GATEWAY_IP="10.20.0.1"

apt-get update -y
apt-get install -y curl dnsutils iproute2 netcat-traditional

IOT_IF="$(ip -4 -o addr show | awk '$4 == "'"${IOT_ADDR}"'" {print $2; exit}')"

if [[ -z "${IOT_IF}" ]]; then
  echo "Unable to detect IoT interface." >&2
  ip -4 -o addr show >&2
  exit 1
fi

install -d /etc/systemd/resolved.conf.d
cat <<'EOF' > /etc/systemd/resolved.conf.d/10-phase3.conf
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=9.9.9.9 8.8.4.4
EOF

systemctl restart systemd-resolved || true

ip route replace default via "${GATEWAY_IP}" dev "${IOT_IF}"

echo "IoT VM ready."
ip route show default
