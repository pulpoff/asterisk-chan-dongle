#!/bin/bash
###############################################################################
# setup.sh — One-command installer for Asterisk + chan_dongle GSM/IAX2 Gateway
#
# Run on a fresh Raspberry Pi / Orange Pi / any Linux box:
#   curl -sSL https://raw.githubusercontent.com/pulpoff/asterisk-chan-dongle/master/setup.sh | sudo bash
#
# Or download and run:
#   wget -O setup.sh https://raw.githubusercontent.com/pulpoff/asterisk-chan-dongle/master/setup.sh
#   sudo bash setup.sh
###############################################################################
set -e

DOCKER_IMAGE="ghcr.io/pulpoff/asterisk-chan-dongle:latest"
INSTALL_DIR="/opt/asterisk-dongle"
SERVICE_NAME="asterisk-dongle"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}>> $1${NC}"; }
ok()    { echo -e "${GREEN}>> $1${NC}"; }
warn()  { echo -e "${YELLOW}>> $1${NC}"; }
err()   { echo -e "${RED}>> ERROR: $1${NC}"; exit 1; }

# ── Must be root ────────────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    err "Please run as root: sudo bash setup.sh"
fi

echo ""
echo "============================================================"
echo "  Asterisk + chan_dongle  —  GSM / IAX2 Gateway Setup"
echo "============================================================"
echo ""
echo "  This script will:"
echo "    1. Install Docker (if not present)"
echo "    2. Pull the multi-arch Docker image"
echo "    3. Configure your IAX2 connection"
echo "    4. Set up auto-start on boot"
echo ""

# ── Collect IAX2 credentials ───────────────────────────────────────────────
read -rp "IAX2 Host (e.g. pbx.example.com): " IAX_HOST
if [ -z "$IAX_HOST" ]; then
    err "IAX2 host is required."
fi

read -rp "IAX2 Username: " IAX_USER
if [ -z "$IAX_USER" ]; then
    err "IAX2 username is required."
fi

read -rsp "IAX2 Password: " IAX_PASS
echo ""
if [ -z "$IAX_PASS" ]; then
    err "IAX2 password is required."
fi

read -rp "IAX2 Port [4569]: " IAX_PORT
IAX_PORT=${IAX_PORT:-4569}

echo ""

# ── Install Docker if needed ───────────────────────────────────────────────
if command -v docker &>/dev/null; then
    ok "Docker is already installed: $(docker --version)"
else
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    ok "Docker installed successfully."
fi

# ── Pull the image ─────────────────────────────────────────────────────────
info "Pulling Docker image: $DOCKER_IMAGE"
info "(This downloads the correct image for your CPU architecture automatically)"
docker pull "$DOCKER_IMAGE"
ok "Image pulled successfully."

# ── Create config directory ────────────────────────────────────────────────
info "Setting up configuration in $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

cat > "$INSTALL_DIR/.env" <<EOF
IAX_USER=$IAX_USER
IAX_PASS=$IAX_PASS
IAX_HOST=$IAX_HOST
IAX_PORT=$IAX_PORT
DONGLE_CONTEXT=from-dongle
EOF

chmod 600 "$INSTALL_DIR/.env"

# ── Create systemd service ─────────────────────────────────────────────────
info "Creating systemd service for auto-start on boot..."

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Asterisk chan_dongle GSM/IAX2 Gateway
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=10
EnvironmentFile=$INSTALL_DIR/.env

ExecStartPre=-/usr/bin/docker rm -f $SERVICE_NAME
ExecStart=/usr/bin/docker run --rm \\
    --name $SERVICE_NAME \\
    --privileged \\
    --network host \\
    -v /dev/bus/usb:/dev/bus/usb \\
    -e IAX_USER=\${IAX_USER} \\
    -e IAX_PASS=\${IAX_PASS} \\
    -e IAX_HOST=\${IAX_HOST} \\
    -e IAX_PORT=\${IAX_PORT} \\
    -e DONGLE_CONTEXT=\${DONGLE_CONTEXT} \\
    $DOCKER_IMAGE

ExecStop=/usr/bin/docker stop $SERVICE_NAME

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service

# ── Start the service ──────────────────────────────────────────────────────
info "Starting the gateway..."
systemctl start ${SERVICE_NAME}.service

echo ""
echo "============================================================"
ok "  Setup complete!"
echo ""
echo "  Your GSM/IAX2 gateway is now running and will"
echo "  auto-start on boot."
echo ""
echo "  Useful commands:"
echo "    systemctl status $SERVICE_NAME    # Check status"
echo "    journalctl -u $SERVICE_NAME -f    # View live logs"
echo "    systemctl restart $SERVICE_NAME   # Restart"
echo "    systemctl stop $SERVICE_NAME      # Stop"
echo ""
echo "  Config stored in: $INSTALL_DIR/.env"
echo "  To change credentials, edit that file and restart."
echo ""
echo "  Make sure your Huawei USB dongle is plugged in!"
echo "============================================================"
