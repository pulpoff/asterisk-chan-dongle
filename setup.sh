#!/bin/bash
###############################################################################
# setup.sh — One-command installer for Asterisk + chan_dongle GSM Gateway
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
echo "  Asterisk + chan_dongle  —  GSM Gateway Setup"
echo "============================================================"
echo ""
echo "  This script will:"
echo "    1. Install Docker (if not present)"
echo "    2. Pull the multi-arch Docker image"
echo "    3. Configure your trunk connection (IAX2, SIP, or PJSIP)"
echo "    4. Set up auto-start on boot"
echo ""

# ── Choose protocol ─────────────────────────────────────────────────────────
echo "  Which trunk protocol do you want to use?"
echo "    1) IAX2     (recommended for NAT, low bandwidth)"
echo "    2) SIP      (chan_sip — classic SIP)"
echo "    3) PJSIP    (chan_pjsip — modern SIP stack)"
echo ""
read -rp "  Choose [1/2/3, default=1]: " PROTO_CHOICE
case "${PROTO_CHOICE:-1}" in
    1) TRUNK_PROTO="iax";   DEFAULT_PORT="4569" ;;
    2) TRUNK_PROTO="sip";   DEFAULT_PORT="5060" ;;
    3) TRUNK_PROTO="pjsip"; DEFAULT_PORT="5060" ;;
    *) err "Invalid choice. Use 1, 2, or 3." ;;
esac
echo ""

# ── Collect credentials ─────────────────────────────────────────────────────
read -rp "PBX Host (e.g. pbx.example.com): " TRUNK_HOST
if [ -z "$TRUNK_HOST" ]; then
    err "PBX host is required."
fi

read -rp "Username: " TRUNK_USER
if [ -z "$TRUNK_USER" ]; then
    err "Username is required."
fi

read -rsp "Password: " TRUNK_PASS
echo ""
if [ -z "$TRUNK_PASS" ]; then
    err "Password is required."
fi

read -rp "Port [$DEFAULT_PORT]: " TRUNK_PORT
TRUNK_PORT=${TRUNK_PORT:-$DEFAULT_PORT}

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
TRUNK_PROTO=$TRUNK_PROTO
TRUNK_USER=$TRUNK_USER
TRUNK_PASS=$TRUNK_PASS
TRUNK_HOST=$TRUNK_HOST
TRUNK_PORT=$TRUNK_PORT
DONGLE_CONTEXT=from-dongle
EOF

chmod 600 "$INSTALL_DIR/.env"

# ── Create systemd service ─────────────────────────────────────────────────
info "Creating systemd service for auto-start on boot..."

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Asterisk chan_dongle GSM Gateway
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
    -e TRUNK_PROTO=\${TRUNK_PROTO} \\
    -e TRUNK_USER=\${TRUNK_USER} \\
    -e TRUNK_PASS=\${TRUNK_PASS} \\
    -e TRUNK_HOST=\${TRUNK_HOST} \\
    -e TRUNK_PORT=\${TRUNK_PORT} \\
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
echo "  Your GSM gateway is now running ($TRUNK_PROTO trunk)"
echo "  and will auto-start on boot."
echo ""
echo "  Useful commands:"
echo "    systemctl status $SERVICE_NAME    # Check status"
echo "    journalctl -u $SERVICE_NAME -f    # View live logs"
echo "    systemctl restart $SERVICE_NAME   # Restart"
echo "    systemctl stop $SERVICE_NAME      # Stop"
echo ""
echo "  Config stored in: $INSTALL_DIR/.env"
echo "  To change settings, edit that file and restart."
echo ""
echo "  Make sure your Huawei USB dongle is plugged in!"
echo "============================================================"
