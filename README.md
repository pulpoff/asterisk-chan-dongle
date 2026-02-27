# chan_dongle — Huawei UMTS channel driver for Asterisk

This fork adds support for Asterisk 20.

The original chan_dongle code was written for Asterisk 1.8 and used
many APIs that were removed or changed in later versions. This fork
updates the module to compile and run against Asterisk 20, including:

* Opaque ast_channel structure (accessor functions instead of direct field access)
* New format capabilities API (ast_format_cap / ast_format_slin)
* Updated channel_request callback signature
* Updated ast_channel_alloc with assignedids/requestor parameters
* ast_bridged_channel replaced by ast_channel_bridge_peer
* Updated module registration (AST_MODULE_INFO with load_pri/support_level)
* Removed deprecated ASTERISK_FILE_VERSION macro

Tested with Asterisk 20.6.0 and Huawei E1762.

This channel driver should work with the following UMTS cards:
* Huawei K3715
* Huawei E169 / K3520
* Huawei E155X
* Huawei E175X
* Huawei K3765

Before using the channel driver make sure to:
* Disable PIN code on your SIM card

Supported features:
* Place voice calls and terminate voice calls
* Send SMS and receive SMS
* Send and receive USSD commands / messages

---

## Docker Quick Start

Plug in your Huawei dongle, then:

```bash
# 1. Download compose file and env template
curl -O https://raw.githubusercontent.com/pulpoff/asterisk-chan-dongle/master/docker-compose.yml
curl -o .env https://raw.githubusercontent.com/pulpoff/asterisk-chan-dongle/master/docker/.env.example

# 2. Edit .env with your trunk credentials
nano .env

# 3. Start
docker compose up -d
```

The container auto-restarts on reboot (`restart: unless-stopped`).

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TRUNK_PROTO` | no | `iax` | Trunk protocol: `iax`, `sip`, or `pjsip` |
| `TRUNK_USER` | **yes** | — | Trunk account username |
| `TRUNK_PASS` | **yes** | — | Trunk account password |
| `TRUNK_HOST` | **yes** | — | PBX server hostname or IP |
| `TRUNK_PORT` | no | `4569` (IAX) / `5060` (SIP) | Trunk port |
| `DONGLE_CONTEXT` | no | `from-dongle` | Dialplan context for inbound dongle calls |

### Verify It Works

```bash
# Check logs
docker logs asterisk-dongle

# You should see:
#   [dongle0] Dongle initialized and ready
#   Asterisk Ready.

# Enter Asterisk CLI
docker exec -it asterisk-dongle asterisk -rvvv

# Check dongle status
#   asterisk*CLI> dongle show devices
```

### Alternative: `docker run`

```bash
docker run -d \
  --name asterisk-dongle \
  --restart unless-stopped \
  --privileged \
  --net=host \
  -v /dev/bus/usb:/dev/bus/usb \
  -e TRUNK_PROTO=iax \
  -e TRUNK_USER=myuser \
  -e TRUNK_PASS=mypass \
  -e TRUNK_HOST=pbx.example.com \
  ghcr.io/pulpoff/asterisk-chan-dongle:latest
```

### Custom Config Overrides

To override any generated Asterisk config file:

```bash
mkdir configs
# Copy the generated config out, edit it, mount it back
docker cp asterisk-dongle:/etc/asterisk/dongle.conf configs/
nano configs/dongle.conf
```

Then uncomment the volume mount in `docker-compose.yml`:
```yaml
volumes:
  - ./configs:/etc/asterisk/custom:ro
```

Restart and your custom configs replace the generated ones.

---

## Building from source

Prerequisites:
```
apt install asterisk-dev
```

Build and install:
```
./configure
make
make install
```

---

## Dialplan examples

```ini
[dongle-incoming]
exten => sms,1,Verbose(Incoming SMS from ${CALLERID(num)} ${BASE64_DECODE(${SMS_BASE64})})
exten => sms,n,System(echo '${STRFTIME(${EPOCH},,%Y-%m-%d %H:%M:%S)} - ${DONGLENAME} - ${CALLERID(num)}: ${BASE64_DECODE(${SMS_BASE64})}' >> /var/log/asterisk/sms.txt)
exten => sms,n,Hangup()

exten => ussd,1,Verbose(Incoming USSD: ${BASE64_DECODE(${USSD_BASE64})})
exten => ussd,n,System(echo '${STRFTIME(${EPOCH},,%Y-%m-%d %H:%M:%S)} - ${DONGLENAME}: ${BASE64_DECODE(${USSD_BASE64})}' >> /var/log/asterisk/ussd.txt)
exten => ussd,n,Hangup()

exten => s,1,Dial(SIP/2001@othersipserver)
exten => s,n,Hangup()

[othersipserver-incoming]
exten => _X.,1,Dial(Dongle/r1/${EXTEN})
exten => _X.,n,Hangup
```

Dial string formats:

| Format | Example |
|--------|---------|
| Specific group | `Dongle/g1/${EXTEN}` |
| Round-robin group | `Dongle/r1/${EXTEN}` |
| Specific dongle | `Dongle/dongle0/${EXTEN}` |
| By provider name | `Dongle/p:PROVIDER NAME/${EXTEN}` |
| By IMEI | `Dongle/i:123456789012345/${EXTEN}` |
| By IMSI prefix | `Dongle/s:25099203948/${EXTEN}` |

## Useful AT commands

| Command | Description |
|---------|-------------|
| `AT+CCWA=0,0,1` | Disable call-waiting |
| `AT+CFUN=1,1` | Reset dongle |
| `AT^CARDLOCK="<code>"` | Unlock code |
| `AT^SYSCFG=13,0,3FFFFFFF,0,3` | 2G only, auto band, no roaming |
| `AT^U2DIAG=0` | Enable modem function |

How to store your own number:
```
dongle cmd dongle0 AT+CPBS="ON"
dongle cmd dongle0 AT+CPBW=1,"+123456789",145
```

## CLI commands

```
dongle reset <device>
dongle restart gracefully <device>
dongle restart now <device>
dongle restart when convenient <device>
dongle show device <device>
dongle show devices
dongle show version
dongle sms <device> number message
dongle ussd <device> ussd
dongle stop gracefully <device>
dongle stop now <device>
dongle stop when convenient <device>
dongle start <device>
dongle remove gracefully <device>
dongle remove now <device>
dongle remove when convenient <device>
dongle reload gracefully
dongle reload now
dongle reload when convenient
```

---

Original chan_dongle project: https://github.com/bg111/asterisk-chan-dongle/
