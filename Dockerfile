###############################################################################
# Multi-arch Dockerfile: Asterisk 20 + chan_dongle
# Builds for: linux/amd64, linux/arm64, linux/arm/v7
#
# Turns any Raspberry Pi / Orange Pi / x86 box with a Huawei USB dongle
# into a GSM <-> IAX2 gateway. Just provide IAX2 credentials and a host.
#
# Usage:
#   docker build -t asterisk-chan-dongle .
#   docker run --rm --privileged -v /dev/bus/usb:/dev/bus/usb \
#     -e IAX_USER=myuser -e IAX_PASS=mypass -e IAX_HOST=pbx.example.com \
#     asterisk-chan-dongle
###############################################################################

# ── Stage 1: Build chan_dongle ──────────────────────────────────────────────
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        automake \
        asterisk-dev \
        libiconv-hook-dev \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY . /src/chan_dongle
WORKDIR /src/chan_dongle

RUN autoconf \
    && ./configure --with-asterisk=/usr/include \
    && make clean \
    && make

# ── Stage 2: Runtime image ─────────────────────────────────────────────────
FROM debian:bookworm-slim

LABEL maintainer="pulpoff"
LABEL description="Asterisk 20 + chan_dongle — GSM/IAX2 gateway for Huawei USB dongles"

RUN apt-get update && apt-get install -y --no-install-recommends \
        asterisk \
        asterisk-modules \
        usbutils \
        usb-modeswitch \
        usb-modeswitch-data \
        ca-certificates \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Copy the compiled chan_dongle module
COPY --from=builder /src/chan_dongle/chan_dongle.so /usr/lib/asterisk/modules/chan_dongle.so
RUN chmod 755 /usr/lib/asterisk/modules/chan_dongle.so

# Copy config templates (envsubst fills in IAX creds at startup)
COPY docker/configs/iax.conf.template      /etc/asterisk/templates/iax.conf.template
COPY docker/configs/extensions.conf.template /etc/asterisk/templates/extensions.conf.template
COPY docker/configs/dongle.conf.template    /etc/asterisk/templates/dongle.conf.template
COPY docker/configs/modules.conf            /etc/asterisk/modules.conf

# Copy entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# IAX2 default port
EXPOSE 4569/udp

# Environment variables the user must provide
ENV IAX_USER=""
ENV IAX_PASS=""
ENV IAX_HOST=""
ENV IAX_PORT="4569"
ENV DONGLE_CONTEXT="from-dongle"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["asterisk", "-f", "-vvv"]
