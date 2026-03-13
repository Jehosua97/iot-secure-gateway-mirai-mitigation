#!/usr/bin/env bash
set -euo pipefail

echo "== hostname =="
hostname
echo

echo "== interfaces =="
ip -br address
echo

echo "== routes =="
ip route
echo

echo "== ip_forward =="
cat /proc/sys/net/ipv4/ip_forward
echo

echo "== nftables =="
nft list ruleset
echo

echo "== kernel log tail =="
journalctl -k -n 50 --no-pager || true
