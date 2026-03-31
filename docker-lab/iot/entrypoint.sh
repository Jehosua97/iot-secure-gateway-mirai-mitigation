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

# Force the IoT container to treat the firewall as its default gateway.
ip route replace default via "${FIREWALL_IP}" dev "${DEVICE_IF}"

mkdir -p /results
ip -br addr >/results/iot-ip-addr-startup.txt
ip route >/results/iot-routes-startup.txt

start_listener() {
  local port="$1"
  local log_file="/results/iot-port-${port}.log"

  nohup socat -d -d TCP-LISTEN:"${port}",reuseaddr,fork EXEC:/bin/cat >>"${log_file}" 2>&1 &
  echo $! >"/run/iot-port-${port}.pid"
}

# Keep deliberately exposed services available so the firewall can prove it is blocking them.
start_listener 22
start_listener 23
start_listener 2323

ss -lntp >/results/iot-listeners-startup.txt

echo "IoT container ready."
echo "Test: nc -vz 192.168.56.10 443"
echo "Listeners: TCP 22, 23, and 2323"

exec "$@"
