#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

ATK_ADDR="192.168.56.10/24"
GATEWAY_IP="192.168.56.2"
IOT_NET="10.20.0.0/24"

apt-get update -y
apt-get install -y iproute2 netcat-traditional nmap

ATK_IF="$(ip -4 -o addr show | awk '$4 == "'"${ATK_ADDR}"'" {print $2; exit}')"

if [[ -z "${ATK_IF}" ]]; then
  echo "Unable to detect attacker interface." >&2
  ip -4 -o addr show >&2
  exit 1
fi

ip route replace "${IOT_NET}" via "${GATEWAY_IP}" dev "${ATK_IF}"

echo "Attacker VM ready."
ip route get 10.20.0.10
