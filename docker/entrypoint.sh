#!/bin/bash
set -e

# ── Validate required env vars ──────────────────────────────────────────────
if [ -z "$TRUNK_USER" ] || [ -z "$TRUNK_PASS" ] || [ -z "$TRUNK_HOST" ]; then
    echo "============================================================"
    echo "  ERROR: TRUNK_USER, TRUNK_PASS, and TRUNK_HOST must be set."
    echo ""
    echo "  Example (IAX2):"
    echo "    docker run --privileged -v /dev/bus/usb:/dev/bus/usb \\"
    echo "      -e TRUNK_PROTO=iax \\"
    echo "      -e TRUNK_USER=myuser -e TRUNK_PASS=mypass \\"
    echo "      -e TRUNK_HOST=pbx.example.com \\"
    echo "      asterisk-chan-dongle"
    echo ""
    echo "  Example (SIP):"
    echo "    docker run --privileged -v /dev/bus/usb:/dev/bus/usb \\"
    echo "      -e TRUNK_PROTO=sip \\"
    echo "      -e TRUNK_USER=myuser -e TRUNK_PASS=mypass \\"
    echo "      -e TRUNK_HOST=pbx.example.com \\"
    echo "      asterisk-chan-dongle"
    echo ""
    echo "  Supported protocols: iax, sip, pjsip"
    echo "============================================================"
    exit 1
fi

# ── Set defaults based on protocol ──────────────────────────────────────────
TRUNK_PROTO="${TRUNK_PROTO:-iax}"
TRUNK_PROTO=$(echo "$TRUNK_PROTO" | tr '[:upper:]' '[:lower:]')

case "$TRUNK_PROTO" in
    iax|iax2)
        TRUNK_PROTO="iax"
        TRUNK_PORT="${TRUNK_PORT:-4569}"
        TRUNK_DIAL="IAX2/iax-trunk"
        ;;
    sip|chan_sip)
        TRUNK_PROTO="sip"
        TRUNK_PORT="${TRUNK_PORT:-5060}"
        TRUNK_DIAL="SIP/sip-trunk"
        ;;
    pjsip|chan_pjsip)
        TRUNK_PROTO="pjsip"
        TRUNK_PORT="${TRUNK_PORT:-5060}"
        TRUNK_DIAL="PJSIP/pjsip-trunk"
        ;;
    *)
        echo "ERROR: Unknown TRUNK_PROTO='$TRUNK_PROTO'. Use: iax, sip, or pjsip"
        exit 1
        ;;
esac

# ── Generate TLS certificates if not mounted ────────────────────────────────
TLS_DIR="/etc/asterisk/tls"
if [ ! -f "$TLS_DIR/asterisk.pem" ]; then
    echo ">> No TLS certificate found, generating self-signed cert..."
    openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/CN=asterisk-dongle/O=chan-dongle" \
        -keyout "$TLS_DIR/asterisk.key" \
        -out "$TLS_DIR/asterisk.crt" \
        2>/dev/null
    cat "$TLS_DIR/asterisk.key" "$TLS_DIR/asterisk.crt" > "$TLS_DIR/asterisk.pem"
    cp "$TLS_DIR/asterisk.crt" "$TLS_DIR/ca.crt"
    chmod 600 "$TLS_DIR/asterisk.key" "$TLS_DIR/asterisk.pem"
    echo "   Self-signed TLS certificate generated in $TLS_DIR"
    echo "   Mount your own certs to $TLS_DIR/ to use real certificates"
else
    echo ">> Using existing TLS certificate: $TLS_DIR/asterisk.pem"
fi

# ── Generate Asterisk configs from templates ────────────────────────────────
echo ">> Generating Asterisk configs..."
echo "   Protocol : $TRUNK_PROTO"
echo "   Host     : $TRUNK_HOST:$TRUNK_PORT"
echo "   User     : $TRUNK_USER"
echo "   Context  : $DONGLE_CONTEXT"

export TRUNK_USER TRUNK_PASS TRUNK_HOST TRUNK_PORT TRUNK_PROTO TRUNK_DIAL DONGLE_CONTEXT

# Only substitute our own env vars — Asterisk dialplan uses ${EXTEN}, ${CALLERID(...)}, etc.
# that must NOT be touched by envsubst.
ENVSUBST_VARS='$TRUNK_USER $TRUNK_PASS $TRUNK_HOST $TRUNK_PORT $TRUNK_PROTO $TRUNK_DIAL $DONGLE_CONTEXT'

# Always generate dongle.conf and extensions.conf
envsubst "$ENVSUBST_VARS" < /etc/asterisk/templates/dongle.conf.template     > /etc/asterisk/dongle.conf
envsubst "$ENVSUBST_VARS" < /etc/asterisk/templates/extensions.conf.template  > /etc/asterisk/extensions.conf

# Generate the protocol-specific trunk config
case "$TRUNK_PROTO" in
    iax)
        envsubst "$ENVSUBST_VARS" < /etc/asterisk/templates/iax.conf.template > /etc/asterisk/iax.conf
        echo "   Config   : iax.conf generated"
        ;;
    sip)
        envsubst "$ENVSUBST_VARS" < /etc/asterisk/templates/sip.conf.template > /etc/asterisk/sip.conf
        echo "   Config   : sip.conf generated (chan_sip)"
        ;;
    pjsip)
        envsubst "$ENVSUBST_VARS" < /etc/asterisk/templates/pjsip.conf.template > /etc/asterisk/pjsip.conf
        echo "   Config   : pjsip.conf generated (chan_pjsip)"
        ;;
esac

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
