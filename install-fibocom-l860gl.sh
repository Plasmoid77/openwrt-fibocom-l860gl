#!/bin/sh
#
# install-fibocom-l860gl.sh
# One-shot installer for Fibocom L860-GL (Intel XMM7560)
# on a clean OpenWrt 25.x (apk-based) router.
#
# Installs: XMM proto/drivers (via 132lan modem feed), sms-tool,
#           luci-app-3ginfo-lite + luci-app-sms-tool-js + luci-app-modemband
#           (from 4IceG apk repo) + Russian translations,
#           auto-detects and sets the AT port, and creates a ready-to-use
#           XMM network interface (APN prompted at install time) in the
#           firewall WAN zone.
#
# Differences vs the DW5821e script:
#   - DW5821e = Qualcomm  -> MBIM stack, AT port /dev/ttyUSB1, needs CRLF JSON fix
#   - L860-GL = Intel XMM -> xmm proto, AT port /dev/ttyACM* (auto-detected),
#                            no CRLF fix needed (3ginfo data parses cleanly here)
#
# Transparent-proxy note (Clash / Mihomo / SSClash ...):
#   The .ru modem feed (openwrt.132lan.ru) is often unreachable directly under a
#   transparent proxy -> wget dies with "Failed to send request: Operation not
#   permitted". We NEVER stop the proxy to work around this: in whitelist/bypass
#   mode the proxy is the router's only route to the internet, so stopping it
#   would cut the connection mid-install. Instead we route our OWN downloads
#   through the local Mihomo HTTP proxy (default http://127.0.0.1:7890), exactly
#   like openwrt-ssclash's "update behind whitelists". uclient-fetch and apk both
#   honour http_proxy/https_proxy. Override the proxy with CLASH_PROXY=http://IP:PORT.
#
# Usage:
#   scp this file to the router (e.g. /tmp), then:
#   sh /tmp/install-fibocom-l860gl.sh
#   (optional)  CLASH_PROXY=http://127.0.0.1:7890 sh /tmp/install-fibocom-l860gl.sh
#
# Re-running is safe: every step is idempotent.

set -e

AT_PORT_DEFAULT="/dev/ttyACM0"  # L860-GL AT port is cdc-acm (ttyACM*), NOT ttyUSB
FEEDS="/etc/apk/repositories.d/customfeeds.list"
KEYDIR="/etc/apk/keys"
# Direct raw.githubusercontent.com URLs (NOT github.com/.../raw/..., which 302-
# redirects -- uclient-fetch cannot follow redirects once a proxy is in play).
REPO_ADB="https://raw.githubusercontent.com/4IceG/Modem-extras-apk/main/myapk/packages.adb"
REPO_KEY="https://raw.githubusercontent.com/4IceG/Modem-extras-apk/main/myapk/IceG-apkpub.pem"
LAN132_BASE="https://openwrt.132lan.ru/packages"
CLASH_PROXY_DEFAULT="http://127.0.0.1:7890"   # ssclash/Mihomo mixed-port default

# --- Network interface settings --------------------------------------------
CREATE_INTERFACE="yes"          # yes | no  -- create the XMM interface
IFACE_NAME="LTE_Fibocom_860"    # interface (and UCI section) name
FW_ZONE="wan"                   # firewall zone to place the interface into
APN_DEFAULT="internet"          # used if you just press Enter at the prompt
PDP_TYPE="IPV4V6"               # IP (IPv4) | IPV6 | IPV4V6 (dual-stack)
PIN_CODE=""                     # SIM PIN, leave empty if the SIM has none

# --- 4IceG panel settings --------------------------------------------------
SMS_PREFIX="7"                  # country dialing prefix for sms-tool (48=PL, 7=RU)

say() { echo ""; echo ">>> $1"; }

# --- Download + proxy helpers ----------------------------------------------
# dl <url> <outfile|-> : prefer curl (reliable HTTPS CONNECT through a proxy;
# always present on ssclash routers), else fall back to uclient-fetch. Both
# honour the http_proxy/https_proxy we may export below.
dl() {
    _url="$1"; _out="$2"
    if command -v curl >/dev/null 2>&1; then
        if [ "$_out" = "-" ]; then curl -fsSL "$_url"; else curl -fsSL -o "$_out" "$_url"; fi
    else
        wget "$_url" -O "$_out"
    fi
}

feed_reachable() {
    # Probe the actual add.sh for this release (a real file), not the directory
    # index -- so it still works if the server ever disables directory listing.
    _u="${ADD_SH_URL:-${LAN132_BASE}/}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsS -m 8 -o /dev/null "$_u" 2>/dev/null
    else
        wget -q -O /dev/null -T 8 "$_u" 2>/dev/null
    fi
}

clash_running() {
    pidof clash >/dev/null 2>&1 || pidof mihomo >/dev/null 2>&1
}

# Make sure openwrt.132lan.ru is reachable, WITHOUT ever stopping the proxy.
# 1) reachable as-is (direct, or an already-exported proxy env)  -> done
# 2) proxy running -> route our downloads through it, re-test    -> done
# 3) still blocked -> actionable hint, exit (proxy left untouched)
ensure_feed_reachable() {
    if feed_reachable; then return 0; fi

    if clash_running; then
        _p="${CLASH_PROXY:-$CLASH_PROXY_DEFAULT}"
        echo "   132lan feed not reachable directly -> routing downloads via $_p (proxy stays up)"
        export http_proxy="$_p" https_proxy="$_p"
        _lan="$(uci -q get network.lan.ipaddr 2>/dev/null)"
        export no_proxy="127.0.0.1,localhost,::1${_lan:+,$_lan}"
        unset _lan
        if feed_reachable; then
            echo "   OK: feed reachable through the proxy"
            return 0
        fi
        unset http_proxy https_proxy no_proxy   # proxy didn't help; don't drag it into apk
    fi

    echo ""
    echo "ERROR: cannot reach ${ADD_SH_URL:-$LAN132_BASE} (required for luci-proto-xmm / xmm-modem)."
    if clash_running; then
        echo "  A proxy is running but this domain is still blocked. Allow it in your"
        echo "  Mihomo config and reload, e.g.:"
        echo "      rules:"
        echo "        - DOMAIN-SUFFIX,132lan.ru,DIRECT   # or PROXY in whitelist mode"
        echo "  Also check that mixed-port is 7890 (or pass CLASH_PROXY=http://IP:PORT)."
    else
        echo "  No Clash/Mihomo proxy detected and the host is unreachable directly."
        echo "  Check the router's internet connection, then re-run."
    fi
    exit 1
}

# --- Ask for the APN up front so the rest can run unattended ---------------
APN="$APN_DEFAULT"
if [ "$CREATE_INTERFACE" = "yes" ]; then
    printf 'APN for the LTE interface [%s]: ' "$APN_DEFAULT"
    read -r apn_input || apn_input=""
    [ -n "$apn_input" ] && APN="$apn_input"
    echo "   using APN: $APN"
fi

# --- Ask whether to install Russian translations ---------------------------
# Covers all three 4IceG panels: 3ginfo-lite, sms-tool-js and modemband.
INSTALL_RU="yes"
printf 'Install Russian translations for the 4IceG panels? [Y/n]: '
read -r ru_input || ru_input=""
case "$ru_input" in
    [Nn]*) INSTALL_RU="no" ;;
    *)     INSTALL_RU="yes" ;;
esac
echo "   Russian translations: $INSTALL_RU"

# --- 1. Drivers: XMM proto + serial/ACM AT ports ---------------------------
# The 132lan add.sh registers the modem feed; `apk add luci-proto-xmm` then
# pulls xmm-modem, kmod-usb-net-cdc-ncm, kmod-usb-acm, kmod-usb-serial-option,
# i.e. everything the L860-GL needs (cdc-acm gives us the /dev/ttyACM* AT port).
say "Step 1: installing modem drivers (XMM proto via 132lan feed)"
# Work out the exact feed URL first so the reachability probe hits a real file
# (add.sh for this release) rather than a directory index.
. /etc/openwrt_release
REL="${DISTRIB_RELEASE%.*}"          # e.g. 25.12.4 -> 25.12
ADD_SH_URL="${LAN132_BASE}/${REL}/packages/add.sh"
# Reachability + proxy routing BEFORE the first apk update: in whitelist mode
# even the official feeds are reachable only through the proxy, so the env has
# to be set first. From here on every apk update also refreshes the 132lan repo.
ensure_feed_reachable
apk update
cd /tmp
dl "$ADD_SH_URL" /tmp/add.sh
sh /tmp/add.sh
apk add luci-proto-xmm
apk add sms-tool

# --- 2. Add 4IceG apk repository (idempotent) ------------------------------
say "Step 2: adding 4IceG apk repository"
if ! grep -qF "$REPO_ADB" "$FEEDS" 2>/dev/null; then
    echo "$REPO_ADB" >> "$FEEDS"
    echo "   repo line added"
else
    echo "   repo line already present, skipping"
fi

mkdir -p "$KEYDIR"
if [ ! -s "$KEYDIR/IceG-apkpub.pem" ]; then
    dl "$REPO_KEY" "$KEYDIR/IceG-apkpub.pem"
    echo "   signing key installed"
else
    echo "   signing key already present, skipping"
fi
apk update

# --- 3. Install the plugins ------------------------------------------------
say "Step 3: installing 3ginfo-lite, sms-tool-js and modemband"
apk add luci-app-3ginfo-lite
apk add luci-app-sms-tool-js
# modemband: GUI band-locking for L860-GL (drives AT+XACT under the hood).
apk add luci-app-modemband

if [ "$INSTALL_RU" = "yes" ]; then
    say "Step 3: installing Russian translations"
    # Installed best-effort: a missing -ru package can't abort the run.
    apk add luci-i18n-3ginfo-lite-ru  || echo "   (3ginfo RU not in feed, skipping)"
    apk add luci-i18n-sms-tool-js-ru  || echo "   (sms-tool-js RU not in feed, skipping)"
    apk add luci-i18n-modemband-ru    || echo "   (modemband RU not in feed, skipping)"
fi

# --- 4. Detect + set the AT port -------------------------------------------
# L860-GL exposes several /dev/ttyACM* ports; only one answers AT commands.
# We probe ttyACM0..3 with ATI and pick the one that identifies as Fibocom/L860
# (falling back to the first AT-capable port, then to the default).
say "Step 4: detecting modem AT port"
AT_PORT=""
if command -v sms_tool >/dev/null 2>&1; then
    for p in /dev/ttyACM0 /dev/ttyACM1 /dev/ttyACM2 /dev/ttyACM3; do
        [ -c "$p" ] || continue
        resp="$(sms_tool -d "$p" at "ATI" 2>/dev/null || true)"
        if echo "$resp" | grep -qiE 'Fibocom|L860'; then
            AT_PORT="$p"; break
        fi
        if [ -z "$AT_PORT" ] && echo "$resp" | grep -qi 'OK'; then
            AT_PORT="$p"   # remember first AT-capable port, keep looking for L860
        fi
    done
fi
[ -n "$AT_PORT" ] || AT_PORT="$AT_PORT_DEFAULT"

say "Step 4: setting AT port to $AT_PORT"
if [ "$AT_PORT" = "$AT_PORT_DEFAULT" ] && ! [ -c "$AT_PORT" ]; then
    echo "   NOTE: could not probe a live AT port (modem may enumerate after reboot)."
    echo "   Using default $AT_PORT. Verify after reboot with:"
    echo "       ls -l /dev/ttyACM* ; sms_tool -d /dev/ttyACM0 at ATI"
    echo "   and if needed:  uci set 3ginfo.@3ginfo[0].device=/dev/ttyACMx; uci commit 3ginfo"
fi
uci set 3ginfo.@3ginfo[0].device="$AT_PORT"
[ "$CREATE_INTERFACE" = "yes" ] && uci set 3ginfo.@3ginfo[0].network="$IFACE_NAME"
uci commit 3ginfo

# --- 5. Create the XMM network interface -----------------------------------
# Builds a ready-to-use interface: proto=xmm, the auto-detected modem port,
# the APN entered above, and membership in the WAN firewall zone.
if [ "$CREATE_INTERFACE" = "yes" ]; then
    say "Step 5: creating interface '$IFACE_NAME' (proto xmm, port $AT_PORT, APN $APN)"

    uci set network."$IFACE_NAME"=interface
    uci set network."$IFACE_NAME".proto='xmm'
    uci set network."$IFACE_NAME".device="$AT_PORT"
    uci set network."$IFACE_NAME".apn="$APN"
    uci set network."$IFACE_NAME".pdptype="$PDP_TYPE"
    uci set network."$IFACE_NAME".auth='none'
    if [ -n "$PIN_CODE" ]; then
        uci set network."$IFACE_NAME".pincode="$PIN_CODE"
    fi
    uci commit network

    # Put the interface into the firewall zone (default: wan).
    ZONE_SECT="$(uci show firewall 2>/dev/null | grep "\.name='${FW_ZONE}'" | head -n1 | sed "s/\.name='${FW_ZONE}'.*//")"
    if [ -n "$ZONE_SECT" ]; then
        uci -q del_list "${ZONE_SECT}".network="$IFACE_NAME"   # avoid duplicates
        uci add_list "${ZONE_SECT}".network="$IFACE_NAME"
        uci commit firewall
        echo "   added '$IFACE_NAME' to firewall zone '$FW_ZONE'"
    else
        echo "   WARNING: firewall zone '$FW_ZONE' not found."
        echo "   Add '$IFACE_NAME' to a WAN zone manually in LuCI -> Firewall."
    fi
fi

# --- 6. Configure the 4IceG panels (modemband + sms-tool) ------------------
# Point modemband and sms-tool at the detected AT port, bind modemband to the
# LTE interface, and set the SMS dialing prefix. Each block is guarded on its
# config file so a skipped/absent panel can't abort the run.
say "Step 6: configuring 4IceG panels (port $AT_PORT)"

if [ -f /etc/config/modemband ]; then
    uci set modemband.@modemband[0].set_port="$AT_PORT"
    if [ "$CREATE_INTERFACE" = "yes" ]; then
        uci set modemband.@modemband[0].iface="$IFACE_NAME"
        uci commit modemband
        echo "   modemband: port=$AT_PORT, iface=$IFACE_NAME"
    else
        uci commit modemband
        echo "   modemband: port=$AT_PORT"
    fi
fi

if [ -f /etc/config/sms_tool_js ]; then
    S="sms_tool_js.@sms_tool_js[0]"
    uci set "$S".pnumber="$SMS_PREFIX"
    # All five SMS/USSD/AT/call/read ports -> the detected AT port.
    uci set "$S".readport="$AT_PORT"    # чтение SMS
    uci set "$S".callport="$AT_PORT"    # журнал вызовов
    uci set "$S".sendport="$AT_PORT"    # отправка SMS
    uci set "$S".ussdport="$AT_PORT"    # USSD
    uci set "$S".atport="$AT_PORT"      # AT-команды
    uci commit sms_tool_js
    echo "   sms-tool: prefix=$SMS_PREFIX, all ports=$AT_PORT"
fi

# --- 7. Restart web UI -----------------------------------------------------
say "Step 7: restarting web interface"
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

# --- 8. Reboot -------------------------------------------------------------
# A full reboot ensures modem drivers, ttyACM ports and the web UI all come
# up cleanly from scratch. The reminder is printed BEFORE the countdown so
# there's time to read it (and cancel with Ctrl+C).
say "Step 8: installation complete"
echo "    После перезагрузки:"
echo "      - LuCI -> Network -> Interfaces: у '$IFACE_NAME' должны появиться Carrier/RX/TX."
echo "        Если Carrier остаётся 'Absent' — обычно дело в APN (исправь и Save & Apply)."
echo "      - LuCI -> Modem(s): обнови Ctrl+F5 для сигнала / оператора / бэнда."
echo "    Если 3ginfo не показывает данные модема — проверь AT-порт:"
echo "        ls -l /dev/ttyACM* ; sms_tool -d /dev/ttyACM0 at ATI"
echo "        uci set 3ginfo.@3ginfo[0].device=/dev/ttyACMx; uci commit 3ginfo; /etc/init.d/uhttpd restart"

echo ""
echo ">>> Перезагрузка через 10 секунд (Ctrl+C — отмена)"
i=10
while [ "$i" -gt 0 ]; do
    printf '\r   перезагрузка через %2d с ... ' "$i"
    sleep 1
    i=$((i - 1))
done
echo ""
sync
reboot
