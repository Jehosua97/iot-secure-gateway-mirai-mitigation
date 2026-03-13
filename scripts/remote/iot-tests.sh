#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"

case "${MODE}" in
  route)
    ip route show default
    ;;
  dns)
    dig +time=3 +tries=1 @1.1.1.1 example.com A +short | sed '/^$/d' | head -n 1
    ;;
  https)
    curl -sS -o /dev/null \
      --connect-timeout 8 \
      --max-time 20 \
      -w "url=%{url_effective}\nhttp_code=%{http_code}\nremote_ip=%{remote_ip}\nnum_connects=%{num_connects}\ntime_namelookup=%{time_namelookup}\ntime_connect=%{time_connect}\ntime_appconnect=%{time_appconnect}\ntime_starttransfer=%{time_starttransfer}\ntime_total=%{time_total}\n" \
      https://example.com/
    ;;
  http-block)
    if curl -sS -I --connect-timeout 5 --max-time 10 http://example.com/; then
      echo "Unexpected HTTP success."
      exit 1
    fi
    echo "HTTP egress blocked as expected."
    ;;
  *)
    echo "Usage: $0 {route|dns|https|http-block}" >&2
    exit 64
    ;;
esac
