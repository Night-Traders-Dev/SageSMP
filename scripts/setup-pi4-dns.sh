#!/bin/bash
# SageSMP: Configure Pi4 DNS to route through OrangePi relay -> Pi-hole
# Run from host: ./scripts/setup-pi4-dns.sh
# Or manually: ssh OrangePi "ssh pi4 'sudo tee /etc/resolv.conf <<< \"nameserver 10.42.0.1\"'"

set -e

echo "[SageSMP] Configuring Pi4 DNS via OrangePi relay..."

ssh OrangePi "ssh pi4 'echo jdy@123 | sudo -S tee /etc/resolv.conf > /dev/null' << 'EOF'
nameserver 10.42.0.1
EOF
"

echo "[SageSMP] Verifying Pi4 DNS resolution..."
ssh OrangePi "ssh pi4 'dig +short google.com @10.42.0.1 2>&1 || nslookup google.com 10.42.0.1 2>&1'"

echo "[SageSMP] Pi4 DNS configured successfully."
echo "  - Pi4 resolves DNS via OrangePi relay (10.42.0.1:53)"
echo "  - OrangePi forwards all queries to Pi-hole (10.42.1.109:53)"
echo "  - Pi-hole handles blocking + logging + packet capture"
