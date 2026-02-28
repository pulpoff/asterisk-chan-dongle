#!/bin/bash
# Install Docker CE on Armbian (Debian-based)
# Usage: sudo bash install-docker.sh

set -e

echo "=== Removing old Docker packages (if any) ==="
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

echo "=== Installing prerequisites ==="
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

echo "=== Adding Docker GPG key ==="
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "=== Adding Docker repository ==="
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "=== Installing Docker CE ==="
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

echo "=== Docker installed successfully ==="
docker --version
docker compose version
