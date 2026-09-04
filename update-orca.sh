#!/usr/bin/env bash

set -euo pipefail

# Stop the orca-serve service before updating
systemctl --user stop orca-serve.service

# Check the architecture and set the appropriate pattern for the .deb file
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64) ARCH_PAT='_amd64\.deb$' ;;
    aarch64|arm64) ARCH_PAT='_arm64\.deb$' ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

LATEST_URL=$(curl -fsSL https://api.github.com/repos/stablyai/orca/releases/latest \
  | jq -r --arg pat "${ARCH_PAT}" '.assets[] | select(.name | test($pat)) | .browser_download_url' \
  | head -n1)

# Download to /tmp and install with apt
DEB_PATH=$(mktemp /tmp/orca-XXXXXX.deb)
curl -fsSL "${LATEST_URL}" -o "${DEB_PATH}"
sudo apt-get install -y "${DEB_PATH}"
rm -f "${DEB_PATH}"

# Start the service again
systemctl --user start orca-serve.service

# Verify that it started correctly
systemctl --user status orca-serve.service --no-pager
