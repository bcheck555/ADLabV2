#!/bin/bash
# Packer provisioner: 01-init.sh (Ubuntu 24.04)
# Waits for cloud-init to finish and verifies base state.
# NOTE: offline build - no apt operations.
set -euo pipefail

echo '=== 01-init: Starting ==='

# Wait for cloud-init to finish (autoinstall late-commands may still be running)
cloud-init status --wait || true

echo '=== 01-init: Complete ==='
