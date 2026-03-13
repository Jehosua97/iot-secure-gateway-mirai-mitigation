#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--json" ]]; then
  nft -j list ruleset
  exit 0
fi

echo "== inet filter forward =="
nft list chain inet filter forward
echo

echo "== ip nat postrouting =="
nft list chain ip nat postrouting
