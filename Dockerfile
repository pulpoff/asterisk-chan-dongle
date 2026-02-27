###############################################################################
# Multi-arch Dockerfile: Asterisk 20 LTS (from source) + chan_dongle
# Builds for: linux/amd64, linux/arm64, linux/arm/v7
#
# Turns any Raspberry Pi / Orange Pi / x86 box with a Huawei USB dongle
# into a GSM gateway. Supports IAX2, chan_sip, and PJSIP trunks.
#
# Usage:
#   docker build -t asterisk-chan-dongle .
#   docker run --rm --privileged -v /dev/bus/usb:/dev/bus/usb \
#     -e TRUNK_PROTO=iax -e TRUNK_USER=myuser -e TRUNK_PASS=mypass \
#     -e TRUNK_HOST=pbx.example.com asterisk-chan-dongle
###############################################################################

# ── Stage 1: Build Asterisk 20 LTS + chan_dongle from source ────────────────
FROM debian:bookworm-slim AS builder

ARG ASTERISK_VER=20-current

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        libtool \
        pkg-config \
        ca-certificates \
        wget \
        # Asterisk build dependencies
        libncurses5-dev \
        libxml2-dev \
        libsqlite3-dev \
        uuid-dev \
        libjansson-dev \
        libssl-dev \
        libedit-dev \
        libsrtp2-dev \
        # chan_dongle needs iconv
        libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Build Asterisk 20 LTS ──────────────────────────────────────────────────
WORKDIR /src
RUN wget -q "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VER}.tar.gz" \
    && tar xzf asterisk-${ASTERISK_VER}.tar.gz \
    && rm asterisk-${ASTERISK_VER}.tar.gz \
    && mv asterisk-20.* asterisk

WORKDIR /src/asterisk
RUN ./configure --with-jansson-bundled \
    && make menuselect.makeopts \
    && menuselect/menuselect \
        --enable chan_iax2 \
        --enable chan_sip \
        --enable chan_pjsip \
        --enable format_gsm \
        --enable codec_ulaw \
        --enable codec_alaw \
        --enable codec_gsm \
        --enable res_rtp_asterisk \
        --enable res_pjsip \
        --enable res_pjsip_session \
        --enable res_pjsip_authenticator_digest \
        --enable res_pjsip_outbound_authenticator_digest \
        --enable res_pjsip_registrar \
        --enable res_pjsip_outbound_registration \
        --enable res_pjsip_endpoint_identifier_ip \
        --enable res_pjsip_endpoint_identifier_user \
        --enable res_srtp \
        menuselect.makeopts \
    && make -j$(nproc) \
    && make install \
    && make samples

# ── Build chan_dongle against our Asterisk ──────────────────────────────────
COPY . /src/chan_dongle
WORKDIR /src/chan_dongle

RUN ./configure --with-asterisk=/src/asterisk/include \
    && make

# ── Stage 2: Slim runtime image ────────────────────────────────────────────
FROM debian:bookworm-slim

LABEL maintainer="pulpoff"
LABEL description="Asterisk 20 LTS + chan_dongle — GSM gateway with IAX2/SIP/PJSIP support"

# Runtime dependencies only (no compilers)
RUN apt-get update && apt-get install -y --no-install-recommends \
        libncurses6 \
        libxml2 \
        libsqlite3-0 \
        libuuid1 \
        libjansson4 \
        libssl3 \
        libedit2 \
        libsrtp2-1 \
        usbutils \
        usb-modeswitch \
        usb-modeswitch-data \
        ca-certificates \
        openssl \
        gettext-base \
    && rm -rf /var/lib/apt/lists/*

# Copy Asterisk installation from builder (binaries, modules, bundled libs, data, configs)
COPY --from=builder /usr/sbin/asterisk          /usr/sbin/asterisk
COPY --from=builder /usr/sbin/rasterisk         /usr/sbin/rasterisk
COPY --from=builder /usr/lib/asterisk/          /usr/lib/asterisk/
COPY --from=builder /usr/lib/libasterisk*       /usr/lib/
COPY --from=builder /var/lib/asterisk/          /var/lib/asterisk/
COPY --from=builder /var/spool/asterisk/        /var/spool/asterisk/
COPY --from=builder /etc/asterisk/              /etc/asterisk/

# Copy chan_dongle module
COPY --from=builder /src/chan_dongle/chan_dongle.so /usr/lib/asterisk/modules/chan_dongle.so

# Create required dirs and asterisk user
RUN groupadd -r asterisk \
    && useradd -r -g asterisk -d /var/lib/asterisk -s /sbin/nologin asterisk \
    && mkdir -p /var/log/asterisk /var/run/asterisk /var/spool/asterisk /etc/asterisk/tls \
    && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk \
       /var/log/asterisk /var/run/asterisk /var/spool/asterisk \
       /usr/lib/asterisk

# Copy config templates (entrypoint picks the right ones based on TRUNK_PROTO)
COPY docker/configs/ /etc/asterisk/templates/
COPY docker/configs/modules.conf /etc/asterisk/modules.conf

# Copy entrypoint
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose ports: IAX2, SIP (UDP + TLS), RTP range
EXPOSE 4569/udp
EXPOSE 5060/udp
EXPOSE 5061/tcp
EXPOSE 10000-10100/udp

# Environment variables
ENV TRUNK_PROTO="iax"
ENV TRUNK_USER=""
ENV TRUNK_PASS=""
ENV TRUNK_HOST=""
ENV TRUNK_PORT=""
ENV DONGLE_CONTEXT="from-dongle"

ENTRYPOINT ["/entrypoint.sh"]
CMD ["asterisk", "-f", "-vvv"]
