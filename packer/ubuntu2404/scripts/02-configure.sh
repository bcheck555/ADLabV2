#!/bin/bash
# Packer provisioner: 02-configure.sh (Ubuntu 24.04)
# Baseline hardening and Ansible prerequisites.
set -euo pipefail

echo '=== 02-configure: Starting ==='

# Ensure python3 is available (Ansible control requirement)
sudo apt-get install -y -qq python3 python3-pip openssh-server

# Harden SSH — align with what Ansible will expect
sudo tee /etc/ssh/sshd_config.d/99-lab.conf > /dev/null <<'EOF'
PasswordAuthentication yes
PubkeyAuthentication yes
PermitRootLogin no
EOF
sudo systemctl restart ssh

# Disable automatic unattended-upgrades (prevent disruption during lab setup)
sudo systemctl disable --now unattended-upgrades || true
sudo apt-get remove -y unattended-upgrades || true

# Set timezone to UTC
sudo timedatectl set-timezone UTC

# Clean apt cache to reduce image size
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Zero free space for better VHDX compression
# (Run last — this can take a while)
sudo dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
sudo rm -f /EMPTY
sync

echo '=== 02-configure: Complete ==='
