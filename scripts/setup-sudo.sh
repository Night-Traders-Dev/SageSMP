#!/bin/bash
# SageSMP: Set up passwordless sudo on all cluster devices
# Run this from the host machine (or OrangePi) to configure NOPASSWD sudo.
# Usage: ./scripts/setup-sudo.sh [password]
# If no password is provided, reads from SUDO_PASS env var or prompts.

set -e

PASS="${1:-${SUDO_PASS}}"
if [ -z "$PASS" ]; then
  read -rsp "Enter sudo password for all devices: " PASS
  echo
fi

ORANGE_USER="orangepi"
ORANGE_HOST="192.168.254.44"

echo "=== Setting up passwordless sudo on OrangePi ==="
ssh "$ORANGE_USER@$ORANGE_HOST" "echo '$PASS' | sudo -S sh -c 'echo $ORANGE_USER ALL=\(ALL\) NOPASSWD: ALL > /etc/sudoers.d/sagesmp && chmod 440 /etc/sudoers.d/sagesmp'"

echo ""
echo "=== Setting up passwordless sudo on Pi2 ==="
ssh "$ORANGE_USER@$ORANGE_HOST" "ssh pi2 \"echo '$PASS' | sudo -S sh -c 'echo pi ALL=\(ALL\) NOPASSWD: ALL > /etc/sudoers.d/sagesmp && chmod 440 /etc/sudoers.d/sagesmp'\""

echo ""
echo "=== Setting up passwordless sudo on Pi4 ==="
ssh "$ORANGE_USER@$ORANGE_HOST" "ssh pi4 \"echo '$PASS' | sudo -S sh -c 'echo ubuntu ALL=\(ALL\) NOPASSWD: ALL > /etc/sudoers.d/sagesmp && chmod 440 /etc/sudoers.d/sagesmp'\""

echo ""
echo "=== Verifying passwordless sudo ==="

echo "OrangePi:"
ssh "$ORANGE_USER@$ORANGE_HOST" "sudo whoami"

echo "Pi2:"
ssh "$ORANGE_USER@$ORANGE_HOST" "ssh pi2 'sudo whoami'"

echo "Pi4:"
ssh "$ORANGE_USER@$ORANGE_HOST" "ssh pi4 'sudo whoami'"

echo ""
echo "Done. If all devices show 'root', passwordless sudo is configured."
