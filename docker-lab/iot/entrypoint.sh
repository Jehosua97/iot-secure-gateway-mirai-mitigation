#!/bin/bash
set -euo pipefail

DEVICE_IP="${DEVICE_IP:-10.20.0.10}"
FIREWALL_IP="${FIREWALL_IP:-10.20.0.1}"

DEVICE_IF="$(ip -o -4 addr show | awk -v target="$DEVICE_IP" '$4 ~ ("^" target "/") {print $2; exit}')"

if [[ -z "${DEVICE_IF}" ]]; then
  echo "Unable to determine IoT interface from container IP." >&2
  ip -o -4 addr show >&2
  exit 1
fi

ip route replace default via "${FIREWALL_IP}" dev "${DEVICE_IF}"

mkdir -p /results
ip route >/results/iot-routes-startup.txt

echo "IoT container ready."
echo "Test: curl https://example.com"

exec "$@"
