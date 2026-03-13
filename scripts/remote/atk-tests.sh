#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
TARGET="${2:-10.20.0.10}"
ATTEMPTS="${3:-10}"

case "${MODE}" in
  route)
    ip route get "${TARGET}"
    ;;
  scan)
    nmap -Pn -n -p 23,2323 --max-retries 1 --host-timeout 20s "${TARGET}"
    ;;
  telnet-burst)
    successes=0
    for attempt in $(seq 1 "${ATTEMPTS}"); do
      echo "Attempt ${attempt}: ${TARGET}:23"
      if nc -vz -w 2 "${TARGET}" 23; then
        successes=$((successes + 1))
      else
        echo "blocked"
      fi
    done
    echo "SUCCESSFUL_CONNECTIONS=${successes}"
    if [[ "${successes}" -eq 0 ]]; then
      exit 0
    fi
    exit 1
    ;;
  *)
    echo "Usage: $0 {route|scan|telnet-burst} [target] [attempts]" >&2
    exit 64
    ;;
esac
