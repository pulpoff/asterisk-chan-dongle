###############################################################################
# Multi-arch Dockerfile: Asterisk 20 LTS (from source) + chan_dongle
# Builds for: linux/amd64, linux/arm64, linux/arm/v7
#
# Uses cross-compilation for ARM targets — the builder always runs natively
# on the build platform (amd64), avoiding QEMU compiler crashes entirely.
#
# Usage:
#   docker build -t asterisk-chan-dongle .
#   docker run --rm --privileged -v /dev/bus/usb:/dev/bus/usb \
#     -e TRUNK_PROTO=iax -e TRUNK_USER=myuser -e TRUNK_PASS=mypass \
#     -e TRUNK_HOST=pbx.example.com asterisk-chan-dongle
###############################################################################

# Builder runs natively on the build platform (no QEMU)
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS builder

ARG TARGETARCH
ARG BUILDARCH
ARG ASTERISK_VER=20-current

# ── Install native build tools ────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
        build-essential autoconf automake libtool \
        pkg-config ca-certificates wget bzip2 patch \
    && rm -rf /var/lib/apt/lists/*

# ── Install target-arch compiler + libraries ──────────────────────────────
# Native build: just install dev libs directly
# Cross build: add foreign arch, install cross-compiler + target dev libs
RUN set -eux; \
    if [ "$BUILDARCH" != "$TARGETARCH" ]; then \
        case "$TARGETARCH" in \
            arm64) DEBARCH=arm64; CROSS=aarch64-linux-gnu ;; \
            arm)   DEBARCH=armhf; CROSS=arm-linux-gnueabihf ;; \
            *)     echo "Unsupported cross target: $TARGETARCH"; exit 1 ;; \
        esac; \
        dpkg --add-architecture "$DEBARCH"; \
        apt-get update && apt-get install -y \
            gcc-${CROSS} g++-${CROSS} \
            libncurses5-dev:${DEBARCH} libxml2-dev:${DEBARCH} \
            libsqlite3-dev:${DEBARCH} uuid-dev:${DEBARCH} \
            libjansson-dev:${DEBARCH} libssl-dev:${DEBARCH} \
            libedit-dev:${DEBARCH} libsrtp2-dev:${DEBARCH}; \
    else \
        apt-get update && apt-get install -y \
            libncurses5-dev libxml2-dev libsqlite3-dev \
            uuid-dev libjansson-dev libssl-dev libedit-dev libsrtp2-dev; \
    fi \
    && rm -rf /var/lib/apt/lists/*

# ── Download Asterisk 20 LTS ─────────────────────────────────────────────
WORKDIR /src
RUN wget -q "https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VER}.tar.gz" \
    && tar xzf asterisk-${ASTERISK_VER}.tar.gz \
    && rm asterisk-${ASTERISK_VER}.tar.gz \
    && mv asterisk-20.* asterisk

WORKDIR /src/asterisk

# ── Configure Asterisk ────────────────────────────────────────────────────
# Cross-compile for ARM targets; native build if architectures match.
# --without-pjproject-bundled: use system jansson, skip bundled pjproject
# (pjproject bundled build has its own configure that breaks cross-compile)
RUN set -eux; \
    if [ "$BUILDARCH" != "$TARGETARCH" ]; then \
        case "$TARGETARCH" in \
            arm64) CROSS=aarch64-linux-gnu ;; \
            arm)   CROSS=arm-linux-gnueabihf ;; \
        esac; \
        ./configure --host=${CROSS} \
            CC=${CROSS}-gcc CXX=${CROSS}-g++ \
            PKG_CONFIG_LIBDIR=/usr/lib/${CROSS}/pkgconfig:/usr/share/pkgconfig \
            --without-pjproject-bundled; \
    else \
        ./configure --without-pjproject-bundled; \
    fi

# ── Select modules (menuselect runs on build platform natively) ───────────
RUN make menuselect.makeopts \
    && menuselect/menuselect \
        --enable chan_iax2 \
        --enable chan_sip \
        --enable format_gsm \
        --enable codec_alaw \
        --enable codec_ulaw \
        --enable codec_a_mu \
        --enable codec_g722 \
        --enable res_rtp_asterisk \
        --enable res_srtp \
        --enable res_timing_timerfd \
        menuselect.makeopts

# ── Build and install Asterisk ────────────────────────────────────────────
RUN make -j$(nproc) && make install

# ── Build chan_dongle against our Asterisk ─────────────────────────────────
COPY . /src/chan_dongle
WORKDIR /src/chan_dongle

RUN set -eux; \
    if [ "$BUILDARCH" != "$TARGETARCH" ]; then \
        case "$TARGETARCH" in \
            arm64) CROSS=aarch64-linux-gnu ;; \
            arm)   CROSS=arm-linux-gnueabihf ;; \
        esac; \
        ./configure --host=${CROSS} CC=${CROSS}-gcc \
            --with-asterisk=/src/asterisk/include; \
    else \
        ./configure --with-asterisk=/src/asterisk/include; \
    fi \
    && make

# ── Slim down: strip binaries, drop unnecessary modules and data ──────────
RUN set -eux; \
    if [ "$BUILDARCH" != "$TARGETARCH" ]; then \
        case "$TARGETARCH" in \
            arm64) STRIP=aarch64-linux-gnu-strip ;; \
            arm)   STRIP=arm-linux-gnueabihf-strip ;; \
        esac; \
    else \
        STRIP=strip; \
    fi; \
    $STRIP /usr/sbin/asterisk; \
    $STRIP /usr/sbin/rasterisk; \
    find /usr/lib/asterisk/modules -name '*.so' -exec $STRIP {} +; \
    find /usr/lib -maxdepth 1 -name 'libasterisk*' -exec $STRIP {} +; \
    $STRIP /src/chan_dongle/chan_dongle.so; \
    # ── Remove data dirs we don't need ──
    # NOTE: keep /var/lib/asterisk/documentation — Stasis/ACO needs the XML docs
    rm -rf /var/lib/asterisk/sounds \
           /var/lib/asterisk/moh \
           /var/lib/asterisk/static-http \
           /var/lib/asterisk/rest-api \
           /var/lib/asterisk/agi-bin \
           /var/lib/asterisk/phoneprov \
           /var/lib/asterisk/keys; \
    # ── Remove modules we don't need for a GSM gateway ──
    cd /usr/lib/asterisk/modules; \
    # CDR/CEL backends
    rm -f cdr_*.so cel_*.so; \
    # Database/directory backends
    rm -f res_odbc*.so res_config_odbc*.so res_config_ldap*.so \
          res_config_curl*.so; \
    # Services we don't use
    rm -f res_calendar*.so res_fax*.so res_speech*.so \
          res_phoneprov*.so res_adsi*.so res_smdi*.so \
          res_snmp*.so res_corosync*.so res_xmpp*.so \
          res_ari*.so \
          res_musiconhold*.so res_mwi_devstate*.so \
          res_parking*.so res_clioriginate*.so \
          res_hep*.so res_prometheus*.so; \
    # Apps we don't use
    rm -f app_voicemail*.so app_queue*.so app_confbridge*.so \
          app_adsiprog*.so app_alarmreceiver*.so app_festival*.so \
          app_followme*.so app_minivm*.so app_page*.so \
          app_agent_pool*.so app_directory*.so \
          app_meetme*.so app_mp3*.so app_skel*.so \
          app_jack*.so app_morsecode*.so app_saycounted*.so \
          app_statsd*.so app_test*.so; \
    # Channel drivers we don't use
    rm -f chan_mgcp*.so chan_skinny*.so chan_unistim*.so; \
    # Test modules
    rm -f test_*.so

# ── Stage 2: Slim runtime image ──────────────────────────────────────────
FROM debian:bookworm-slim

LABEL maintainer="pulpoff"
LABEL description="Asterisk 20 LTS + chan_dongle — GSM gateway with IAX2/SIP support"

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

# Copy only what we need from builder — no sounds, no docs, no sample configs
COPY --from=builder /usr/sbin/asterisk          /usr/sbin/asterisk
COPY --from=builder /usr/sbin/rasterisk         /usr/sbin/rasterisk
COPY --from=builder /usr/lib/asterisk/          /usr/lib/asterisk/
COPY --from=builder /usr/lib/libasterisk*       /usr/lib/
COPY --from=builder /var/lib/asterisk/          /var/lib/asterisk/
COPY --from=builder /src/chan_dongle/chan_dongle.so /usr/lib/asterisk/modules/chan_dongle.so

# Create required dirs, user, and minimal config structure
RUN groupadd -r asterisk \
    && useradd -r -g asterisk -d /var/lib/asterisk -s /sbin/nologin asterisk \
    && mkdir -p /var/log/asterisk /var/run/asterisk /var/spool/asterisk \
               /etc/asterisk/tls \
    && chown -R asterisk:asterisk /etc/asterisk /var/lib/asterisk \
       /var/log/asterisk /var/run/asterisk /var/spool/asterisk \
       /usr/lib/asterisk

# Copy our configs (no sample configs from Asterisk — only what we need)
COPY docker/configs/asterisk.conf /etc/asterisk/asterisk.conf
COPY docker/configs/logger.conf  /etc/asterisk/logger.conf
COPY docker/configs/modules.conf /etc/asterisk/modules.conf
COPY docker/configs/ /etc/asterisk/templates/

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
