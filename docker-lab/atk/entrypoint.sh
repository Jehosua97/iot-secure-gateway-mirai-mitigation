#!/bin/bash
set -euo pipefail

ATTACKER_IP="${ATTACKER_IP:-192.168.56.10}"
FIREWALL_WAN_IP="${FIREWALL_WAN_IP:-192.168.56.2}"
IOT_NET="${IOT_NET:-10.20.0.0/24}"

WAN_IF="$(ip -o -4 addr show | awk -v target="$ATTACKER_IP" '$4 ~ ("^" target "/") {print $2; exit}')"

if [[ -z "${WAN_IF}" ]]; then
  echo "Unable to determine attacker interface from container IP." >&2
  ip -o -4 addr show >&2
  exit 1
fi

ip route replace "${IOT_NET}" via "${FIREWALL_WAN_IP}" dev "${WAN_IF}"

mkdir -p /results
ip route >/results/atk-routes-startup.txt

echo "Attacker container ready."
echo "Test: nmap -p 22,23,2323 10.20.0.10"

exec "$@"
