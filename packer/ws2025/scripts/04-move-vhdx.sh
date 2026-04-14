#!/bin/bash
# Post-processor: move VHDX from build output to base-vhds
# Called by Packer — receives paths via environment variables

set -e

OUTPUT_DIR="${PACKER_OUTPUT_DIR:-D:/CODE/ADLabV2/packer/ws2025/output}"
DEST_PATH="${PACKER_DEST_PATH:-D:/CODE/ADLabV2/base-vhds/ws2025-base.vhdx}"

# Normalize paths for PowerShell (convert backslashes to forward slashes)
OUTPUT_DIR=$(echo "$OUTPUT_DIR" | sed 's|\\|/|g')
DEST_PATH=$(echo "$DEST_PATH" | sed 's|\\|/|g')

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PS_SCRIPT="$SCRIPT_DIR/04-move-vhdx.ps1"

# Convert to Windows path for powershell.exe
PS_SCRIPT_WIN=$(cygpath -w "$PS_SCRIPT" 2>/dev/null || echo "$PS_SCRIPT")

echo "Moving VHDX from $OUTPUT_DIR to $DEST_PATH..."
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "$PS_SCRIPT_WIN" \
  -OutputDir "$OUTPUT_DIR" \
  -DestPath "$DEST_PATH" || exit 1
