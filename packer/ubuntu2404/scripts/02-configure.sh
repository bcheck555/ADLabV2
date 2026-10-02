#!/bin/bash
# Packer provisioner: 02-configure.sh (Ubuntu 24.04)
# Baseline hardening and final image prep.
# NOTE: offline build - no apt operations. python3 / openssh-server ship on the live-server ISO.
set -euo pipefail

echo '=== 02-configure: Starting ==='

# Harden SSH - align with what Ansible will expect
sudo tee /etc/ssh/sshd_config.d/99-lab.conf > /dev/null <<'EOF'
PasswordAuthentication yes
PubkeyAuthentication yes
PermitRootLogin no
EOF
sudo systemctl restart ssh

# Disable automatic unattended-upgrades (would fail on isolated net + disrupt lab setup)
sudo systemctl disable --now unattended-upgrades.service 2>/dev/null || true
sudo systemctl mask unattended-upgrades.service 2>/dev/null || true

# Set timezone to UTC
sudo timedatectl set-timezone UTC

# Clean apt cache to reduce image size
sudo apt-get clean || true
sudo rm -rf /var/lib/apt/lists/*

# Zero free space for better VHDX compression (takes a while)
sudo dd if=/dev/zero of=/EMPTY bs=1M 2>/dev/null || true
sudo rm -f /EMPTY
sync

echo '=== 02-configure: Complete ==='
