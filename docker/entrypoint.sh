#!/bin/bash
set -e

# ── Validate required env vars ──────────────────────────────────────────────
if [ -z "$IAX_USER" ] || [ -z "$IAX_PASS" ] || [ -z "$IAX_HOST" ]; then
    echo "============================================================"
    echo "  ERROR: IAX_USER, IAX_PASS, and IAX_HOST must be set."
    echo ""
    echo "  Example:"
    echo "    docker run --privileged -v /dev/bus/usb:/dev/bus/usb \\"
    echo "      -e IAX_USER=myuser -e IAX_PASS=mypass \\"
    echo "      -e IAX_HOST=pbx.example.com \\"
    echo "      asterisk-chan-dongle"
    echo "============================================================"
    exit 1
fi

# ── Generate Asterisk configs from templates ────────────────────────────────
echo ">> Generating Asterisk configs..."
echo "   IAX Host : $IAX_HOST:$IAX_PORT"
echo "   IAX User : $IAX_USER"
echo "   Context  : $DONGLE_CONTEXT"

export IAX_USER IAX_PASS IAX_HOST IAX_PORT DONGLE_CONTEXT

envsubst < /etc/asterisk/templates/iax.conf.template       > /etc/asterisk/iax.conf
envsubst < /etc/asterisk/templates/extensions.conf.template > /etc/asterisk/extensions.conf
envsubst < /etc/asterisk/templates/dongle.conf.template     > /etc/asterisk/dongle.conf

# ── Detect USB dongles ──────────────────────────────────────────────────────
echo ">> Checking for Huawei USB dongles..."
if command -v lsusb &>/dev/null; then
    HUAWEI_DEVICES=$(lsusb | grep -i huawei || true)
    if [ -n "$HUAWEI_DEVICES" ]; then
        echo "   Found devices:"
        echo "$HUAWEI_DEVICES" | sed 's/^/     /'
    else
        echo "   WARNING: No Huawei USB dongles detected."
        echo "   Make sure to pass --privileged and -v /dev/bus/usb:/dev/bus/usb"
    fi
fi

# ── Switch USB modems to correct mode if needed ─────────────────────────────
if command -v usb_modeswitch &>/dev/null; then
    echo ">> Running usb_modeswitch (if applicable)..."
    usb_modeswitch_dispatcher --verbose 2>/dev/null || true
fi

# ── Fix permissions on tty devices ──────────────────────────────────────────
echo ">> Setting permissions on /dev/ttyUSB* devices..."
for tty in /dev/ttyUSB*; do
    if [ -e "$tty" ]; then
        chmod 666 "$tty" 2>/dev/null || true
        echo "   $tty ready"
    fi
done

# ── Ensure asterisk user can access devices ─────────────────────────────────
chown -R asterisk:asterisk /etc/asterisk/ 2>/dev/null || true
chown -R asterisk:asterisk /var/lib/asterisk/ 2>/dev/null || true
chown -R asterisk:asterisk /var/log/asterisk/ 2>/dev/null || true
chown -R asterisk:asterisk /var/spool/asterisk/ 2>/dev/null || true
chown -R asterisk:asterisk /var/run/asterisk/ 2>/dev/null || true

echo ">> Starting Asterisk..."
exec "$@"
